import Foundation

/// Estimates Claude 5h and weekly usage between real readings from the tokens MaxxBar already counts in local
/// transcripts. Pure: callers pass readings and token points in, and nothing here touches disk or the network.
///
/// Calibration: for consecutive pairs of real readings inside the same window (same reset time), the tokens
/// spent between them divided by the percent the reading moved gives tokens-per-percent. Pairs are pooled
/// (total tokens over total percent), which absorbs the whole-percent rounding of each reading. Only pairs
/// taken on the current plan and since `since` count. Two measures are tried: raw tokens and tokens weighted
/// by each model's API prices; the weighted one is used only when its per-pair ratios agree more closely.
///
/// Estimates are never written back as readings: the quota history and the window ledger only hold real ones.
enum ClaudeQuotaEstimator {
    enum Kind: String, Codable, CaseIterable {
        case fiveHour
        case weekly
    }

    /// One real reading (endpoint, status line, or the saved endpoint response), never an estimate.
    struct Reading: Codable, Equatable {
        var at: Date
        var kind: Kind
        var usedPercent: Double
        var resetAt: Date?
        var plan: String?
        var source: String?
    }

    /// Claude tokens counted in one stretch of time (the app uses one point per minute).
    struct UsagePoint: Equatable {
        var at: Date
        var tokens: Double
        /// Tokens weighted by each model's API prices, in $5-per-million input token equivalents.
        var weightedTokens: Double
    }

    struct Calibration: Equatable {
        var tokensPerPercent: Double
        /// True when the price-weighted measure fitted the readings better than raw tokens.
        var weighted: Bool
        /// Pairs in which the reading moved.
        var pairs: Int
    }

    struct Estimate: Equatable {
        var usedPercent: Double
        var basedOn: Reading
        var at: Date
    }

    static let minimumMovingPairs = 3
    static let minimumPercentMoved = 3.0
    /// Endpoint reset times wobble by a few seconds between reads; a real reset moves them by hours.
    static let sameWindowTolerance: TimeInterval = 600

    static func sameWindow(_ a: Reading, _ b: Reading) -> Bool {
        guard a.kind == b.kind, let first = a.resetAt, let second = b.resetAt else { return false }
        return abs(first.timeIntervalSince(second)) < sameWindowTolerance
    }

    /// Prefix sums over usage points sorted by time, so each pair costs two binary searches.
    struct Ledger {
        private let times: [Date]
        private let raw: [Double]
        private let weighted: [Double]

        init(_ points: [UsagePoint]) {
            let sorted = points.sorted { $0.at < $1.at }
            times = sorted.map(\.at)
            var rawSum = [0.0], weightedSum = [0.0]
            for point in sorted {
                rawSum.append(rawSum[rawSum.count - 1] + max(point.tokens, 0))
                weightedSum.append(weightedSum[weightedSum.count - 1] + max(point.weightedTokens, 0))
            }
            raw = rawSum
            weighted = weightedSum
        }

        /// Tokens in points stamped after `start` and at or before `end`.
        func tokens(after start: Date, through end: Date, weighted useWeighted: Bool) -> Double {
            guard end > start else { return 0 }
            let sums = useWeighted ? weighted : raw
            return sums[upperIndex(end)] - sums[upperIndex(start)]
        }

        /// Number of points stamped at or before `date`.
        private func upperIndex(_ date: Date) -> Int {
            var low = 0, high = times.count
            while low < high {
                let mid = (low + high) / 2
                if times[mid] <= date { low = mid + 1 } else { high = mid }
            }
            return low
        }
    }

    /// The start of the trailing run of readings on `plan`: earlier readings were taken on another plan.
    static func planStart(of readings: [Reading], plan: String?) -> Date? {
        let sorted = readings.sorted { $0.at < $1.at }
        guard let plan, sorted.last?.plan == plan else { return nil }
        var start = sorted.last?.at
        for reading in sorted.reversed() {
            guard reading.plan == plan else { break }
            start = reading.at
        }
        return start
    }

    static func calibrate(
        readings: [Reading], usage: [UsagePoint], kind: Kind, plan: String?, since: Date
    ) -> Calibration? {
        calibrate(readings: readings, ledger: Ledger(usage), kind: kind, plan: plan, since: since)
    }

