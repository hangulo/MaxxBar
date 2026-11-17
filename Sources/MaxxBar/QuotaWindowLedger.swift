import Foundation

/// The Claude plans Hector has been on, oldest first. The ledger uses it to tell a plan change from a window
/// reset in rows that predate `claudePlanType`, and the usage report uses it for plan cost per day.
enum ClaudePlanTimeline {
    struct Entry: Codable, Equatable {
        let plan: String
        let monthlyUSD: Double
        let from: Date
    }

    static let entries: [Entry] = [
        Entry(plan: "Pro", monthlyUSD: 20, from: .distantPast),
        // 12 Nov 2026 07:41 Pacific: Pro to Max 5x.
        Entry(plan: "Max 5x", monthlyUSD: 100, from: Date(timeIntervalSinceReferenceDate: 816_190_860))
    ]

    static func entry(at date: Date) -> Entry {
        entries.last { $0.from <= date } ?? entries[0]
    }

    /// One name per plan, so "max_5x", "Max 5x" and the timeline agree.
    static func normalized(_ plan: String?) -> String? {
        guard let value = plan?.lowercased(), !value.isEmpty else { return nil }
        if value.contains("20x") { return "Max 20x" }
        if value.contains("max") || value.contains("5x") { return "Max 5x" }
        if value.contains("pro") { return "Pro" }
        return plan
    }
}

/// What was left in one Claude quota window when it closed.
struct QuotaWindowRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case fiveHour, weekly, weeklyModel
    }

    var kind: Kind
    /// The model for a per-model weekly window, for example "Fable".
    var model: String?
    var windowResetAt: Date
    /// True when the reset time was not reported and was inferred from the weekly reset schedule or a jump.
    var resetInferred: Bool = false
    var lastUsedPercent: Int
    var leftPercent: Int
    var lastSampleAt: Date
    var sampleAgeAtResetSeconds: Int
    /// The last reading came more than 30 minutes before the reset, so usage after it is missing.
    var lowConfidence: Bool
    var weeklyAllUsedPercentAtClose: Int?
    var plan: String?
    var source: String?
    var backfilled: Bool

    func isSameWindow(as other: QuotaWindowRecord) -> Bool {
        kind == other.kind && model == other.model
            && abs(windowResetAt.timeIntervalSince(other.windowResetAt)) < QuotaWindowLedger.sameResetTolerance
    }
}

/// Finds closed windows in the quota history. Pure: the store below reads and writes the file.
enum QuotaWindowLedger {
    static let lowConfidenceAge: TimeInterval = 30 * 60
    static let sameResetTolerance: TimeInterval = 30 * 60
    /// A reset time that moves later by more than this means a new window started early.
    static let resetJumpThreshold: TimeInterval = 3_600
    /// Without reset times, a rise in remaining percent this large (and no plan change) is a weekly reset.
    static let inferredRiseThreshold = 5
    static let week: TimeInterval = 7 * 86_400

    struct Point {
        var at: Date
        var remaining: Int
        var resetAt: Date?
        var plan: String
        var source: String?
        var weeklyAllUsed: Int?
    }

