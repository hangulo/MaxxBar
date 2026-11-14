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
    }
    struct KeepAliveState: Codable, Equatable {
        var fingerprint: String
        var attempts: Int
        var nextAttemptAt: Date
    }
    static let keepAliveDefaultsKey = "ClaudeKeepAlive"
    static let retryDelay: TimeInterval = 600
    static let maxAttempts = 2
    static let gaveUpMessage = "Couldn't refresh Claude Code's sign-in automatically. Open claude in Terminal or run claude auth login."
    static let shared = ClaudeCredentialManager(
        load: loadCredential,
        keepAlive: runKeepAlive,
        stateURL: supportURL.appendingPathComponent("claude-keepalive-state.json"),
        logURL: supportURL.appendingPathComponent("claude-keepalive.log"),
        enabled: UserDefaults.standard.object(forKey: keepAliveDefaultsKey) as? Bool ?? true
    )
    private static var supportURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/MaxxBar")
    }
    private let lock = NSLock()
    private let load: () -> ClaudeOAuthCredential?
    private let keepAlive: () -> ClaudeKeepAliveRun
    private let stateURL: URL
    private let logURL: URL?
    private let clock: () -> Date
    private let enabled: Bool
    private(set) var state: KeepAliveState?
    /// The last credential read. Reading it launches /usr/bin/security, so a still-valid token is reused
    /// until its own expiry or until Claude rejects it.
    private var cached: ClaudeOAuthCredential?

    init(load: @escaping () -> ClaudeOAuthCredential?, keepAlive: @escaping () -> ClaudeKeepAliveRun,
         stateURL: URL, logURL: URL? = nil, clock: @escaping () -> Date = Date.init, enabled: Bool = true) {
        self.load = load
        self.keepAlive = keepAlive
        self.stateURL = stateURL
        self.logURL = logURL
        self.clock = clock
        self.enabled = enabled
        state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(KeepAliveState.self, from: $0) }
    }

    func read(rejectedAccessToken: String? = nil) -> ReadResult {
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        if rejectedAccessToken == nil, let cached, cached.isValid(at: now) {
            return ReadResult(accessToken: cached.accessToken)
        }
        cached = nil
        guard let credential = load() else {
            return ReadResult(error: "Claude Code's saved sign-in is missing or empty. Run claude auth login in Terminal to restore live Claude limits.")
        }
        let rejected = rejectedAccessToken == credential.accessToken
        // Claude Code refreshes once its token has expired, so the keep-alive waits for expiry.
        guard rejected || !credential.isValid(at: now) else {
            // Without an expiry the token cannot be cached safely; read it again next time.
            if credential.expiresAt != nil { cached = credential }
            return ReadResult(accessToken: credential.accessToken)
        }
        guard enabled else {
            return ReadResult(error: "Claude Code's sign-in has expired. Open claude in Terminal or run claude auth login to restore live Claude limits.")
        }
        let previous = state?.fingerprint == credential.fingerprint ? state : nil
        if let previous {
            if previous.attempts >= Self.maxAttempts { return ReadResult(error: Self.gaveUpMessage) }
            if previous.nextAttemptAt > now {
                let retry = previous.nextAttemptAt.formatted(date: .omitted, time: .shortened)
                return ReadResult(error: "Couldn't refresh Claude Code's sign-in yet; trying again at \(retry).")
            }
        }
        // Record the attempt first so a crash or restart mid-run cannot turn into a loop.
        let attempts = (previous?.attempts ?? 0) + 1
        state = KeepAliveState(fingerprint: credential.fingerprint, attempts: attempts,
                               nextAttemptAt: now.addingTimeInterval(Self.retryDelay))
        persistState()
        let run = keepAlive()
        let after = load()
        let renewed = after.map { current in
            current.accessToken != credential.accessToken && current.refreshToken != nil
                && current.isValid(at: clock())
                && (current.expiresAt ?? .distantFuture) > (credential.expiresAt ?? .distantPast)
        } ?? false
        appendLog(run: run, before: credential.expiresAt, after: after?.expiresAt, renewed: renewed, attempt: attempts)
        if renewed, let after {
            cached = after
            state = nil
            try? FileManager.default.removeItem(at: stateURL)
            return ReadResult(accessToken: after.accessToken, refreshed: true)
        }
        if attempts >= Self.maxAttempts { return ReadResult(error: Self.gaveUpMessage) }
        let retry = now.addingTimeInterval(Self.retryDelay).formatted(date: .omitted, time: .shortened)
        return ReadResult(error: "Couldn't refresh Claude Code's sign-in yet; trying again at \(retry).")
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

    static func loadCredential() -> ClaudeOAuthCredential? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.credentials.json")
        let file = (try? Data(contentsOf: url)).flatMap(ClaudeOAuthCredential.init(data:))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        var keychain: ClaudeOAuthCredential?
        if (try? process.run()) != nil {
            if finished.wait(timeout: .now() + 10) == .success {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 { keychain = ClaudeOAuthCredential(data: data) }
            } else {
                process.terminate()
            }
        }
        // A stale file must not mask a newly rotated Keychain credential, or vice versa.
        return [file, keychain].compactMap { $0 }.max {
            ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast)
        }
    }

    /// One minimal Claude Code request (Haiku, no tools, MCP servers, slash commands, settings or saved session)
    /// from an empty temporary folder, so no project CLAUDE.md or hooks load. Hard 60-second limit.
    static func runKeepAlive() -> ClaudeKeepAliveRun {
        let started = Date()
        let home = NSHomeDirectory()
        let paths = ["\(home)/.local/bin/claude", "\(home)/.npm-global/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
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
