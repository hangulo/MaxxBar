import Foundation

/// `~/Library/Application Support/MaxxBar/usage-feed.json`: a small, versioned summary of MaxxBar's LLM usage
/// that other local apps (Tracework first) can read without knowing MaxxBar's internal files.
/// The contract is documented in `Docs/usage-feed.md`. Add fields freely; renaming or removing one, or changing
/// its meaning, needs a new `schemaVersion`.
struct UsageFeed: Codable, Equatable {
    static let currentSchema = "maxxbar.usage-feed"
    static let currentVersion = 1

    struct Window: Codable, Equatable {
        var remainingPercent: Int
        var usedPercent: Int
        var resetsAt: Date?
        var windowSeconds: Int
        /// "measured" (a real reading) or "estimated" (the last reading plus local tokens since). Added in
        /// version 1; files written before it have no value, which means measured.
        var basis: String? = nil
        /// The real reading behind an estimate. Only present when `basis` is "estimated".
        var measuredRemainingPercent: Int? = nil
        var measuredUsedPercent: Int? = nil
    }

    struct Provider: Codable, Equatable {
        var provider: String
        var plan: String?
        /// "statusline", "endpoint" or "cache" for Claude; "endpoint" for Codex. Nil when no quota reading exists.
        var source: String?
        /// When the quota reading was taken. Age = now minus this. Nil when unknown.
        var checkedAt: Date?
        var fiveHour: Window?
        var weekly: Window?
        var error: String?
    }

    struct Totals: Codable, Equatable {
        var provider: String
        var tokens: UInt64
        var inputTokens: UInt64
        var cachedInputTokens: UInt64
        var cacheWriteInputTokens: UInt64
        var outputTokens: UInt64
        var requests: Int
        var estimatedCostUSD: Double
    }

    struct Day: Codable, Equatable {
        /// Local calendar day, "yyyy-MM-dd" in `timeZone`.
        var date: String
        var totals: Totals
    }

    /// A quota window that has closed (reset), with what was left unused. Filled from the window ledger.
    struct ClosedWindow: Codable, Equatable {
        var provider: String
        /// "fiveHour", "weekly" (all models) or "weeklyModel" (one model's weekly limit, see `model`).
        var kind: String
        var model: String?
        var resetAt: Date
        var usedPercent: Int
        var leftPercent: Int
        /// The last reading before the reset was taken more than 30 minutes before it.
        var lowConfidence: Bool
        /// Reconstructed from older quota history rather than recorded at the close.
        var backfilled: Bool
        var plan: String?
    }

    struct Hour: Codable, Equatable {
        var hourStart: Date
        var totals: Totals
    }

    var schema = UsageFeed.currentSchema
    var schemaVersion = UsageFeed.currentVersion
    /// When the content last changed (the file is rewritten only then).
    var generatedAt: Date
    var appVersion: String
    var timeZone: String
    var costBasis = "Estimated at public API list prices. Subscription plans are not billed this way."
    var providers: [Provider]
    var daily: [Day]
    var hourly: [Hour]
    /// Closed quota windows from the last `closedWindowRetentionSeconds`, oldest first. Empty until the ledger has rows.
    var closedWindows: [ClosedWindow]

    static let closedWindowRetentionSeconds: TimeInterval = 30 * 86_400

