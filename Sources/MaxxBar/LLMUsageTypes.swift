import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

struct LLMUsageWindow: Equatable {
    var label: String
    var usedPercent: Int
    var remainingPercent: Int
    var resetAt: Date?
    var windowSeconds: Int
}

struct LLMUsageLimit: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var primary: LLMUsageWindow?
    var secondary: LLMUsageWindow?
    var cachedAt: Date? = nil
    /// When this reading was taken, for display; set for Claude readings whether live or cached.
    var checkedAt: Date? = nil
    /// Where the reading came from: "statusline" (Claude Code's own rate_limits), "endpoint" (a live usage request),
    /// or "cache" (the last saved endpoint response).
    var source: String? = nil

    var windows: [LLMUsageWindow] {
        [primary, secondary].compactMap { $0 }
    }

    var shortWindow: LLMUsageWindow? {
        windows.first { $0.windowSeconds < 604_800 }
    }

    var weeklyWindow: LLMUsageWindow? {
        windows.first { $0.windowSeconds >= 604_800 }
    }
}

/// Token use and estimated API-price cost of one provider in one clock hour (local time).
/// Published to other apps through `usage-feed.json` (see `UsageFeed`).
struct LLMUsageBucket: Equatable {
    var provider: String
    var hourStart: Date
    var tokens: UInt64 = 0
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var cacheWriteInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var requests = 0
    var estimatedCostUSD: Double = 0

    mutating func add(_ call: LLMTokenCall, modelName: String) {
        let cost = LLMTokenPricing.rates(for: modelName, promptTokens: call.inputTokens).breakdown(
            inputTokens: call.inputTokens,
            cachedInputTokens: call.cachedInputTokens,
            cacheWriteInputTokens: call.cacheWriteInputTokens,
            cacheWrite1hInputTokens: call.cacheWrite1hInputTokens,
            outputTokens: call.outputTokens
        ).total
        tokens += call.inputTokens + call.outputTokens
        inputTokens += call.inputTokens
        cachedInputTokens += call.cachedInputTokens
        cacheWriteInputTokens += call.cacheWriteInputTokens
        outputTokens += call.outputTokens
        requests += 1
        estimatedCostUSD += cost
    }

    mutating func add(_ other: LLMUsageBucket) {
        tokens += other.tokens
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        cacheWriteInputTokens += other.cacheWriteInputTokens
        outputTokens += other.outputTokens
        requests += other.requests
        estimatedCostUSD += other.estimatedCostUSD
    }

    /// How many days of hourly buckets the readers keep.
    static let retentionSeconds: TimeInterval = 7 * 86_400

    /// Groups timestamped calls into hourly buckets for `provider`, dropping calls older than the retention window.
    static func hourly(
        provider: String,
        calls: [(call: LLMTokenCall, modelName: String)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LLMUsageBucket] {
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        var buckets: [Date: LLMUsageBucket] = [:]
        for item in calls {
            guard let timestamp = item.call.timestamp, timestamp >= cutoff, timestamp <= now.addingTimeInterval(300),
                  !item.modelName.localizedCaseInsensitiveContains("synthetic"),
                  let hour = calendar.dateInterval(of: .hour, for: timestamp)?.start else { continue }
            buckets[hour, default: LLMUsageBucket(provider: provider, hourStart: hour)].add(item.call, modelName: item.modelName)
        }
        return buckets.values.filter { $0.requests > 0 }.sorted { $0.hourStart < $1.hourStart }
    }
}

struct LLMResetCreditExpiration: Identifiable, Equatable {
    var id: String { "\(Int(expiresAt.timeIntervalSince1970))-\(count)" }
    var count: Int
    var expiresAt: Date
}

struct LLMLocalUsageWindow: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var tokens: UInt64
    var threads: Int
}

struct LLMUsageSession: Identifiable, Equatable {
    var id: String
    var provider: String
    var title: String
    var projectName: String
    var modelName: String
    var preview: String
    var rolloutPath: String
    var tokens: UInt64
    var tokenUsage: LLMTokenUsageSummary?
    var createdAt: Date?
    var updatedAt: Date?

    var detail: String {
        "\(provider) • \(projectName) • \(modelName)"
    }
}

/// One model request. `inputTokens` is the whole prompt, including cache reads and cache writes.
struct LLMTokenCall: Equatable {
    static let rebuildMinimumPromptTokens: UInt64 = 30_000