    /// Every closed window in `history`, oldest first, deduplicated. Records are marked `backfilled` as asked.
    static func closedWindows(in history: [LLMQuotaHistorySample], now: Date, backfilled: Bool = false) -> [QuotaWindowRecord] {
        let samples = history.sorted { $0.sampledAt < $1.sampledAt }
        func plan(_ sample: LLMQuotaHistorySample) -> String {
            ClaudePlanTimeline.normalized(sample.claudePlanType) ?? ClaudePlanTimeline.entry(at: sample.sampledAt).plan
        }
        func point(_ sample: LLMQuotaHistorySample, remaining: Int, resetAt: Date?) -> Point {
            Point(
                at: sample.sampledAt, remaining: remaining, resetAt: resetAt, plan: plan(sample),
                source: sample.claudeSource, weeklyAllUsed: sample.claudeWeeklyRemainingPercent.map { 100 - $0 }
            )
        }

        let fiveHour = samples.compactMap { sample in
            sample.claudeFiveHourRemainingPercent.map { point(sample, remaining: $0, resetAt: sample.claudeFiveHourResetAt) }
        }
        let weekly = samples.compactMap { sample in
            sample.claudeWeeklyRemainingPercent.map { point(sample, remaining: $0, resetAt: sample.claudeWeeklyResetAt) }
        }
        // Weekly resets fall on a fixed weekly schedule; the first reported reset time anchors older rows.
        let anchor = samples.lazy.compactMap(\.claudeWeeklyResetAt).first

        var records = closes(fiveHour, kind: .fiveHour, model: nil, now: now, weeklyAnchor: nil)
        records += closes(weekly, kind: .weekly, model: nil, now: now, weeklyAnchor: anchor)
        let models = Set(samples.flatMap { ($0.claudeModelWeeklyRemaining ?? [:]).keys }).sorted()
        for model in models {
            let series = samples.compactMap { sample in
                sample.claudeModelWeeklyRemaining?[model].map {
                    point(sample, remaining: $0, resetAt: sample.claudeModelWeeklyResetAt?[model])
                }
            }
            records += closes(series, kind: .weeklyModel, model: model, now: now, weeklyAnchor: nil)
        }
        return deduplicated(records.map { var record = $0; record.backfilled = backfilled; return record })
            .sorted { $0.windowResetAt < $1.windowResetAt }
    }

    static func closes(_ points: [Point], kind: QuotaWindowRecord.Kind, model: String?, now: Date, weeklyAnchor: Date?) -> [QuotaWindowRecord] {
        guard var current = points.first else { return [] }
        var currentReset = current.resetAt
        var records: [QuotaWindowRecord] = []

        func close(at reset: Date, inferred: Bool) {
            // An unused 5 hour window never started, so nothing expired.
            guard !(kind == .fiveHour && current.remaining >= 100) else { return }
            let age = reset.timeIntervalSince(current.at)
            records.append(QuotaWindowRecord(
                kind: kind, model: model, windowResetAt: reset, resetInferred: inferred,
                lastUsedPercent: 100 - current.remaining, leftPercent: current.remaining,
                lastSampleAt: current.at, sampleAgeAtResetSeconds: Int(max(age, 0)),
                lowConfidence: age > lowConfidenceAge,
                weeklyAllUsedPercentAtClose: current.weeklyAllUsed,
                plan: current.plan, source: current.source, backfilled: false
            ))
        }

        func scheduledReset(after start: Date, through end: Date) -> Date? {
            guard let weeklyAnchor else { return nil }
            let steps = (start.timeIntervalSince(weeklyAnchor) / week).rounded(.down) + 1
            let candidate = weeklyAnchor.addingTimeInterval(steps * week)
            return candidate <= end ? candidate : nil
        }

        for next in points.dropFirst() {
            if next.plan != current.plan {
                // A new plan changes the allowance; the jump is not a reset.
                current = next
                currentReset = next.resetAt
                continue
            }
            var closedAt: (Date, Bool)?
            if let reset = currentReset {
                if next.at >= reset {
                    closedAt = (reset, false)
                } else if let nextReset = next.resetAt, nextReset.timeIntervalSince(reset) > resetJumpThreshold {
                    closedAt = (reset, false)
                }
            } else if kind != .fiveHour {
                if let scheduled = scheduledReset(after: current.at, through: next.at) {
                    closedAt = (scheduled, true)
                } else if weeklyAnchor == nil, next.remaining >= current.remaining + inferredRiseThreshold {
                    closedAt = (next.at, true)
                }
            }
            if let (reset, inferred) = closedAt {
                close(at: reset, inferred: inferred)
                currentReset = next.resetAt
            } else {
                currentReset = next.resetAt ?? currentReset
            }
            current = next
        }

        // The last window may have closed while nothing was sampled (asleep, or quit).
        if let reset = currentReset, now >= reset {
            close(at: reset, inferred: false)
        } else if currentReset == nil, kind != .fiveHour, let scheduled = scheduledReset(after: current.at, through: now) {
            close(at: scheduled, inferred: true)
        }
        return records
    }

