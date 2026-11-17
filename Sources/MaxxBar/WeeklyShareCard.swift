import Foundation

/// Figures for the weekly "credits rescued" share card. Built from the window ledger and the API cost ledger.
/// It deliberately holds nothing that identifies the person or the machine: no names, paths, projects or accounts.
struct WeeklyShareSummary: Equatable {
    struct Day: Equatable {
        var date: Date
        var turns: Int
        var tokens: UInt64
        var apiValueUSD: Double
    }

    /// Start of the 7 calendar days the activity figures cover.
    var periodStart: Date
    /// The weekly reset that closed the week, or the upcoming reset for a week still in progress.
    var resetAt: Date
    var inProgress: Bool
    var usedPercent: Int
    var leftPercent: Int
    var plan: String?
    /// Average share left at reset over the previous closed weeks on the same plan.
    var baselineLeftPercent: Int?
    var baselineWeeks: Int
    /// Points of the plan that did not expire compared with the baseline. Nil unless the week beat it.
    var rescuedPoints: Int?
    /// The last reading came long before the reset, so the true figure may be higher than shown.
    var lowConfidence: Bool
    var lastReadingMinutesBeforeReset: Int?
    var days: [Day]

    var turns: Int { days.reduce(0) { $0 + $1.turns } }
    var tokens: UInt64 { days.reduce(0) { $0 + $1.tokens } }
    var apiValueUSD: Double { days.reduce(0) { $0 + $1.apiValueUSD } }
    var activeDays: Int { days.filter { $0.turns > 0 }.count }
}

enum WeeklyShareCard {
    static let baselineWeekCount = 4
    static let week: TimeInterval = 7 * 86_400

    enum Period: String, CaseIterable {
        case lastFullWeek, thisWeekSoFar
    }

    /// The live weekly Claude reading, for a week still in progress.
    struct LiveWeek: Equatable {
        var usedPercent: Int
        var resetAt: Date
    }

    /// Picks the week and fills the card. `period` is a preference: with no closed week yet it falls back to the
    /// live week, and with no live reading it falls back to the last closed week. Nil when neither exists.
    static func summary(
        records: [QuotaWindowRecord],
        live: LiveWeek?,
        plan: String?,
        period: Period,
        now: Date = Date(),
        calendar: Calendar = .current,
        loadDays: (Date, Date) -> [String: APICostDay]
    ) -> WeeklyShareSummary? {
        let weekly = records.filter { $0.kind == .weekly && $0.windowResetAt <= now }
            .sorted { $0.windowResetAt < $1.windowResetAt }
        let closed = weekly.last
        let useLive = live != nil && (period == .thisWeekSoFar || closed == nil)

        let resetAt: Date
        let used: Int
        let currentPlan: String?
        var lowConfidence = false
        var minutesBefore: Int?
        if useLive, let live {
            resetAt = live.resetAt
            used = live.usedPercent
            currentPlan = ClaudePlanTimeline.normalized(plan) ?? ClaudePlanTimeline.entry(at: now).plan
        } else if let closed {
            resetAt = closed.windowResetAt
            used = closed.lastUsedPercent
            currentPlan = ClaudePlanTimeline.normalized(closed.plan) ?? ClaudePlanTimeline.entry(at: resetAt).plan
            lowConfidence = closed.lowConfidence
            minutesBefore = closed.sampleAgeAtResetSeconds / 60
        } else {
            return nil
        }

        // Earlier closed weeks on the same plan; a plan change resizes the allowance, so older weeks do not compare.
        // Low confidence weeks are left out too: a reading taken days before the reset overstates what expired.
        let earlier = weekly.filter {
            $0.windowResetAt < resetAt.addingTimeInterval(-86_400) && !$0.lowConfidence
                && (ClaudePlanTimeline.normalized($0.plan) ?? ClaudePlanTimeline.entry(at: $0.windowResetAt).plan) == currentPlan
        }.suffix(baselineWeekCount)
        let baseline = earlier.isEmpty ? nil
            : Int((Double(earlier.reduce(0) { $0 + $1.leftPercent }) / Double(earlier.count)).rounded())
        let left = max(0, 100 - used)
        let rescued = useLive ? nil : baseline.flatMap { $0 - left > 0 ? $0 - left : nil }

        // Activity covers the 7 calendar days ending on the reset day (or today, for a week in progress).
        let lastDay = calendar.startOfDay(for: useLive ? min(now, resetAt) : resetAt)
        let firstDay = calendar.date(byAdding: .day, value: -6, to: lastDay) ?? lastDay
        let totals = loadDays(firstDay, lastDay)
        let days = (0..<7).compactMap { offset -> WeeklyShareSummary.Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            let day = totals[APICostLedger.dayKey(date, calendar: calendar)] ?? APICostDay()
            return WeeklyShareSummary.Day(
                date: date, turns: day.requests, tokens: day.inputTokens + day.outputTokens, apiValueUSD: day.costUSD
            )
        }

        return WeeklyShareSummary(
            periodStart: firstDay, resetAt: resetAt, inProgress: useLive,
            usedPercent: min(max(used, 0), 100), leftPercent: left, plan: currentPlan,
            baselineLeftPercent: baseline, baselineWeeks: earlier.count, rescuedPoints: rescued,
            lowConfidence: lowConfidence, lastReadingMinutesBeforeReset: minutesBefore, days: days
        )
    }

    /// Made up figures for screenshots and the demo render.
    static func demo(now: Date = Date(), calendar: Calendar = .current) -> WeeklyShareSummary {
        let lastDay = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -6, to: lastDay) ?? lastDay
        let turns = [212, 348, 0, 405, 290, 176, 133]
        let days = turns.enumerated().map { index, count in
            WeeklyShareSummary.Day(
                date: calendar.date(byAdding: .day, value: index, to: firstDay) ?? firstDay,
                turns: count, tokens: UInt64(count) * 61_000, apiValueUSD: Double(count) * 0.21
            )
        }
        return WeeklyShareSummary(
            periodStart: firstDay, resetAt: now, inProgress: false, usedPercent: 82, leftPercent: 18,
            plan: "Max 5x", baselineLeftPercent: 41, baselineWeeks: 4, rescuedPoints: 23,
            lowConfidence: false, lastReadingMinutesBeforeReset: 6, days: days
        )
    }
}