    var timestamp: Date?
    var inputTokens: UInt64
    var cachedInputTokens: UInt64
    var cacheWriteInputTokens: UInt64 = 0
    var cacheWrite1hInputTokens: UInt64 = 0
    var outputTokens: UInt64

    /// A near-full cache rebuild: at least half of a 30K+ prompt was not read from cache.
    var isCacheRebuild: Bool {
        guard inputTokens >= Self.rebuildMinimumPromptTokens else { return false }
        let uncached = inputTokens - min(cachedInputTokens, inputTokens)
        return uncached * 2 >= inputTokens
    }
}

struct LLMTokenWindowUsage: Equatable {
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var cacheWriteInputTokens: UInt64 = 0
    var cacheWrite1hInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var callCount = 0
    var rebuildCount = 0

    var totalTokens: UInt64 {
        inputTokens + outputTokens
    }

    func costBreakdown(for modelName: String) -> LLMCostBreakdown {
        LLMTokenPricing.rates(for: modelName).breakdown(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            cacheWrite1hInputTokens: cacheWrite1hInputTokens,
            outputTokens: outputTokens
        )
    }
}

extension LLMTokenWindowUsage {
    init<Calls: Sequence>(calls: Calls) where Calls.Element == LLMTokenCall {
        for call in calls {
            inputTokens += call.inputTokens
            cachedInputTokens += call.cachedInputTokens
            cacheWriteInputTokens += call.cacheWriteInputTokens
            cacheWrite1hInputTokens += call.cacheWrite1hInputTokens
            outputTokens += call.outputTokens
            callCount += 1
            if call.isCacheRebuild {
                rebuildCount += 1
            }
        }
    }
}

struct LLMCostBreakdown: Equatable {
    var freshInput: Double
    var cacheWrite: Double
    var cacheRead: Double
    var output: Double

    var total: Double {
        freshInput + cacheWrite + cacheRead + output
    }
}

struct LLMTokenUsageSummary: Equatable {
    var inputTokens: UInt64
    var cachedInputTokens: UInt64
    var outputTokens: UInt64
    var reasoningOutputTokens: UInt64
    var totalTokens: UInt64
    var turnCount: Int
    var cacheWriteInputTokens: UInt64 = 0
    var cacheWrite1hInputTokens: UInt64 = 0
    var rebuildCount = 0
    var peakContextTokens: UInt64 = 0
    var last24h: LLMTokenWindowUsage? = nil

    var nonCachedInputTokens: UInt64 {
        inputTokens >= cachedInputTokens ? inputTokens - cachedInputTokens : 0
    }

    var freshInputTokens: UInt64 {
        nonCachedInputTokens - min(cacheWriteInputTokens, nonCachedInputTokens)
    }

    var cacheHitPercent: Int {
        guard inputTokens > 0 else { return 0 }
        return Int((Double(cachedInputTokens) / Double(inputTokens) * 100).rounded())
    }

    var lifetime: LLMTokenWindowUsage {
        LLMTokenWindowUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            cacheWrite1hInputTokens: cacheWrite1hInputTokens,
            outputTokens: outputTokens,
            callCount: turnCount,
            rebuildCount: rebuildCount
        )
    }

    func costBreakdown(for modelName: String) -> LLMCostBreakdown {
        lifetime.costBreakdown(for: modelName)
    }

    func estimatedCost(for modelName: String) -> Double {
        costBreakdown(for: modelName).total
    }

    func pricingLabel(for modelName: String) -> String {
        LLMTokenPricing.rates(for: modelName).label
    }
}

extension LLMTokenUsageSummary {
    /// Lifetime totals from per-request calls; `last24h` covers only calls in the 24 hours before `now`.
    init(calls: [LLMTokenCall], now: Date = Date()) {
        let lifetime = LLMTokenWindowUsage(calls: calls)
        self.init(
            inputTokens: lifetime.inputTokens,
            cachedInputTokens: lifetime.cachedInputTokens,
            outputTokens: lifetime.outputTokens,
            reasoningOutputTokens: 0,
            totalTokens: lifetime.totalTokens,
            turnCount: lifetime.callCount,
            cacheWriteInputTokens: lifetime.cacheWriteInputTokens,
            cacheWrite1hInputTokens: lifetime.cacheWrite1hInputTokens,
            rebuildCount: lifetime.rebuildCount,
            peakContextTokens: calls.map(\.inputTokens).max() ?? 0,
            last24h: LLMTokenWindowUsage(calls: calls.filter { ($0.timestamp ?? .distantPast) >= now.addingTimeInterval(-86_400) })
        )
    }
}

