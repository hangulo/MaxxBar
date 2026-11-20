import Foundation
import CryptoKit

struct ClaudeOAuthCredential {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let refreshExpiresAt: Date?
    let scopes: [String]

    init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String, !access.isEmpty else { return nil }
        accessToken = access
        refreshToken = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        refreshExpiresAt = (oauth["refreshTokenExpiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        scopes = oauth["scopes"] as? [String] ?? []
    }

    func isValid(at date: Date) -> Bool { expiresAt.map { $0 > date } ?? true }
    var fingerprint: String {
        SHA256.hash(data: Data((accessToken + "|" + (refreshToken ?? "")).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// What Claude Code's stored sign-in says, read once from the raw JSON. After a sign-in ends the item stays with
/// empty tokens, `loginEnded` (e.g. "time_limit") and `refreshTokenExpiresAt`, so `credential` is nil but the rest is not.
struct ClaudeStoredSignIn {
    var credential: ClaudeOAuthCredential?
    var loginEnded: String?
    /// The hard end of the sign-in (`refreshTokenExpiresAt`); renewals cannot extend it.
    var endsAt: Date?

    init(credential: ClaudeOAuthCredential?, loginEnded: String? = nil, endsAt: Date? = nil) {
        self.credential = credential
        self.loginEnded = loginEnded
        self.endsAt = endsAt ?? credential?.refreshExpiresAt
    }

    init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
        credential = ClaudeOAuthCredential(data: data)
        loginEnded = (oauth["loginEnded"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        endsAt = (oauth["refreshTokenExpiresAt"] as? NSNumber)
            .flatMap { $0.doubleValue > 0 ? Date(timeIntervalSince1970: $0.doubleValue / 1000) : nil }
    }
}

/// Why Claude Code needs a new sign-in, so the runway card can offer "Sign in again".
enum ClaudeSignInProblem: Equatable {
    /// The sign-in reached its hard time limit (`loginEnded == "time_limit"`).
    case timeLimit
    /// Signed out, empty or missing for any other reason.
    case signedOut
    /// The token expired and could not be renewed (keep-alive off or gave up).
    case expired
}

/// Outcome of one keep-alive run, without any CLI output (it could contain account details).
struct ClaudeKeepAliveRun {
    var exitCode: Int32?
    var duration: TimeInterval
    /// "not-found", "launch-failed", "timeout" or "exit-<code>"; nil on a clean exit.
    var errorClass: String?
}

/// Claude Code owns token exchange, rotation, and storage; MaxxBar never writes the Keychain and never runs
/// `claude auth login`. When the stored access token has expired (or Claude rejects it), MaxxBar runs one tiny
/// `claude -p` request, which makes Claude Code refresh and save its own sign-in, then verifies the Keychain.
/// A failed attempt is retried once after 10 minutes; after that it stops until the credential changes.
final class ClaudeCredentialManager: @unchecked Sendable {
    struct ReadResult {
        var accessToken: String?
        var error: String?
        /// True when a keep-alive just produced this token, so the caller should read usage right away.
        var refreshed = false
        /// The hard end of the current sign-in, when Claude Code recorded one.
        var signInEndsAt: Date?
        /// Set when only a new `claude auth login` can restore live limits.
        var signInProblem: ClaudeSignInProblem?
    }
    struct KeepAliveState: Codable, Equatable {
        var fingerprint: String
        var attempts: Int
        var nextAttemptAt: Date
    }
    static let keepAliveDefaultsKey = "ClaudeKeepAlive"
    static let retryDelay: TimeInterval = 600
    static let maxAttempts = 2
    static let gaveUpMessage = "Couldn't refresh Claude Code's sign-in automatically. Click Sign in again to reconnect."
    static let expiredMessage = "Claude Code's sign-in has expired. Click Sign in again to reconnect."
    static let timeLimitMessage = "Your Claude Code sign-in reached its time limit and was signed out. Click Sign in again to reconnect."
    static let signedOutMessage = "Claude Code is signed out. Click Sign in again to reconnect."
    /// How early the runway card starts warning that the sign-in will end.
    static let signInWarningLead: TimeInterval = 7 * 86_400

    /// The amber line shown within 7 days of the sign-in's hard end; nil outside that window or once it has ended.
    static func signInWarning(endsAt: Date?, now: Date = Date()) -> String? {
        guard let endsAt, endsAt > now, endsAt.timeIntervalSince(now) <= signInWarningLead else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return "Claude Code sign-in ends \(formatter.string(from: endsAt)). Sign in again before then to stay connected."
    }

    static let shared = ClaudeCredentialManager(
        loadSignIn: loadSignIn,
        keepAlive: runKeepAlive,
        stateURL: supportURL.appendingPathComponent("claude-keepalive-state.json"),
        logURL: supportURL.appendingPathComponent("claude-keepalive.log"),
        enabled: UserDefaults.standard.object(forKey: keepAliveDefaultsKey) as? Bool ?? true
    )
    static var supportURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/MaxxBar")
    }
    private let lock = NSLock()
    private let load: () -> ClaudeStoredSignIn
    private let keepAlive: () -> ClaudeKeepAliveRun
    private let stateURL: URL
    private let logURL: URL?
    private let clock: () -> Date
    private let enabled: Bool
    private(set) var state: KeepAliveState?
    /// The last credential read. Reading it launches /usr/bin/security, so a still-valid token is reused
    /// until its own expiry or until Claude rejects it.
    private var cached: ClaudeOAuthCredential?
    private var cachedEndsAt: Date?
    /// The sign-in end and problem from the latest read, including the retry after a rejected token.
    private(set) var lastSignIn: (endsAt: Date?, problem: ClaudeSignInProblem?) = (nil, nil)

    init(loadSignIn: @escaping () -> ClaudeStoredSignIn, keepAlive: @escaping () -> ClaudeKeepAliveRun,
         stateURL: URL, logURL: URL? = nil, clock: @escaping () -> Date = Date.init, enabled: Bool = true) {
        self.load = loadSignIn
        self.keepAlive = keepAlive
        self.stateURL = stateURL
        self.logURL = logURL
        self.clock = clock
        self.enabled = enabled
        state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(KeepAliveState.self, from: $0) }
    }

    convenience init(load: @escaping () -> ClaudeOAuthCredential?, keepAlive: @escaping () -> ClaudeKeepAliveRun,
                     stateURL: URL, logURL: URL? = nil, clock: @escaping () -> Date = Date.init, enabled: Bool = true) {
        self.init(loadSignIn: { ClaudeStoredSignIn(credential: load()) }, keepAlive: keepAlive,
                  stateURL: stateURL, logURL: logURL, clock: clock, enabled: enabled)
    }

    func read(rejectedAccessToken: String? = nil) -> ReadResult {
        lock.lock()
        defer { lock.unlock() }
        let result = readLocked(rejectedAccessToken: rejectedAccessToken)
        lastSignIn = (result.signInEndsAt, result.signInProblem)
        return result
    }

    private func readLocked(rejectedAccessToken: String?) -> ReadResult {
        let now = clock()
        if rejectedAccessToken == nil, let cached, cached.isValid(at: now) {
            return ReadResult(accessToken: cached.accessToken, signInEndsAt: cachedEndsAt)
        }
        cached = nil
        let stored = load()
        let endsAt = stored.endsAt
        guard let credential = stored.credential else {
            let timeLimit = stored.loginEnded == "time_limit"
            return ReadResult(error: timeLimit ? Self.timeLimitMessage : Self.signedOutMessage, signInEndsAt: endsAt,
                              signInProblem: timeLimit ? .timeLimit : .signedOut)
        }
        let rejected = rejectedAccessToken == credential.accessToken
        // Claude Code refreshes once its token has expired, so the keep-alive waits for expiry.
        guard rejected || !credential.isValid(at: now) else {
            // Without an expiry the token cannot be cached safely; read it again next time.
            if credential.expiresAt != nil {
                cached = credential
                cachedEndsAt = endsAt
            }
            return ReadResult(accessToken: credential.accessToken, signInEndsAt: endsAt)
        }
        guard enabled else {
            return ReadResult(error: Self.expiredMessage, signInEndsAt: endsAt, signInProblem: .expired)
        }
        let previous = state?.fingerprint == credential.fingerprint ? state : nil
        if let previous {
            if previous.attempts >= Self.maxAttempts {
                return ReadResult(error: Self.gaveUpMessage, signInEndsAt: endsAt, signInProblem: .expired)
            }
            if previous.nextAttemptAt > now {
                let retry = previous.nextAttemptAt.formatted(date: .omitted, time: .shortened)
                return ReadResult(error: "Couldn't refresh Claude Code's sign-in yet; trying again at \(retry).", signInEndsAt: endsAt)
            }
        }
        // Record the attempt first so a crash or restart mid-run cannot turn into a loop.
        let attempts = (previous?.attempts ?? 0) + 1
        state = KeepAliveState(fingerprint: credential.fingerprint, attempts: attempts,
                               nextAttemptAt: now.addingTimeInterval(Self.retryDelay))
        persistState()
        let run = keepAlive()
        let afterStored = load()
        let after = afterStored.credential
        let renewed = after.map { current in
            current.accessToken != credential.accessToken && current.refreshToken != nil
                && current.isValid(at: clock())
                && (current.expiresAt ?? .distantFuture) > (credential.expiresAt ?? .distantPast)
        } ?? false
        appendLog(run: run, before: credential.expiresAt, after: after?.expiresAt, renewed: renewed, attempt: attempts)
        if renewed, let after {
            cached = after
            cachedEndsAt = afterStored.endsAt
            clearStateLocked()
            return ReadResult(accessToken: after.accessToken, refreshed: true, signInEndsAt: afterStored.endsAt)
        }
        if afterStored.credential == nil, afterStored.loginEnded == "time_limit" {
            return ReadResult(error: Self.timeLimitMessage, signInEndsAt: afterStored.endsAt, signInProblem: .timeLimit)
        }
        if attempts >= Self.maxAttempts {
            return ReadResult(error: Self.gaveUpMessage, signInEndsAt: endsAt, signInProblem: .expired)
        }
        let retry = now.addingTimeInterval(Self.retryDelay).formatted(date: .omitted, time: .shortened)
        return ReadResult(error: "Couldn't refresh Claude Code's sign-in yet; trying again at \(retry).", signInEndsAt: endsAt)
    }

    /// Fingerprint of the stored sign-in right now (nil when signed out), read fresh. Used as the baseline
    /// before "Sign in again", so an unchanged credential is not mistaken for the new sign-in.
    func currentSignInFingerprint() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return load().credential?.fingerprint
    }

    /// After "Sign in again": true once a valid credential other than `previousFingerprint` is stored.
    /// Adopts it and clears the keep-alive state. Reads storage only; never calls the usage endpoint.
    func adoptNewSignIn(replacing previousFingerprint: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let stored = load()
        guard let credential = stored.credential, credential.fingerprint != previousFingerprint,
              credential.isValid(at: clock()) else { return false }
        cached = credential
        cachedEndsAt = stored.endsAt
        lastSignIn = (stored.endsAt, nil)
        clearStateLocked()
        return true
    }

    private func clearStateLocked() {
        state = nil
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func persistState() {
        guard let state, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    /// Diagnostics only: timestamps, exit status and expiry times. Never tokens or CLI output.
    private func appendLog(run: ClaudeKeepAliveRun, before: Date?, after: Date?, renewed: Bool, attempt: Int) {
        guard let logURL else { return }
        let iso = ISO8601DateFormatter()
        let line = [
            iso.string(from: clock()),
            "attempt=\(attempt)",
            "exit=\(run.exitCode.map(String.init) ?? "none")",
            "duration=\(String(format: "%.1f", run.duration))s",
            "expiresBefore=\(before.map(iso.string(from:)) ?? "none")",
            "expiresAfter=\(after.map(iso.string(from:)) ?? "none")",
            "result=\(renewed ? "renewed" : (run.errorClass ?? "no-new-token"))"
        ].joined(separator: " ") + "\n"
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
    }

    /// Reads `~/.claude/.credentials.json` and the "Claude Code-credentials" Keychain item once each (read-only).
    static func loadSignIn() -> ClaudeStoredSignIn {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.credentials.json")
        let file = (try? Data(contentsOf: url)).flatMap(ClaudeStoredSignIn.init(data:))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        var keychain: ClaudeStoredSignIn?
        if (try? process.run()) != nil {
            if finished.wait(timeout: .now() + 10) == .success {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 { keychain = ClaudeStoredSignIn(data: data) }
            } else {
                process.terminate()
            }
        }
        // A stale file must not mask a newly rotated Keychain credential, or vice versa.
        let usable = [file, keychain].compactMap { $0 }.filter { $0.credential != nil }.max {
            ($0.credential?.expiresAt ?? .distantPast) < ($1.credential?.expiresAt ?? .distantPast)
        }
        // Signed out everywhere: the Keychain item still says why and when the sign-in ended.
        return usable ?? keychain ?? file ?? ClaudeStoredSignIn(credential: nil)
    }

    static var claudeExecutableCandidates: [String] {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin/claude", "\(home)/.npm-global/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    }

    static func findClaudeExecutable() -> String? {
        claudeExecutableCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let signInScriptURL = supportURL.appendingPathComponent("claude-signin.command")

    /// Writes the Terminal script behind "Sign in again". It runs `claude auth login` in a visible window, where
    /// Claude Code saves its own sign-in; MaxxBar never runs the login hidden or touches the Keychain itself.
    /// Returns nil when claude is not installed in any of the usual places.
    static func writeSignInScript() -> URL? {
        guard findClaudeExecutable() != nil else { return nil }
        let candidates = claudeExecutableCandidates.map { "\"\($0)\"" }.joined(separator: " ")
        let script = """
        #!/bin/zsh
        # Written by MaxxBar for its Sign in again button.
        unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_OAUTH_TOKEN \\
            CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CONFIG_DIR CLAUDECODE CLAUDE_CODE_ENTRYPOINT
        CLAUDE=""
        for candidate in \(candidates); do
            if [ -x "$candidate" ]; then CLAUDE="$candidate"; break; fi
        done
        if [ -z "$CLAUDE" ]; then
            echo "MaxxBar couldn't find claude. Install Claude Code, then try Sign in again."
            exit 1
        fi
        echo "MaxxBar is signing Claude Code back in. Finish the steps in your browser."
        if "$CLAUDE" auth login; then
            echo "Signed in. You can close this window."
        else
            echo "Sign-in didn't finish. You can close this window and click Sign in again in MaxxBar."
        fi

        """
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try Data(script.utf8).write(to: signInScriptURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: signInScriptURL.path)
            return signInScriptURL
        } catch {
            return nil
        }
    }

    /// One minimal Claude Code request (Haiku, no tools, MCP servers, slash commands, settings or saved session)
    /// from an empty temporary folder, so no project CLAUDE.md or hooks load. Hard 60-second limit.
    static func runKeepAlive() -> ClaudeKeepAliveRun {
        let started = Date()
        let home = NSHomeDirectory()
        guard let executable = findClaudeExecutable() else {
            return ClaudeKeepAliveRun(exitCode: nil, duration: 0, errorClass: "not-found")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maxxbar-keepalive-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-p", "ok", "--model", "haiku", "--tools", "", "--no-session-persistence",
                             "--strict-mcp-config", "--disable-slash-commands", "--setting-sources", ""]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        // Use the stored sign-in, never an inherited token or API key.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_OAUTH_TOKEN",
                    "CLAUDE_CODE_OAUTH_REFRESH_TOKEN", "CLAUDE_CONFIG_DIR", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"] {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else {
            return ClaudeKeepAliveRun(exitCode: nil, duration: Date().timeIntervalSince(started), errorClass: "launch-failed")
        }
        guard finished.wait(timeout: .now() + 60) == .success else {
            process.terminate()
            return ClaudeKeepAliveRun(exitCode: nil, duration: Date().timeIntervalSince(started), errorClass: "timeout")
        }
        let status = process.terminationStatus
        return ClaudeKeepAliveRun(exitCode: status, duration: Date().timeIntervalSince(started),
                                  errorClass: status == 0 ? nil : "exit-\(status)")
    }
}