    init(
        snapshot: LLMUsageSnapshot,
        closedWindows: [ClosedWindow] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        appVersion: String
    ) {
        self.closedWindows = closedWindows
            .filter { $0.resetAt >= now.addingTimeInterval(-Self.closedWindowRetentionSeconds) }
            .sorted { $0.resetAt == $1.resetAt ? $0.kind < $1.kind : $0.resetAt < $1.resetAt }
        self.generatedAt = now
        self.appVersion = appVersion
        self.timeZone = calendar.timeZone.identifier

        let plans: [String: String?] = ["Codex": snapshot.planType, "Claude": snapshot.claudePlanType]
        self.providers = snapshot.limits
            .sorted { $0.name < $1.name }
            .map { limit in
                Provider(
                    provider: limit.name,
                    plan: plans[limit.name] ?? nil,
                    source: limit.source ?? (limit.name == "Codex" ? "endpoint" : nil),
                    checkedAt: limit.checkedAt ?? limit.cachedAt ?? (limit.name == "Codex" ? snapshot.lastUpdated : nil),
                    fiveHour: limit.shortWindow.map(Self.window),
                    weekly: limit.weeklyWindow.map(Self.window),
                    error: snapshot.providerErrors[limit.name]
                )
            }

        self.hourly = snapshot.usageBuckets.map { Hour(hourStart: $0.hourStart, totals: Self.totals($0)) }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var days: [String: LLMUsageBucket] = [:]
        for bucket in snapshot.usageBuckets {
            let key = "\(formatter.string(from: bucket.hourStart))|\(bucket.provider)"
            var day = days[key] ?? LLMUsageBucket(provider: bucket.provider, hourStart: bucket.hourStart)
            day.add(bucket)
            days[key] = day
        }
        self.daily = days
            .map { key, bucket in Day(date: String(key.prefix(10)), totals: Self.totals(bucket)) }
            .sorted { $0.date == $1.date ? $0.totals.provider < $1.totals.provider : $0.date < $1.date }
    }

    private static func window(_ window: LLMUsageWindow) -> Window {
        Window(
            remainingPercent: window.remainingPercent,
            usedPercent: window.usedPercent,
            resetsAt: window.resetAt,
            windowSeconds: window.windowSeconds,
            basis: window.isEstimate ? "estimated" : "measured",
            measuredRemainingPercent: window.isEstimate ? window.measuredRemainingPercent : nil,
            measuredUsedPercent: window.measuredUsedPercent
        )
    }

    private static func totals(_ bucket: LLMUsageBucket) -> Totals {
        Totals(
            provider: bucket.provider,
            tokens: bucket.tokens,
            inputTokens: bucket.inputTokens,
            cachedInputTokens: bucket.cachedInputTokens,
            cacheWriteInputTokens: bucket.cacheWriteInputTokens,
            outputTokens: bucket.outputTokens,
            requests: bucket.requests,
            // Cents are enough and keep tiny float noise from rewriting the file.
            estimatedCostUSD: (bucket.estimatedCostUSD * 10_000).rounded() / 10_000
        )
    }

    /// A newer `checkedAt` alone rewrites the file only once it has moved this far, so a 30-second poll that
    /// returns the same numbers does not rewrite the file every 30 seconds.
    static let checkedAtResolution: TimeInterval = 300

    /// True when both describe the same usage, ignoring when they were generated and small `checkedAt` moves.
    func sameContent(as other: UsageFeed) -> Bool {
        var copy = other
        copy.generatedAt = generatedAt
        if copy.providers.count == providers.count {
            for index in providers.indices {
                guard let mine = providers[index].checkedAt, let theirs = copy.providers[index].checkedAt,
                      abs(mine.timeIntervalSince(theirs)) < Self.checkedAtResolution else { continue }
                copy.providers[index].checkedAt = mine
            }
        }
        return copy == self
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Writes `usage-feed.json` atomically, and only when its content changed.
enum UsageFeedWriter {
    nonisolated(unsafe) private static var lastWritten: UsageFeed?
    private static let lock = NSLock()

    static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MaxxBar", isDirectory: true)
            .appendingPathComponent("usage-feed.json")
    }

    /// Returns true when the file was written.
    @discardableResult
    static func publish(
        _ snapshot: LLMUsageSnapshot,
        closedWindows: [UsageFeed.ClosedWindow] = [],
        to target: URL? = UsageFeedWriter.url
    ) -> Bool {
        // Nothing read yet (first launch tick): keep the last file instead of replacing it with an empty one.
        guard let target, !snapshot.limits.isEmpty || !snapshot.usageBuckets.isEmpty else { return false }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let feed = UsageFeed(snapshot: snapshot, closedWindows: closedWindows, appVersion: version)

        lock.lock()
        defer { lock.unlock() }
        if lastWritten == nil,
           let data = try? Data(contentsOf: target),
           let existing = try? UsageFeed.decoder().decode(UsageFeed.self, from: data) {
            lastWritten = existing
        }
        if let lastWritten, feed.sameContent(as: lastWritten) { return false }
        guard let data = try? UsageFeed.encoder().encode(feed) else { return false }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            lastWritten = feed
            return true
        } catch {
            return false
        }
    }
}