/// API list prices in USD per million tokens, one table for every estimate in the app. Each model stores its
/// own cache write (5 minute and 1 hour) and cache read rates. Models are matched by the longest ID prefix,
/// tolerating suffixes such as "[1m]" or a date, but never a further version number ("claude-fable-5-2" is not
/// "claude-fable-5"). Two models price by prompt size per request: Haiku 5.5 above 100K prompt tokens and the
/// GPT-5.6 family and gpt-5.5 above 272K input tokens. Claude 4.6 and later have no long context surcharge.
struct LLMTokenPricing: Equatable {
    /// When the table was last checked against platform.claude.com/docs/en/about-claude/pricing and
    /// developers.openai.com/api/docs/pricing.
    static let asOf = "2026-11-16"
    static let checkedLabel = "rates checked \(asOf)"

    var label: String
    var freshInputDollarsPerMillion: Double
    var cacheWrite5mDollarsPerMillion: Double
    var cacheWrite1hDollarsPerMillion: Double
    var cachedInputDollarsPerMillion: Double
    var outputDollarsPerMillion: Double
    /// False when the model is not in the table and a family's rates stand in for it.
    var isKnown = true

    /// OpenAI rows: no cache write premium.
    init(label: String, freshInputDollarsPerMillion: Double, cachedInputDollarsPerMillion: Double, outputDollarsPerMillion: Double) {
        self.init(label: label, input: freshInputDollarsPerMillion, write5m: freshInputDollarsPerMillion,
                  write1h: freshInputDollarsPerMillion, read: cachedInputDollarsPerMillion, output: outputDollarsPerMillion)
    }

    init(label: String, input: Double, write5m: Double, write1h: Double, read: Double, output: Double) {
        self.label = label
        freshInputDollarsPerMillion = input
        cacheWrite5mDollarsPerMillion = write5m
        cacheWrite1hDollarsPerMillion = write1h
        cachedInputDollarsPerMillion = read
        outputDollarsPerMillion = output
    }

    private static func claude(_ label: String, _ input: Double, _ write5m: Double, _ write1h: Double, _ read: Double, _ output: Double) -> LLMTokenPricing {
        LLMTokenPricing(label: "\(label) API", input: input, write5m: write5m, write1h: write1h, read: read, output: output)
    }

    private static func openAI(_ label: String, _ input: Double, _ cached: Double, _ output: Double) -> LLMTokenPricing {
        LLMTokenPricing(label: "\(label) API", freshInputDollarsPerMillion: input, cachedInputDollarsPerMillion: cached, outputDollarsPerMillion: output)
    }

    static let gpt55 = openAI("gpt-5.5", 5.00, 0.50, 30.00)

    private struct Row {
        var prefix: String
        var pricing: LLMTokenPricing
        /// Prompts over `threshold` tokens in one request use `pricing` from here instead.
        var longPrompt: (threshold: UInt64, pricing: LLMTokenPricing)? = nil
    }