    static func deduplicated(_ records: [QuotaWindowRecord]) -> [QuotaWindowRecord] {
        var kept: [QuotaWindowRecord] = []
        for record in records where !kept.contains(where: { $0.isSameWindow(as: record) }) {
            kept.append(record)
        }
        return kept
    }

    /// Records in `found` that `existing` does not already hold.
    static func newRecords(_ found: [QuotaWindowRecord], existing: [QuotaWindowRecord]) -> [QuotaWindowRecord] {
        found.filter { record in !existing.contains { $0.isSameWindow(as: record) } }
    }

    /// The next reset worth a fresh reading just before it, from the latest sample.
    static func nextReset(in history: [LLMQuotaHistorySample], after now: Date) -> Date? {
        guard let last = history.max(by: { $0.sampledAt < $1.sampledAt }) else { return nil }
        let resets = [last.claudeFiveHourResetAt, last.claudeWeeklyResetAt].compactMap { $0 }
            + (last.claudeModelWeeklyResetAt ?? [:]).values
        return resets.filter { $0 > now }.min()
    }
}

/// Figures for the "Left at reset" card.
struct QuotaLeftAtReset: Equatable {
    var lastFiveHour: QuotaWindowRecord?
    var fiveHourAverageToday: Double?
    var fiveHourCountToday = 0
    var fiveHourAverageWeek: Double?
    var fiveHourCountWeek = 0
    var lastWeekly: QuotaWindowRecord?
    var lastModelWeekly: [String: QuotaWindowRecord] = [:]

    init(records: [QuotaWindowRecord], now: Date = Date(), calendar: Calendar = .current) {
        let sorted = records.sorted { $0.windowResetAt < $1.windowResetAt }
        let fiveHour = sorted.filter { $0.kind == .fiveHour }
        lastFiveHour = fiveHour.last
        let startOfDay = calendar.startOfDay(for: now)
        let today = fiveHour.filter { $0.windowResetAt >= startOfDay && $0.windowResetAt <= now }
        let week = fiveHour.filter { now.timeIntervalSince($0.windowResetAt) <= QuotaWindowLedger.week && $0.windowResetAt <= now }
        fiveHourCountToday = today.count
        fiveHourCountWeek = week.count
        fiveHourAverageToday = today.isEmpty ? nil : Double(today.reduce(0) { $0 + $1.leftPercent }) / Double(today.count)
        fiveHourAverageWeek = week.isEmpty ? nil : Double(week.reduce(0) { $0 + $1.leftPercent }) / Double(week.count)
        lastWeekly = sorted.last { $0.kind == .weekly }
        for record in sorted where record.kind == .weeklyModel {
            if let model = record.model { lastModelWeekly[model] = record }
        }
    }
}

/// llm-window-ledger.jsonl: one closed window per line, append only, never trimmed.
enum QuotaWindowLedgerStore {
    private static let queue = DispatchQueue(label: "com.hector.MaxxBar.window-ledger", qos: .utility)

    static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/llm-window-ledger.jsonl")
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Every record on disk; a line that does not decode is skipped.
    static func load(from url: URL = url) -> [QuotaWindowRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(QuotaWindowRecord.self, from: Data($0.utf8)) }
    }

    /// Appends windows that closed since the last call. The first run, with no file yet, backfills from history.
    static func update(history: [LLMQuotaHistorySample], now: Date = Date(), completion: @escaping @Sendable ([QuotaWindowRecord]) -> Void) {
        queue.async {
            completion(appendClosedWindows(history: history, now: now, to: url))
        }
    }

    @discardableResult
    static func appendClosedWindows(history: [LLMQuotaHistorySample], now: Date, to url: URL) -> [QuotaWindowRecord] {
        let isFirstRun = !FileManager.default.fileExists(atPath: url.path)
        let existing = load(from: url)
        let found = QuotaWindowLedger.closedWindows(in: history, now: now, backfilled: isFirstRun)
        let added = QuotaWindowLedger.newRecords(found, existing: existing)
        guard isFirstRun || !added.isEmpty else { return existing }
        var data = Data()
        for record in added {
            guard let line = try? encoder.encode(record) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if isFirstRun {
            try? data.write(to: url, options: .atomic)
        } else if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
        return existing + added
    }
}
