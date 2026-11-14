import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

enum LLMUsageReader {
    /// Local token and session totals for one provider (Codex from its sqlite state, Claude from transcripts).
    struct LocalProviderUsage {
        static let empty = LocalProviderUsage(fiveHourTokens: 0, weeklyTokens: 0, weeklyThreads: 0, windows: [], costEstimates: [], recentSessions: [], topWeeklySessions: [], modelUsage: [], dailyModelUsage: [])

        let fiveHourTokens: UInt64
        let weeklyTokens: UInt64
        let weeklyThreads: Int
        let windows: [LLMLocalUsageWindow]
        let costEstimates: [LLMTokenCostEstimate]
        let recentSessions: [LLMUsageSession]
        let topWeeklySessions: [LLMUsageSession]
        let modelUsage: [LLMModelUsageTotal]
        let dailyModelUsage: [LLMModelUsageTotal]
    }

    struct ClaudeModelUsageEvent {
        let requestID: String
        let sessionID: String
        let modelName: String
        let tokens: UInt64
        let timestamp: Date?
        var usage: LLMTokenUsageSummary? = nil
    }

    struct ClaudeTranscript {
        let session: LLMUsageSession
        let modelEvents: [ClaudeModelUsageEvent]
        /// Cleaned first prompt, set only when nothing better than it was available as a title.
        let untitledPrompt: String?
    }

    private final class HTTPResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        private var statusCode: Int?
        private var retryAfter: String?
        private var errorDescription: String?

        func set(data: Data?, response: URLResponse?, error: Error?) {
            lock.lock()
            self.data = data
            self.statusCode = (response as? HTTPURLResponse)?.statusCode
            self.retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            self.errorDescription = error?.localizedDescription
            lock.unlock()
        }