    private static let table: [Row] = {
        let fable52 = claude("Claude Fable 5.2", 8, 10, 16, 0.20, 40)
        let fable51 = claude("Claude Fable 5.1", 10, 12.50, 20, 0.25, 50)
        let fable5 = claude("Claude Fable 5", 10, 12.50, 20, 1.00, 50)
        let opus5 = claude("Claude Opus 5 / 4.5-4.8", 5, 6.25, 10, 0.50, 25)
        let opus4 = claude("Claude Opus 4 / 4.1", 15, 18.75, 30, 1.50, 75)
        let sonnet4 = claude("Claude Sonnet 4 / 4.5 / 4.6", 3, 3.75, 6, 0.30, 15)
        let gpt56Sol = openAI("gpt-5.6-sol", 4.00, 0.40, 20.00), gpt56SolLong = openAI("gpt-5.6-sol (over 272K)", 8, 0.80, 30)
        let gpt56Terra = openAI("gpt-5.6-terra", 2.00, 0.20, 12.00), gpt56TerraLong = openAI("gpt-5.6-terra (over 272K)", 4, 0.40, 18)
        let gpt56Luna = openAI("gpt-5.6-luna", 0.20, 0.02, 1.20), gpt56LunaLong = openAI("gpt-5.6-luna (over 272K)", 0.40, 0.04, 1.80)
        let gpt52 = openAI("gpt-5.2", 1.75, 0.175, 14.00)
        let gpt51 = openAI("gpt-5.1", 1.25, 0.125, 10.00)
        return [
            Row(prefix: "claude-fable-5-2", pricing: fable52),
            Row(prefix: "claude-mythos-5-2", pricing: fable52),
            Row(prefix: "claude-fable-5-1", pricing: fable51),
            Row(prefix: "claude-mythos-5-1", pricing: fable51),
            Row(prefix: "claude-fable-5", pricing: fable5),
            Row(prefix: "claude-mythos-5", pricing: fable5),
            Row(prefix: "claude-opus-5-5", pricing: claude("Claude Opus 5.5", 4, 5, 8, 0.20, 20)),
            Row(prefix: "claude-opus-5", pricing: opus5),
            Row(prefix: "claude-opus-4-8", pricing: opus5),
            Row(prefix: "claude-opus-4-7", pricing: opus5),
            Row(prefix: "claude-opus-4-6", pricing: opus5),
            Row(prefix: "claude-opus-4-5", pricing: opus5),
            Row(prefix: "claude-opus-4-1", pricing: opus4),
            Row(prefix: "claude-opus-4", pricing: opus4),
            Row(prefix: "claude-sonnet-5-5", pricing: claude("Claude Sonnet 5.5", 2, 2.50, 4, 0.10, 10)),
            Row(prefix: "claude-sonnet-5", pricing: claude("Claude Sonnet 5", 2, 2.50, 4, 0.20, 10)),
            Row(prefix: "claude-sonnet-4-6", pricing: sonnet4),
            Row(prefix: "claude-sonnet-4-5", pricing: sonnet4),
            Row(prefix: "claude-sonnet-4", pricing: sonnet4),
            Row(prefix: "claude-haiku-5-5", pricing: claude("Claude Haiku 5.5", 0.10, 0.125, 0.20, 0.01, 0.50),
                longPrompt: (100_000, claude("Claude Haiku 5.5 (over 100K prompt)", 0.50, 0.625, 1.00, 0.05, 2.50))),
            Row(prefix: "claude-haiku-4-5", pricing: claude("Claude Haiku 4.5", 1, 1.25, 2, 0.10, 5)),
            Row(prefix: "gpt-5.6-sol", pricing: gpt56Sol, longPrompt: (272_000, gpt56SolLong)),
            Row(prefix: "gpt-5.6-terra", pricing: gpt56Terra, longPrompt: (272_000, gpt56TerraLong)),
            Row(prefix: "gpt-5.6-luna", pricing: gpt56Luna, longPrompt: (272_000, gpt56LunaLong)),
            Row(prefix: "gpt-5.5", pricing: gpt55, longPrompt: (272_000, openAI("gpt-5.5 (over 272K)", 10, 1.00, 45))),
            Row(prefix: "gpt-5.4-mini", pricing: openAI("gpt-5.4-mini", 0.75, 0.075, 4.50)),
            Row(prefix: "gpt-5.4-nano", pricing: openAI("gpt-5.4-nano", 0.20, 0.02, 1.25)),
            Row(prefix: "gpt-5.4", pricing: openAI("gpt-5.4", 2.50, 0.25, 15.00)),
            Row(prefix: "gpt-5.3-codex", pricing: openAI("gpt-5.3-codex", 1.75, 0.175, 14.00)),
            Row(prefix: "gpt-5.2-codex", pricing: gpt52),
            Row(prefix: "gpt-5.2", pricing: gpt52),
            Row(prefix: "gpt-5.1-codex", pricing: gpt51),
            Row(prefix: "gpt-5.1", pricing: gpt51),
            Row(prefix: "gpt-5-codex", pricing: openAI("gpt-5", 1.25, 0.125, 10.00)),
            Row(prefix: "gpt-5-mini", pricing: openAI("gpt-5-mini", 0.25, 0.025, 2.00)),
            Row(prefix: "gpt-5-nano", pricing: openAI("gpt-5-nano", 0.05, 0.005, 0.40)),
            Row(prefix: "gpt-5", pricing: openAI("gpt-5", 1.25, 0.125, 10.00)),
            Row(prefix: "codex-mini", pricing: openAI("codex-mini", 1.5, 0.375, 6.0))
        ].sorted { $0.prefix.count > $1.prefix.count }
    }()

