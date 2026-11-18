import Foundation

/// What local usage would have cost at API prices, kept per day in api-cost-ledger.json. The live scan only
/// reads the last 8 days of transcripts, so older days (for "this month") come from this ledger, which is
/// backfilled once from every transcript and then refreshed for the last 7 days on each scan.
struct APICostDay: Codable, Equatable {
    var costUSD: Double = 0
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var cacheWriteInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var requests = 0
}

struct APICostEvent {
    let at: Date
    let costUSD: Double
    let inputTokens: UInt64
    let cachedInputTokens: UInt64
    let cacheWriteInputTokens: UInt64
    let outputTokens: UInt64
}

struct APICostSummary: Equatable {
    var today: Double
    var thisWeek: Double
    var lastSevenDays: Double
    var thisMonth: Double
    /// Days of this month the ledger has a row for, so a partial backfill is visible.
    var monthDaysCovered: Int
    var pricingAsOf: String
}

enum APICostLedger {
    private struct File: Codable {
        var pricingAsOf: String
        var backfilled: [String: Bool] = [:]
        /// "yyyy-MM-dd" (local) -> provider -> totals.
        var days: [String: [String: APICostDay]] = [:]
    }

    private static let lock = NSLock()

    private static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/api-cost-ledger.json")
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `mark` names a backfill version, so a fixed backfill can run again over the same provider.
    static func isBackfilled(provider: String, mark: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return load()?.backfilled[mark ?? provider] == true
    }

    /// Replaces the stored totals for every day on or after `completeFrom` (days the events fully cover) and,
    /// for a backfill, every day the events touch. Older days the events do not cover are kept.
    static func record(_ events: [APICostEvent], provider: String, completeFrom: Date?, backfill: Bool = false, mark: String? = nil) {
        var totals: [String: APICostDay] = [:]
        for event in events {
            var day = totals[dayKey(event.at), default: APICostDay()]
            day.costUSD += event.costUSD
            day.inputTokens += event.inputTokens
            day.cachedInputTokens += event.cachedInputTokens
            day.cacheWriteInputTokens += event.cacheWriteInputTokens
            day.outputTokens += event.outputTokens
            day.requests += 1
            totals[dayKey(event.at)] = day
        }
        let firstComplete = completeFrom.map { dayKey($0) }
        lock.lock()
        defer { lock.unlock() }
        var file = load() ?? File(pricingAsOf: LLMTokenPricing.asOf)
        for (key, var providers) in file.days where firstComplete.map({ key >= $0 }) ?? false {
            providers[provider] = nil
            file.days[key] = providers.isEmpty ? nil : providers
        }
        for (key, day) in totals where backfill || firstComplete.map({ key >= $0 }) ?? false {
            file.days[key, default: [:]][provider] = day
        }
        if backfill { file.backfilled[mark ?? provider] = true }
        file.pricingAsOf = LLMTokenPricing.asOf
        save(file)
    }

    static func summary(provider: String, now: Date = Date(), calendar: Calendar = .current) -> APICostSummary? {
        lock.lock()
        let file = load()
        lock.unlock()
        guard let file else { return nil }
        func total(from start: Date) -> Double {
            let first = dayKey(start, calendar: calendar)
            let last = dayKey(now, calendar: calendar)
            return file.days.filter { $0.key >= first && $0.key <= last }
                .compactMap { $0.value[provider]?.costUSD }
                .reduce(0, +)
        }
        let startOfDay = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfDay
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfDay
        let monthFirst = dayKey(monthStart, calendar: calendar)
        let monthDays = file.days.filter { $0.key >= monthFirst && $0.value[provider] != nil }.count
        return APICostSummary(
            today: total(from: startOfDay),
            thisWeek: total(from: weekStart),
            lastSevenDays: total(from: calendar.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay),
            thisMonth: total(from: monthStart),
            monthDaysCovered: monthDays,
            pricingAsOf: file.pricingAsOf
        )
    }

    /// Monthly subscription price for a plan name, for the comparison line. Nil when unknown.
    static func monthlyPlanPrice(_ plan: String?) -> Double? {
        guard let plan = plan?.lowercased() else { return nil }
        if plan.contains("20x") { return 200 }
        if plan.contains("5x") { return 100 }
        if plan.contains("max") { return 100 }
        if plan.contains("pro") { return 20 }
        return nil
    }

    private static func load() -> File? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) }
    }

    private static func save(_ file: File) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