        func snapshot() -> (data: Data?, statusCode: Int?, errorDescription: String?, retryAfter: String?) {
            lock.lock()
            defer { lock.unlock() }
            return (data, statusCode, errorDescription, retryAfter)
        }
    }

    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let access_token: String?
        }

        let tokens: Tokens?
    }

    private struct WhamUsageResponse: Decodable {
        let email: String?
        let plan_type: String?
        let rate_limit: RateLimitPayload?
        let additional_rate_limits: [AdditionalRateLimit]?
        let credits: Credits?
        let rate_limit_reset_credits: RateLimitResetCredits?
    }

    private struct ClaudeUsageResponse: Decodable {
        let five_hour: ClaudeUsageWindowPayload?
        let seven_day: ClaudeUsageWindowPayload?
        let seven_day_opus: ClaudeUsageWindowPayload?
        let seven_day_sonnet: ClaudeUsageWindowPayload?
    }

    private struct ClaudeUsageWindowPayload: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    private struct AdditionalRateLimit: Decodable {
        let limit_name: String?
        let rate_limit: RateLimitPayload?
    }

    private struct RateLimitPayload: Decodable {
        let primary_window: WindowPayload?
        let secondary_window: WindowPayload?
    }

    private struct WindowPayload: Decodable {
        let used_percent: Int?
        let limit_window_seconds: Int?
        let reset_at: TimeInterval?
    }

    private struct Credits: Decodable {
        let balance: String?
        let unlimited: Bool?
    }

    private struct RateLimitResetCredits: Decodable {
        let available_count: Int?
        let expirations: [LLMResetCreditExpiration]

        init(from decoder: Decoder) throws {
            let value = try FlexibleUsageValue(from: decoder)
            available_count = value.object?["available_count"]?.intValue
            expirations = RateLimitResetCredits.expirations(in: value)
        }

        private static func expirations(in value: FlexibleUsageValue) -> [LLMResetCreditExpiration] {
            var results: [LLMResetCreditExpiration] = []
            collectExpirations(in: value, into: &results)

            return results
                .reduce(into: [Date: Int]()) { grouped, expiration in
                    grouped[expiration.expiresAt, default: 0] += expiration.count
                }
                .map { LLMResetCreditExpiration(count: $0.value, expiresAt: $0.key) }
                .sorted { $0.expiresAt < $1.expiresAt }
        }

        private static func collectExpirations(in value: FlexibleUsageValue, into results: inout [LLMResetCreditExpiration]) {
            if let object = value.object {
                if let expiresAt = expirationDate(in: object) {
                    results.append(LLMResetCreditExpiration(count: creditCount(in: object), expiresAt: expiresAt))
                }

                for child in object.values {
                    collectExpirations(in: child, into: &results)
                }
            }

            if let array = value.array {
                for child in array {
                    collectExpirations(in: child, into: &results)
                }
            }
        }

        private static func expirationDate(in object: [String: FlexibleUsageValue]) -> Date? {
            let expirationKeys = ["expires_at", "expiresAt", "expire_at", "expires", "expiration", "expiration_at", "expirationAt", "expiration_date"]

            for key in expirationKeys {
                guard let value = object[key] else { continue }
                if let date = value.dateValue {
                    return date
                }
            }

            return nil
        }

        private static func creditCount(in object: [String: FlexibleUsageValue]) -> Int {
            let countKeys = ["count", "available_count", "availableCount", "credits", "amount", "quantity", "remaining_count", "remainingCount"]

            for key in countKeys {
                guard let count = object[key]?.intValue else { continue }
                return max(count, 1)
            }

            return 1
        }
    }

    private struct FlexibleUsageValue: Decodable {
        let object: [String: FlexibleUsageValue]?
        let array: [FlexibleUsageValue]?
        let string: String?
        let number: Double?

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: DynamicUsageKey.self) {
                var object: [String: FlexibleUsageValue] = [:]
                for key in container.allKeys {
                    object[key.stringValue] = try? container.decode(FlexibleUsageValue.self, forKey: key)
                }
                self.object = object
                array = nil
                string = nil
                number = nil
                return
            }

            if var container = try? decoder.unkeyedContainer() {
                var array: [FlexibleUsageValue] = []
                while !container.isAtEnd {
                    if let value = try? container.decode(FlexibleUsageValue.self) {
                        array.append(value)
                    } else {
                        _ = try? container.decode(EmptyUsageValue.self)
                    }
                }
                object = nil
                self.array = array
                string = nil
                number = nil
                return
            }

            let container = try decoder.singleValueContainer()
            object = nil
            array = nil
            if let string = try? container.decode(String.self) {
                self.string = string
                number = nil
            } else if let number = try? container.decode(Double.self) {
                string = nil
                self.number = number
            } else {
                string = nil
                number = nil
            }
        }

        var intValue: Int? {
            if let number {
                return Int(number)
            }

            if let string {
                return Int(string)
            }

            return nil
        }

        var dateValue: Date? {
            if let number {
                return Date(timeIntervalSince1970: number)
            }

            guard let string else { return nil }
            if let timestamp = TimeInterval(string) {
                return Date(timeIntervalSince1970: timestamp)
            }

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: string) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }
    }

    private struct DynamicUsageKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    private struct EmptyUsageValue: Decodable {}

    struct SessionIndexEntry: Decodable {
        let id: String
        let thread_name: String?
    }

    /// "Check now": refreshes only the Claude card from the usage endpoint, reusing the rest of `snapshot`
    /// (the full read rescans every local transcript and can take minutes). Returns why no request was made, if none was.
    static func checkClaudeNow(in snapshot: LLMUsageSnapshot) -> (snapshot: LLMUsageSnapshot, skipped: String?) {
        let now = Date()
        let before = ClaudeUsagePollingState.load(from: claudeCacheURL)
        var skipped = before?.manualCheckBlockReason(at: now)
        var updated = snapshot
        let claudeSessions = (snapshot.recentSessions + snapshot.topWeeklySessions).filter { $0.provider == "Claude" }
        applyClaudeLimits(
            to: &updated, lastActivity: claudeSessions.compactMap(\.updatedAt).max(),
            hasClaudeSessions: !claudeSessions.isEmpty, manual: true
        )
        // Every click ends with a visible outcome: if no new reading arrived, say why (e.g. an expired sign-in).
        let after = ClaudeUsagePollingState.load(from: claudeCacheURL)
        if skipped == nil, after?.fetchedAt == nil || after?.fetchedAt == before?.fetchedAt {
            skipped = updated.providerErrors["Claude"] ?? "Claude did not return a new reading."
        }
        return (updated, skipped)
    }

    private static func applyClaudeLimits(
        to snapshot: inout LLMUsageSnapshot, lastActivity: Date?, hasClaudeSessions: Bool, manual: Bool
    ) {
        snapshot.limits.removeAll { $0.name == "Claude" }
        snapshot.providerErrors["Claude"] = nil
        let now = Date()
        let tapped = ClaudeStatusLineLimits.read()?.current(at: now)
        let tappedLimit = tapped.flatMap { claudeLimit(fromStatusLine: $0, now: now) }
        let claudeCredential = ClaudeCredentialManager.shared.read()
        if let token = claudeCredential.accessToken {
            // A fresh status line capture is live; the endpoint is then only refreshed hourly for the per-model weeklies.
            let tappedIsFresh = tappedLimit != nil && tapped?.isFresh(at: now) == true
            switch readClaudeLimits(
                accessToken: token,
                minimumRefreshAge: tappedIsFresh ? 3_600 : 0,
                lastActivity: lastActivity,
                // A just-refreshed sign-in reads usage right away (429 cooldowns still apply).
                manual: manual || claudeCredential.refreshed
            ) {
            case .success(var limits, let warning):
                if let tappedLimit, tappedIsFresh || isNewer(tappedLimit, than: limits.first { $0.name == "Claude" }) {
                    limits.removeAll { $0.name == "Claude" }
                    limits.insert(tappedLimit, at: 0)
                    snapshot.providerErrors["Claude"] = tappedIsFresh ? nil : warning
                } else {
                    snapshot.providerErrors["Claude"] = warning
                }
                snapshot.limits.append(contentsOf: limits)
            case .failure(let message), .unauthorized(let message):
                if let tappedLimit {
                    snapshot.limits.append(tappedLimit)
                    snapshot.providerErrors["Claude"] = tappedIsFresh ? nil : message
                } else {
                    snapshot.providerErrors["Claude"] = message
                }
            }
        } else {
            // Without a usable token, keep showing the last reading (marked with its check time) until its windows reset.
            var limits = lastKnownClaudeLimits(at: now)
            if let tappedLimit, isNewer(tappedLimit, than: limits.first { $0.name == "Claude" }) {
                limits.removeAll { $0.name == "Claude" }
                limits.insert(tappedLimit, at: 0)
            }
            let tappedIsFresh = tappedLimit != nil && tapped?.isFresh(at: now) == true
            if !limits.isEmpty {
                snapshot.limits.append(contentsOf: limits)
                if !tappedIsFresh {
                    snapshot.providerErrors["Claude"] = "Showing the last Claude usage MaxxBar read. "
                        + (claudeCredential.error ?? "Run claude auth login in Terminal for live updates.")
                }
            } else if hasClaudeSessions || claudeAccountExists() {
                snapshot.providerErrors["Claude"] = claudeCredential.error ?? "Live limits require a Claude Code OAuth sign-in; local Claude sessions are still captured."
            }
        }
        snapshot.error = snapshot.providerErrors.isEmpty
            ? nil
            : snapshot.providerErrors.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " ")
    }

    /// `checkClaudeNow` asks the Claude usage endpoint immediately unless a cooldown is active or it was read under 30s ago.
    /// Local scans (Claude transcripts, Codex sqlite) are the expensive part of a read. The menu bar only needs the
    /// quotas, so while the popover is closed callers pass refreshLocal: false and reuse the last scan for a while.
    nonisolated(unsafe) private static var cachedLocalUsage: (codex: LocalProviderUsage, claude: LocalProviderUsage, at: Date)?
    private static let cachedLocalUsageLock = NSLock()
    private static let localUsageMaxAge: TimeInterval = 10 * 60

    private static func localUsage(refresh: Bool) -> (codex: LocalProviderUsage, claude: LocalProviderUsage) {
        cachedLocalUsageLock.lock()
        let cached = cachedLocalUsage
        cachedLocalUsageLock.unlock()
        if !refresh, let cached, Date().timeIntervalSince(cached.at) < localUsageMaxAge {
            return (cached.codex, cached.claude)
        }
        // A provider hidden with the eye toggle is not scanned at all.
        let codex = ProviderVisibility.showCodex ? readLocalCodexUsage() : .empty
        let claude = ProviderVisibility.showClaude ? readLocalClaudeUsage() : .empty
        cachedLocalUsageLock.lock()
        cachedLocalUsage = (codex, claude, Date())
        cachedLocalUsageLock.unlock()
        return (codex, claude)
    }

    static func read(checkClaudeNow: Bool = false, refreshLocal: Bool = true) -> LLMUsageSnapshot {
        let (codexLocal, claudeLocal) = localUsage(refresh: refreshLocal)
        let local = mergedLocalUsage(codexLocal, claudeLocal)
        var snapshot = ProviderVisibility.showCodex
            ? readCodexUsage(local: local)
            : snapshotWithLocalUsage(local, error: nil)
        snapshot.weeklyModelUsage = local.modelUsage
        snapshot.dailyModelUsage = local.dailyModelUsage
        snapshot.providerAccounts = providerAccounts(
            codexEmail: snapshot.email,
            codexPlan: snapshot.planType,
            hasCodexSessions: !codexLocal.recentSessions.isEmpty,
            hasClaudeSessions: !claudeLocal.recentSessions.isEmpty
        )

        // Record the Codex error first: applyClaudeLimits rebuilds `error` from providerErrors.
        if let codexError = snapshot.error {
            snapshot.providerErrors["Codex"] = codexError
        }
        guard ProviderVisibility.showClaude else {
            snapshot.providerAccounts.removeAll { $0.provider == "Claude" }
            return snapshot
        }
        snapshot.apiCost["Claude"] = APICostLedger.summary(provider: "Claude")
        let claudeActivity = (claudeLocal.recentSessions + claudeLocal.topWeeklySessions).compactMap(\.updatedAt).max()
        applyClaudeLimits(
            to: &snapshot, lastActivity: claudeActivity,
            hasClaudeSessions: !claudeLocal.recentSessions.isEmpty, manual: checkClaudeNow
        )
        return snapshot
    }

    private static func providerAccounts(
        codexEmail: String?,
        codexPlan: String?,
        hasCodexSessions: Bool,
        hasClaudeSessions: Bool
    ) -> [LLMProviderAccount] {
        var accounts: [LLMProviderAccount] = []
        if codexEmail != nil || codexPlan != nil || hasCodexSessions {
            accounts.append(
                LLMProviderAccount(
                    provider: "Codex",
                    email: codexEmail,
                    displayName: nil,
                    organizationName: nil,
                    planName: codexPlan
                )
            )
        }
        if let claude = readClaudeAccountProfile() {
            accounts.append(claude)
        } else if hasClaudeSessions {
            accounts.append(
                LLMProviderAccount(
                    provider: "Claude",
                    email: nil,
                    displayName: nil,
                    organizationName: nil,
                    planName: nil
                )
            )
        }
        return accounts
    }

    nonisolated(unsafe) private static var cachedClaudeProfile: (stamp: ClaudeParsedFileStamp, root: [String: Any])?
    private static let cachedClaudeProfileLock = NSLock()

    /// ~/.claude.json, parsed once per change instead of several times per refresh.
    private static func claudeProfileRoot() -> [String: Any]? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        let stamp = ClaudeParsedFileStamp(size: size, modified: modified)
        cachedClaudeProfileLock.lock()
        defer { cachedClaudeProfileLock.unlock() }
        if let cachedClaudeProfile, cachedClaudeProfile.stamp == stamp { return cachedClaudeProfile.root }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            cachedClaudeProfile = nil
            return nil
        }
        cachedClaudeProfile = (stamp, root)
        return root
    }

    private static func readClaudeAccountProfile() -> LLMProviderAccount? {
        guard let root = claudeProfileRoot() else {
            return nil
        }
        let account = (root["oauthAccount"] as? [String: Any]) ?? root

        func text(_ key: String) -> String? {
            guard let value = account[key] as? String else { return nil }
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }

        let seatTier = text("seatTier")
        let plan: String?
        if let tier = text("userRateLimitTier") ?? text("organizationRateLimitTier"),
           let tierPlan = claudePlanName(rateLimitTier: tier) {
            // The rate limit tier separates Max 5x from Max 20x; seatTier is often empty on personal plans.
            plan = tierPlan
        } else if let seatTier {
            let normalized = seatTier.lowercased()
            if normalized.contains("team") {
                plan = "Team"
            } else if normalized.contains("enterprise") {
                plan = "Enterprise"
            } else if normalized.contains("max") {
                plan = "Max"
            } else if normalized.contains("pro") {
                plan = "Pro"
            } else {
                plan = seatTier.replacingOccurrences(of: "_", with: " ").capitalized
            }
        } else {
            plan = nil
        }

        return LLMProviderAccount(
            provider: "Claude",
            email: text("emailAddress"),
            displayName: text("displayName"),
            organizationName: text("organizationName"),
            planName: plan
        )
    }

    /// Maps tiers such as "default_claude_max_5x" to "Max 5x".
    static func claudePlanName(rateLimitTier tier: String) -> String? {
        let normalized = tier.lowercased()
        if normalized.contains("max") {
            if normalized.contains("20x") { return "Max 20x" }
            if normalized.contains("5x") { return "Max 5x" }
            return "Max"
        }
        if normalized.contains("enterprise") { return "Enterprise" }
        if normalized.contains("team") { return "Team" }
        if normalized.contains("pro") { return "Pro" }
        return nil
    }

    private static func readCodexUsage(local: LocalProviderUsage) -> LLMUsageSnapshot {
        guard let token = readAccessToken() else {
            return LLMUsageSnapshot(
                email: nil,
                planType: nil,
                limits: [],
                creditsBalance: nil,
                resetCreditCount: nil,
                resetCreditExpirations: [],
                lastUpdated: Date(),
                localFiveHourTokens: local.fiveHourTokens,
                localWeeklyTokens: local.weeklyTokens,
                localWeeklyThreads: local.weeklyThreads,
                localWindows: local.windows,
                costEstimates: local.costEstimates,
                recentSessions: local.recentSessions,
                topWeeklySessions: local.topWeeklySessions,
                error: "Codex auth not found"
            )
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = HTTPResultBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            resultBox.set(data: data, response: response, error: error)
            semaphore.signal()
        }.resume()

        let timeout = semaphore.wait(timeout: .now() + 4)
        if timeout == .timedOut {
            return snapshotWithLocalUsage(local, error: "Codex usage request timed out")
        }

        let httpResult = resultBox.snapshot()
        if let errorDescription = httpResult.errorDescription {
            return snapshotWithLocalUsage(local, error: errorDescription)
        }

        guard httpResult.statusCode == 200,
              let resultData = httpResult.data else {
            let status = httpResult.statusCode
            return snapshotWithLocalUsage(local, error: status.map { "Codex usage returned HTTP \($0)" } ?? "Codex usage unavailable")
        }

        do {
            let response = try JSONDecoder().decode(WhamUsageResponse.self, from: resultData)
            return LLMUsageSnapshot(
                email: response.email,
                planType: response.plan_type,
                limits: limits(from: response),
                creditsBalance: response.credits?.unlimited == true ? "Unlimited" : response.credits?.balance,
                resetCreditCount: response.rate_limit_reset_credits?.available_count,
                resetCreditExpirations: response.rate_limit_reset_credits?.expirations ?? [],
                lastUpdated: Date(),
                localFiveHourTokens: local.fiveHourTokens,
                localWeeklyTokens: local.weeklyTokens,
                localWeeklyThreads: local.weeklyThreads,
                localWindows: local.windows,
                costEstimates: local.costEstimates,
                recentSessions: local.recentSessions,
                topWeeklySessions: local.topWeeklySessions,
                error: nil
            )
        } catch {
            return snapshotWithLocalUsage(local, error: "Could not parse Codex usage")
        }
    }

    private static func limits(from response: WhamUsageResponse) -> [LLMUsageLimit] {
        var limits: [LLMUsageLimit] = []
        if let rateLimit = response.rate_limit {
            limits.append(LLMUsageLimit(name: "Codex", primary: window(from: rateLimit.primary_window), secondary: window(from: rateLimit.secondary_window)))
        }

        for additional in response.additional_rate_limits ?? [] {
            guard let rateLimit = additional.rate_limit else { continue }
            limits.append(LLMUsageLimit(name: additional.limit_name ?? "Model", primary: window(from: rateLimit.primary_window), secondary: window(from: rateLimit.secondary_window)))
        }

        return limits
    }

    private static func window(from payload: WindowPayload?) -> LLMUsageWindow? {
        guard let payload,
              let usedPercent = payload.used_percent,
              let windowSeconds = payload.limit_window_seconds else {
            return nil
        }

        return LLMUsageWindow(
            label: label(forWindowSeconds: windowSeconds),
            usedPercent: min(max(usedPercent, 0), 100),
            remainingPercent: min(max(100 - usedPercent, 0), 100),
            resetAt: payload.reset_at.map { Date(timeIntervalSince1970: $0) },
            windowSeconds: windowSeconds
        )
    }

    private static func label(forWindowSeconds seconds: Int) -> String {
        if seconds >= 604_800 {
            let weeks = max(Int((Double(seconds) / 604_800).rounded()), 1)
            return weeks == 1 ? "Weekly" : "\(weeks) Weeks"
        }
        if seconds >= 86_400 {
            return "\(Int(ceil(Double(seconds) / 86_400)))d"
        }
        if seconds >= 3_600 {
            return "\(Int(ceil(Double(seconds) / 3_600)))h"
        }
        return "\(Int(ceil(Double(seconds) / 60)))m"
    }

    private static func readAccessToken() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let token = auth.tokens?.access_token,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private enum ClaudeLimitReadResult {
        case success([LLMUsageLimit], warning: String?)
        case failure(String)
        case unauthorized(String)
    }

    private static let claudePollingLock = NSLock()
    private static var claudeCacheURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/claude-usage-cache.json")
    }

    private static func claudeLimit(fromStatusLine tapped: ClaudeStatusLineLimits, now: Date) -> LLMUsageLimit? {
        func window(_ payload: ClaudeStatusLineLimits.Window?, label: String, seconds: Int) -> LLMUsageWindow? {
            guard let payload else { return nil }
            let used = min(max(Int(payload.usedPercent.rounded()), 0), 100)
            return LLMUsageWindow(
                label: label,
                usedPercent: used,
                remainingPercent: 100 - used,
                resetAt: payload.resetAt,
                windowSeconds: seconds
            )
        }
        var limit = LLMUsageLimit(
            name: "Claude",
            primary: window(tapped.fiveHour, label: "5h", seconds: 18_000),
            secondary: window(tapped.sevenDay, label: "Weekly", seconds: 604_800)
        )
        guard !limit.windows.isEmpty else { return nil }
        // Mark older captures as previously checked readings.
        limit.cachedAt = ClaudeUsagePollingState.staleMarker(checkedAt: tapped.capturedAt, now: now)
        limit.checkedAt = tapped.capturedAt
        limit.source = "statusline"
        return limit
    }

    private static func isNewer(_ limit: LLMUsageLimit, than other: LLMUsageLimit?) -> Bool {
        guard let other else { return true }
        // Compare actual check times; cachedAt is only set once a reading is over five minutes old.
        let mine = limit.checkedAt ?? limit.cachedAt ?? .distantPast
        let theirs = other.checkedAt ?? other.cachedAt ?? .distantFuture
        return mine > theirs
    }

    /// Token refreshes would change a token fingerprint, so prefer the stable account ID.
    private static func claudeCredentialID(accessToken: String) -> String {
        if let root = claudeProfileRoot(),
           let account = root["oauthAccount"] as? [String: Any],
           let uuid = account["accountUuid"] as? String,
           !uuid.isEmpty {
            return "account:\(uuid)"
        }
        return SHA256.hash(data: Data(accessToken.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func readClaudeLimits(
        accessToken: String, minimumRefreshAge: TimeInterval = 0, lastActivity: Date? = nil, manual: Bool = false
    ) -> ClaudeLimitReadResult {
        let result = fetchClaudeLimits(
            accessToken: accessToken, minimumRefreshAge: minimumRefreshAge, lastActivity: lastActivity, manual: manual
        )
        guard case .unauthorized = result else { return result }
        // A revoked or early-expiring access token can fail before its recorded expiry.
        // Renew once and retry once, after the polling lock has been released.
        let refreshed = ClaudeCredentialManager.shared.read(rejectedAccessToken: accessToken)
        guard let newToken = refreshed.accessToken, newToken != accessToken else {
            return .failure(refreshed.error ?? "Claude rejected its access token and automatic renewal failed; run claude auth login --claudeai.")
        }
        let retried = fetchClaudeLimits(accessToken: newToken, minimumRefreshAge: 0, renewedCredential: true)
        if case .unauthorized = retried {
            return .failure("Claude rejected its renewed access token; run claude auth login --claudeai once.")
        }
        return retried
    }

    /// A reset passing does not establish the new window's remaining quota, so passed windows are dropped.
    private static func currentClaudeLimits(from response: ClaudeUsageResponse, fetchedAt: Date?, now: Date) -> [LLMUsageLimit] {
        var limits = claudeLimits(from: response)
        for index in limits.indices {
            if let reset = limits[index].primary?.resetAt, reset <= now { limits[index].primary = nil }
            if let reset = limits[index].secondary?.resetAt, reset <= now { limits[index].secondary = nil }
            limits[index].cachedAt = ClaudeUsagePollingState.staleMarker(checkedAt: fetchedAt, now: now)
            limits[index].checkedAt = fetchedAt
            limits[index].source = "cache"
        }
        limits.removeAll { $0.windows.isEmpty }
        return limits
    }

    /// The last saved usage response, read without a token or network request.
    private static func lastKnownClaudeLimits(at now: Date) -> [LLMUsageLimit] {
        claudePollingLock.lock()
        defer { claudePollingLock.unlock() }
        guard let state = ClaudeUsagePollingState.load(from: claudeCacheURL),
              let data = state.usableData(at: now),
              let response = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data) else {
            return []
        }
        return currentClaudeLimits(from: response, fetchedAt: state.fetchedAt, now: now)
    }

    private static func fetchClaudeLimits(
        accessToken: String, minimumRefreshAge: TimeInterval, lastActivity: Date? = nil, manual: Bool = false,
        renewedCredential: Bool = false
    ) -> ClaudeLimitReadResult {
        // Serialize reads and persist the cooldown so reopening the app cannot bypass it.
        claudePollingLock.lock()
        defer { claudePollingLock.unlock() }
        let now = Date()
        let credentialID = claudeCredentialID(accessToken: accessToken)
        let loadedState = ClaudeUsagePollingState.load(from: claudeCacheURL)
        var state = loadedState ?? ClaudeUsagePollingState(credentialID: credentialID)
        state.switchCredential(to: credentialID)
        state.decayFloor(at: now)
        if renewedCredential, state.lastError == "Claude access token was rejected" {
            state.nextAllowedAt = .distantPast
            state.lastError = nil
        }
        defer {
            // Most passes only read the cache; rewrite the file only when the state changed.
            if state != loadedState, let data = try? JSONEncoder().encode(state) {
                try? FileManager.default.createDirectory(
                    at: claudeCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? data.write(to: claudeCacheURL, options: .atomic)
            }
        }

        func cachedResult() -> ClaudeLimitReadResult {
            let retry = state.nextAllowedAt.formatted(date: .omitted, time: .shortened)
            let warning = state.lastError.map { "\($0). Retrying after \(retry)." }
            guard let data = state.usableData(at: now),
                  let response = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data) else {
                return .failure(warning ?? "Waiting for the next usage refresh after \(retry).")
            }
            let limits = currentClaudeLimits(from: response, fetchedAt: state.fetchedAt, now: now)
            guard !limits.isEmpty else {
                return .failure(warning ?? "Previous Claude windows have reset; waiting for fresh usage.")
            }
            return .success(limits, warning: warning)
        }

        // Adaptive schedule: 2 min while Claude is in use, 5 min normally, 15 min when idle; never under the 429 floor.
        let interval = max(state.refreshInterval(lastActivity: lastActivity, at: now), minimumRefreshAge)
        guard manual ? state.allowsManualCheck(at: now) : state.isDue(at: now, interval: interval) else {
            return cachedResult()
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = HTTPResultBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            resultBox.set(data: data, response: response, error: error)
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 5) != .timedOut else {
            task.cancel()
            state.failed(status: nil, retryAfter: nil, message: "Usage request timed out", at: now)
            return cachedResult()
        }
        let result = resultBox.snapshot()
        guard result.errorDescription == nil, result.statusCode == 200, let data = result.data else {
            let message: String
            switch result.statusCode {
            case 429: message = "Claude usage requests are temporarily rate-limited (HTTP 429)"
            case 401: message = "Claude access token was rejected"
            case 403: message = "Claude usage access is forbidden; verify your account permissions in Claude Code"
            default: message = result.errorDescription ?? result.statusCode.map { "Usage returned HTTP \($0)" } ?? "Usage unavailable"
            }
            state.failed(status: result.statusCode, retryAfter: result.retryAfter, message: message, at: now)
            if result.statusCode == 401 { return .unauthorized(message) }
            return cachedResult()
        }
        guard let response = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data),
              !claudeLimits(from: response).isEmpty else {
            state.failed(status: nil, retryAfter: nil, message: "Usage response contained no readable limit windows", at: now)
            return cachedResult()
        }
        state.succeeded(data: data, at: now)
        var limits = claudeLimits(from: response)
        for index in limits.indices {
            limits[index].checkedAt = now
            limits[index].source = "endpoint"
        }
        return .success(limits, warning: nil)
    }

    private static func claudeLimits(from response: ClaudeUsageResponse) -> [LLMUsageLimit] {
        var limits: [LLMUsageLimit] = []
        let general = LLMUsageLimit(
            name: "Claude",
            primary: claudeWindow(response.five_hour, label: "5h", seconds: 18_000),
            secondary: claudeWindow(response.seven_day, label: "Weekly", seconds: 604_800)
        )
        if !general.windows.isEmpty { limits.append(general) }
        if let opus = claudeWindow(response.seven_day_opus, label: "Weekly", seconds: 604_800) {
            limits.append(LLMUsageLimit(name: "Claude Opus", primary: nil, secondary: opus))
        }
        if let sonnet = claudeWindow(response.seven_day_sonnet, label: "Weekly", seconds: 604_800) {
            limits.append(LLMUsageLimit(name: "Claude Sonnet", primary: nil, secondary: sonnet))
        }
        return limits
    }

    private static func claudeWindow(
        _ payload: ClaudeUsageWindowPayload?,
        label: String,
        seconds: Int
    ) -> LLMUsageWindow? {
        guard let utilization = payload?.utilization else { return nil }
        let used = min(max(Int(utilization.rounded()), 0), 100)
        return LLMUsageWindow(
            label: label,
            usedPercent: used,
            remainingPercent: 100 - used,
            resetAt: payload?.resets_at.flatMap(iso8601Date),
            windowSeconds: seconds
        )
    }

    // Shared formatters: building one per timestamp dominated the Claude transcript scan.
    // ISO8601DateFormatter is thread-safe once configured, and these are never mutated after creation.
    nonisolated(unsafe) private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let standardISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso8601Date(_ value: String) -> Date? {
        fractionalISO8601.date(from: value) ?? standardISO8601.date(from: value)
    }

    private static func claudeAccountExists() -> Bool {
        claudeProfileRoot()?["oauthAccount"] is [String: Any]
    }

    private static func mergedLocalUsage(
        _ codex: LocalProviderUsage,
        _ claude: LocalProviderUsage
    ) -> LocalProviderUsage {
        let labels = ["1h", "5h", "24h", "7d"]
        let windows = labels.map { label in
            let values = (codex.windows + claude.windows).filter { $0.label == label }
            return LLMLocalUsageWindow(
                label: label,
                tokens: values.reduce(0) { $0 + $1.tokens },
                threads: values.reduce(0) { $0 + $1.threads }
            )
        }
        let recent = uniqueSessions(codex.recentSessions + claude.recentSessions)
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        let topWeekly = uniqueSessions(codex.topWeeklySessions + claude.topWeeklySessions)
            .sorted { $0.tokens == $1.tokens
                ? ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
                : $0.tokens > $1.tokens
            }
        return LocalProviderUsage(
            fiveHourTokens: codex.fiveHourTokens + claude.fiveHourTokens,
            weeklyTokens: codex.weeklyTokens + claude.weeklyTokens,
            weeklyThreads: codex.weeklyThreads + claude.weeklyThreads,
            windows: windows,
            costEstimates: codex.costEstimates,
            recentSessions: Array(recent.prefix(30)),
            topWeeklySessions: Array(topWeekly.prefix(30)),
            modelUsage: mergedModelUsage(codex.modelUsage + claude.modelUsage),
            dailyModelUsage: mergedModelUsage(codex.dailyModelUsage + claude.dailyModelUsage)
        )
    }

    static func mergedModelUsage(_ totals: [LLMModelUsageTotal]) -> [LLMModelUsageTotal] {
        var merged: [String: LLMModelUsageTotal] = [:]
        for total in totals {
            let key = "\(total.provider.lowercased())|\(total.modelName.lowercased())"
            let existing = merged[key]
            merged[key] = LLMModelUsageTotal(
                provider: existing?.provider ?? total.provider,
                modelName: existing?.modelName ?? total.modelName,
                tokens: (existing?.tokens ?? 0) + total.tokens,
                sessionCount: (existing?.sessionCount ?? 0) + total.sessionCount
            )
        }
        return merged.values.sorted {
            $0.tokens == $1.tokens
                ? $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending
                : $0.tokens > $1.tokens
        }
    }

    static func uniqueSessions(_ sessions: [LLMUsageSession]) -> [LLMUsageSession] {
        var seen = Set<String>()
        return sessions.filter { seen.insert("\($0.provider):\($0.id)").inserted }
    }
}