    /// "Claude Opus 4.8", "us.anthropic.claude-opus-4-8-v1" and "claude-opus-4-8[1m]" all become claude-opus-4-8….
    static func normalizedModelID(_ modelName: String) -> String {
        var model = modelName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = model.range(of: "claude") { model = String(model[range.lowerBound...]) }
        let families = ["fable", "mythos", "opus", "sonnet", "haiku"]
        if model.hasPrefix("claude") || families.contains(where: { model.hasPrefix($0) }) {
            model = model.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: "-")
            if !model.hasPrefix("claude-") {
                model = "claude-" + (model.hasPrefix("claude") ? String(model.dropFirst("claude".count)) : model)
            }
        }
        return model
    }

    /// Whether a table prefix ends where the model ID's own name does. Rejected: the middle of a number
    /// ("claude-fable-5-2" inside "claude-fable-5-20261101") and another version number ("-2" after
    /// "claude-fable-5", ".4" after "gpt-5"). Accepted: nothing, a date ("-20250514"), "[1m]", a variant name.
    private static func endsAtBoundary(_ remainder: Substring) -> Bool {
        guard let first = remainder.first else { return true }
        guard !first.isLetter, !first.isNumber else { return false }
        guard first == "-" || first == "." else { return true }
        let digits = remainder.dropFirst().prefix { $0.isNumber }
        return !(1...2).contains(digits.count)
    }

    /// Rates for one request. Pass the request's whole prompt (`promptTokens`: input plus cache reads and writes)
    /// so models that price by prompt size pick the right tier; aggregates leave it nil and use the base tier.
    static func rates(for modelName: String, promptTokens: UInt64? = nil) -> LLMTokenPricing {
        let model = normalizedModelID(modelName)
        if let row = table.first(where: { model.hasPrefix($0.prefix) && endsAtBoundary(model.dropFirst($0.prefix.count)) }) {
            if let long = row.longPrompt, let promptTokens, promptTokens > long.threshold { return long.pricing }
            return row.pricing
        }
        // Not in the table: a family's newest rates stand in, labelled as an estimate.
        let family: [(String, String)] = [
            ("fable", "claude-fable-5-2"), ("mythos", "claude-fable-5-2"), ("opus", "claude-opus-5-5"),
            ("sonnet", "claude-sonnet-5-5"), ("haiku", "claude-haiku-5-5")
        ]
        var fallback = family.first { model.contains($0.0) }.map { rates(for: $0.1) } ?? gpt55
        fallback.label = "\(fallback.label) rates (model has no known price)"
        fallback.isKnown = false
        return fallback
    }

    func estimatedCost(
        freshInputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64
    ) -> Double {
        dollars(for: freshInputTokens, rate: freshInputDollarsPerMillion)
            + dollars(for: cachedInputTokens, rate: cachedInputDollarsPerMillion)
            + dollars(for: outputTokens, rate: outputDollarsPerMillion)
    }

    /// `inputTokens` is the whole prompt; cache reads, 5 minute and 1 hour cache writes are carved out of it.
    func breakdown(
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        cacheWriteInputTokens: UInt64,
        cacheWrite1hInputTokens: UInt64,
        outputTokens: UInt64
    ) -> LLMCostBreakdown {
        let uncached = inputTokens - min(cachedInputTokens, inputTokens)
        let writes = min(cacheWriteInputTokens, uncached)
        let writes1h = min(cacheWrite1hInputTokens, writes)
        return LLMCostBreakdown(
            freshInput: dollars(for: uncached - writes, rate: freshInputDollarsPerMillion),
            cacheWrite: dollars(for: writes - writes1h, rate: cacheWrite5mDollarsPerMillion)
                + dollars(for: writes1h, rate: cacheWrite1hDollarsPerMillion),
            cacheRead: dollars(for: cachedInputTokens, rate: cachedInputDollarsPerMillion),
            output: dollars(for: outputTokens, rate: outputDollarsPerMillion)
        )
    }

    private func dollars(for tokens: UInt64, rate: Double) -> Double {
        Double(tokens) / 1_000_000 * rate
    }
}