    static func calibrate(
        readings: [Reading], ledger: Ledger, kind: Kind, plan: String?, since: Date
    ) -> Calibration? {
        let usable = readings
            .filter { $0.kind == kind && $0.at >= since && $0.plan == plan }
            .sorted { $0.at < $1.at }
        var pairs: [(percent: Double, raw: Double, weighted: Double)] = []
        for (earlier, later) in zip(usable, usable.dropFirst()) where sameWindow(earlier, later) {
            let percent = later.usedPercent - earlier.usedPercent
            // A drop inside one window is a correction or a bad read, not usage.
            guard percent >= 0 else { continue }
            pairs.append((
                percent,
                ledger.tokens(after: earlier.at, through: later.at, weighted: false),
                ledger.tokens(after: earlier.at, through: later.at, weighted: true)
            ))
        }
        let moving = pairs.filter { $0.percent > 0 }
        let totalPercent = pairs.reduce(0) { $0 + $1.percent }
        guard moving.count >= minimumMovingPairs, totalPercent >= minimumPercentMoved else { return nil }

        func spread(_ value: (Double, Double, Double) -> Double) -> Double? {
            // Percent-weighted coefficient of variation of the per-pair ratios.
            let ratios = moving.map { (ratio: value($0.percent, $0.raw, $0.weighted) / $0.percent, weight: $0.percent) }
            let weight = ratios.reduce(0) { $0 + $1.weight }
            let mean = ratios.reduce(0) { $0 + $1.ratio * $1.weight } / weight
            guard mean > 0 else { return nil }
            let variance = ratios.reduce(0) { $0 + $1.weight * pow($1.ratio - mean, 2) } / weight
            return variance.squareRoot() / mean
        }
        let rawSpread = spread { _, raw, _ in raw }
        let weightedSpread = spread { _, _, weighted in weighted }
        let useWeighted: Bool
        switch (rawSpread, weightedSpread) {
        case let (raw?, weighted?): useWeighted = weighted < raw
        case (nil, .some): useWeighted = true
        default: useWeighted = false
        }
        let tokens = pairs.reduce(0) { $0 + (useWeighted ? $1.weighted : $1.raw) }
        guard tokens > 0 else { return nil }
        return Calibration(tokensPerPercent: tokens / totalPercent, weighted: useWeighted, pairs: moving.count)
    }

    /// Usage now, from the last real reading plus the tokens counted since. Nil when there is nothing to add or
    /// the reading's window has reset. Pass the previous estimate so the value never steps down within a window.
    static func estimate(
        from reading: Reading, calibration: Calibration, ledger: Ledger, now: Date, previous: Estimate? = nil
    ) -> Estimate? {
        guard now > reading.at, calibration.tokensPerPercent > 0 else { return nil }
        if let reset = reading.resetAt, reset <= now { return nil }
        let tokens = ledger.tokens(after: reading.at, through: now, weighted: calibration.weighted)
        guard tokens > 0 else { return nil }
        var used = reading.usedPercent + tokens / calibration.tokensPerPercent
        if let previous, previous.basedOn == reading { used = max(used, previous.usedPercent) }
        return Estimate(usedPercent: min(max(used, 0), 100), basedOn: reading, at: now)
    }
}

/// `claude-readings.json`: the real Claude readings the estimator calibrates from, kept for 8 days.
/// Only real readings go in; estimates never do.
enum ClaudeReadingLog {
    static let retention: TimeInterval = 8 * 86_400
    static let maximumCount = 6_000
    private static let lock = NSLock()

    static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/claude-readings.json")
    }

    /// Adds readings not already logged and drops old ones. Returns the log after the change.
    static func merge(
        _ existing: [ClaudeQuotaEstimator.Reading], adding new: [ClaudeQuotaEstimator.Reading], now: Date
    ) -> [ClaudeQuotaEstimator.Reading] {
        var result = existing
        for reading in new where !result.contains(where: { $0.kind == reading.kind && abs($0.at.timeIntervalSince(reading.at)) < 1 }) {
            result.append(reading)
        }
        let cutoff = now.addingTimeInterval(-retention)
        return Array(result.filter { $0.at >= cutoff }.sorted { $0.at < $1.at }.suffix(maximumCount))
    }

    /// The real endpoint readings already in the quota history, used once to seed an empty log.
    static func seed(from history: [LLMQuotaHistorySample]) -> [ClaudeQuotaEstimator.Reading] {
        history.filter { $0.claudeSource == "endpoint" }.flatMap { sample -> [ClaudeQuotaEstimator.Reading] in
            var readings: [ClaudeQuotaEstimator.Reading] = []
            if let left = sample.claudeFiveHourRemainingPercent {
                readings.append(.init(at: sample.sampledAt, kind: .fiveHour, usedPercent: Double(100 - left),
                                      resetAt: sample.claudeFiveHourResetAt, plan: sample.claudePlanType, source: "endpoint"))
            }
            if let left = sample.claudeWeeklyRemainingPercent {
                readings.append(.init(at: sample.sampledAt, kind: .weekly, usedPercent: Double(100 - left),
                                      resetAt: sample.claudeWeeklyResetAt, plan: sample.claudePlanType, source: "endpoint"))
            }
            return readings
        }
    }

    /// Records `new` and returns the whole log. Writes only when something was added.
    static func record(_ new: [ClaudeQuotaEstimator.Reading], now: Date, url: URL = url) -> [ClaudeQuotaEstimator.Reading] {
        lock.lock()
        defer { lock.unlock() }
        let decoder = JSONDecoder()
        var existing = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([ClaudeQuotaEstimator.Reading].self, from: $0) }
        if existing == nil {
            let historyURL = url.deletingLastPathComponent().appendingPathComponent("llm-quota-history.json")
            let history = (try? Data(contentsOf: historyURL)).flatMap { try? decoder.decode([LLMQuotaHistorySample].self, from: $0) } ?? []
            existing = merge([], adding: seed(from: history), now: now)
        }
        let before = existing ?? []
        let after = merge(before, adding: new, now: now)
        if after != before || !FileManager.default.fileExists(atPath: url.path),
           let data = try? JSONEncoder().encode(after) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return after
    }
}