struct LLMTokenCostEstimate: Identifiable, Equatable {
    static let freshInputDollarsPerMillion = LLMTokenPricing.gpt55.freshInputDollarsPerMillion
    static let cachedInputDollarsPerMillion = LLMTokenPricing.gpt55.cachedInputDollarsPerMillion
    static let outputDollarsPerMillion = LLMTokenPricing.gpt55.outputDollarsPerMillion

    var id: String { label }
    var label: String
    var sessionCount: Int
    var inputTokens: UInt64
    var cachedInputTokens: UInt64
    var outputTokens: UInt64
    var totalTokens: UInt64
    var windowStartedAt: Date
    var windowEndedAt: Date

    var freshInputTokens: UInt64 {
        inputTokens >= cachedInputTokens ? inputTokens - cachedInputTokens : 0
    }

    var cacheHitPercent: Int {
        guard inputTokens > 0 else { return 0 }
        return Int((Double(cachedInputTokens) / Double(inputTokens) * 100).rounded())
    }

    var estimatedCost: Double {
        LLMTokenPricing.gpt55.estimatedCost(
            freshInputTokens: freshInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens
        )
    }
}

struct LLMUsageWindowLogEntry: Codable, Equatable {
    var recordedAt: Date
    /// Missing in lines written before provider support; those lines are Codex.
    var provider: String? = nil
    var windowLabel: String
    var windowStartedAt: Date
    var windowEndedAt: Date
    var sessionCount: Int
    var totalInputTokens: UInt64
    var cachedInputTokens: UInt64
    var freshInputTokens: UInt64
    var outputTokens: UInt64
    var totalTokens: UInt64
    var cacheHitPercent: Int
    var estimatedCostUSD: Double
    var freshInputDollarsPerMillion: Double
    var cachedInputDollarsPerMillion: Double
    var outputDollarsPerMillion: Double

    init(recordedAt: Date = Date(), provider: String? = nil, estimate: LLMTokenCostEstimate) {
        self.recordedAt = recordedAt
        self.provider = provider
        self.windowLabel = estimate.label
        self.windowStartedAt = estimate.windowStartedAt
        self.windowEndedAt = estimate.windowEndedAt
        self.sessionCount = estimate.sessionCount
        self.totalInputTokens = estimate.inputTokens
        self.cachedInputTokens = estimate.cachedInputTokens
        self.freshInputTokens = estimate.freshInputTokens
        self.outputTokens = estimate.outputTokens
        self.totalTokens = estimate.totalTokens
        self.cacheHitPercent = estimate.cacheHitPercent
        self.estimatedCostUSD = estimate.estimatedCost
        self.freshInputDollarsPerMillion = LLMTokenCostEstimate.freshInputDollarsPerMillion
        self.cachedInputDollarsPerMillion = LLMTokenCostEstimate.cachedInputDollarsPerMillion
        self.outputDollarsPerMillion = LLMTokenCostEstimate.outputDollarsPerMillion
    }
}

/// One point of quota history. The first four fields predate Claude support and hold Codex values
/// (`planType` is the Codex plan). Every later field is optional so files written by older builds still decode.
struct LLMQuotaHistorySample: Identifiable, Equatable, Codable {
    var id = UUID()
    var sampledAt: Date
    var primaryRemainingPercent: Int?
    var weeklyRemainingPercent: Int?
    var planType: String? = nil
    var claudeWeeklyRemainingPercent: Int? = nil
    var claudeFiveHourRemainingPercent: Int? = nil
    /// The Claude plan at the time of the sample, for example "Max 5x". A plan change starts a new drawdown segment.
    var claudePlanType: String? = nil
    /// Where the Claude reading came from (see `LLMUsageLimit.source`).
    var claudeSource: String? = nil
    var codexFiveHourResetAt: Date? = nil
    var codexWeeklyResetAt: Date? = nil
    var claudeFiveHourResetAt: Date? = nil
    var claudeWeeklyResetAt: Date? = nil
    /// Per-model weekly windows (for example "Fable"), keyed by model display name. Absent in older rows.
    var claudeModelWeeklyRemaining: [String: Int]? = nil
    var claudeModelWeeklyResetAt: [String: Date]? = nil

    func weeklyRemainingPercent(for provider: String) -> Int? {
        provider == "Claude" ? claudeWeeklyRemainingPercent : weeklyRemainingPercent
    }

    func plan(for provider: String) -> String? {
        provider == "Claude" ? claudePlanType : planType
    }

    func weeklyResetAt(for provider: String) -> Date? {
        provider == "Claude" ? claudeWeeklyResetAt : codexWeeklyResetAt
    }

    func fiveHourRemainingPercent(for provider: String) -> Int? {
        provider == "Claude" ? claudeFiveHourRemainingPercent : primaryRemainingPercent
    }

    func fiveHourResetAt(for provider: String) -> Date? {
        provider == "Claude" ? claudeFiveHourResetAt : codexFiveHourResetAt
    }
}

struct LLMQuotaActivitySignature: Equatable {
    var primaryRemainingPercent: Int?
    var weeklyRemainingPercent: Int?
    var planType: String?
    var claudeWeeklyRemainingPercent: Int?
    var claudeFiveHourRemainingPercent: Int?
    var claudePlanType: String?
    var localFiveHourTokens: UInt64
    var localWeeklyTokens: UInt64
    var localWeeklyThreads: Int
    var latestSessionUpdateSecond: Int?

    init(usage: LLMUsageSnapshot) {
        let codex = usage.limits.first { $0.name == "Codex" }
        let claude = usage.limits.first { $0.name == "Claude" }
        self.primaryRemainingPercent = codex?.shortWindow?.remainingPercent
        self.weeklyRemainingPercent = codex?.weeklyWindow?.remainingPercent
        self.claudeWeeklyRemainingPercent = claude?.weeklyWindow?.remainingPercent
        self.claudeFiveHourRemainingPercent = claude?.shortWindow?.remainingPercent
        self.claudePlanType = usage.claudePlanType
        self.planType = usage.planType
        self.localFiveHourTokens = usage.localFiveHourTokens
        self.localWeeklyTokens = usage.localWeeklyTokens
        self.localWeeklyThreads = usage.localWeeklyThreads
        self.latestSessionUpdateSecond = (usage.recentSessions + usage.topWeeklySessions)
            .compactMap(\.updatedAt)
            .map { Int($0.timeIntervalSince1970) }
            .max()
    }
}

struct LLMUsageSnapshot: Equatable {
    var email: String?
    var planType: String?
    var limits: [LLMUsageLimit]
    var creditsBalance: String?
    var resetCreditCount: Int?
    var resetCreditExpirations: [LLMResetCreditExpiration]
    var lastUpdated: Date?
    var localFiveHourTokens: UInt64
    var localWeeklyTokens: UInt64
    var localWeeklyThreads: Int
    var localWindows: [LLMLocalUsageWindow]
    var costEstimates: [LLMTokenCostEstimate]
    var recentSessions: [LLMUsageSession]
    var topWeeklySessions: [LLMUsageSession]
    var error: String?
    var providerErrors: [String: String] = [:]
    var weeklyModelUsage: [LLMModelUsageTotal] = []
    var dailyModelUsage: [LLMModelUsageTotal] = []
    var providerAccounts: [LLMProviderAccount] = []
    /// Hourly token and cost totals per provider for the last 7 days, oldest first.
    var usageBuckets: [LLMUsageBucket] = []
    /// API cost equivalents by provider, from the daily ledger.
    var apiCost: [String: APICostSummary] = [:]

    /// The Claude plan from the local Claude profile. `planType` above is the Codex plan.
    var claudePlanType: String? {
        providerAccounts.first { $0.provider == "Claude" }?.planName
    }
}

struct LLMProviderAccount: Identifiable, Equatable {
    var id: String { provider.lowercased() }
    let provider: String
    let email: String?
    let displayName: String?
    let organizationName: String?
    let planName: String?
}

struct LLMModelUsageTotal: Equatable {
    let provider: String
    let modelName: String
    let tokens: UInt64
    let sessionCount: Int
}

struct LLMModelUsage: Identifiable, Equatable {
    var id: String { "\(provider.lowercased())|\(modelName.lowercased())" }
    let provider: String
    let modelName: String
    let tokens: UInt64
    let sessionCount: Int
    let sharePercent: Int
}

struct LLMModelUsageSummary: Equatable {
    let models: [LLMModelUsage]
    let totalTokens: UInt64
    let sessionCount: Int
    let distributionBasis: String
}

extension LLMUsageSnapshot {
    func modelUsageSummary(provider: String? = nil, lastSeconds: TimeInterval = 604_800) -> LLMModelUsageSummary {
        struct Aggregate {
            var provider: String
            var modelName: String
            var tokens: UInt64
            var sessionCount: Int
        }

        var aggregates: [String: Aggregate] = [:]
        let recordedModelUsage = lastSeconds <= 86_400 ? dailyModelUsage : weeklyModelUsage
        let selectedRecordedModelUsage = recordedModelUsage.filter {
            provider == nil || $0.provider.caseInsensitiveCompare(provider!) == .orderedSame
        }
        let recordedProviders = Set(selectedRecordedModelUsage.map { $0.provider.lowercased() })

        for total in selectedRecordedModelUsage {
            let key = "\(total.provider.lowercased())|\(total.modelName.lowercased())"
            aggregates[key] = Aggregate(
                provider: total.provider,
                modelName: total.modelName,
                tokens: total.tokens,
                sessionCount: total.sessionCount
            )
        }

        // A provider-specific reader can fail independently (for example, after a
        // local database schema change). Keep the other provider's exact totals,
        // then fill only the missing provider from discovered sessions.
        if selectedRecordedModelUsage.isEmpty || provider == nil {
            let cutoff = Date().addingTimeInterval(-lastSeconds)
            var seen = Set<String>()
            let sessions = (recentSessions + topWeeklySessions).filter { session in
                guard seen.insert("\(session.provider.lowercased()):\(session.id)").inserted else { return false }
                if let provider,
                   session.provider.caseInsensitiveCompare(provider) != .orderedSame {
                    return false
                }
                if recordedProviders.contains(session.provider.lowercased()) {
                    return false
                }
                guard let timestamp = session.updatedAt ?? session.createdAt else { return true }
                return timestamp >= cutoff
            }
            for session in sessions {
                let modelName = session.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = modelName.isEmpty ? "Model unavailable" : modelName
                let key = "\(session.provider.lowercased())|\(displayName.lowercased())"
                var aggregate = aggregates[key] ?? Aggregate(
                    provider: session.provider,
                    modelName: displayName,
                    tokens: 0,
                    sessionCount: 0
                )
                aggregate.tokens += session.tokenUsage?.totalTokens ?? session.tokens
                aggregate.sessionCount += 1
                aggregates[key] = aggregate
            }
        }

        let sorted = aggregates.values.sorted {
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            if $0.sessionCount != $1.sessionCount { return $0.sessionCount > $1.sessionCount }
            return $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending
        }
        let totalTokens = sorted.reduce(UInt64(0)) { $0 + $1.tokens }
        let totalSessions = sorted.reduce(0) { $0 + $1.sessionCount }
        let usesTokenShare = totalTokens > 0
        let weights = sorted.map { usesTokenShare ? Double($0.tokens) : Double($0.sessionCount) }
        let totalWeight = weights.reduce(0, +)
        let rawShares = weights.map { totalWeight > 0 ? $0 / totalWeight * 100 : 0 }
        var shares = rawShares.map { Int($0.rounded(.down)) }
        let pointsToAssign = max(0, 100 - shares.reduce(0, +))
        let fractionalOrder = rawShares.indices.sorted {
            let lhs = rawShares[$0] - Double(shares[$0])
            let rhs = rawShares[$1] - Double(shares[$1])
            return lhs == rhs ? $0 < $1 : lhs > rhs
        }
        if !fractionalOrder.isEmpty {
            for index in 0..<pointsToAssign {
                shares[fractionalOrder[index % fractionalOrder.count]] += 1
            }
        }

        let models = sorted.enumerated().map { index, aggregate in
            LLMModelUsage(
                provider: aggregate.provider,
                modelName: aggregate.modelName,
                tokens: aggregate.tokens,
                sessionCount: aggregate.sessionCount,
                sharePercent: shares[index]
            )
        }
        return LLMModelUsageSummary(
            models: models,
            totalTokens: totalTokens,
            sessionCount: totalSessions,
            distributionBasis: usesTokenShare ? "recorded tokens" : "sessions"
        )
    }
}
