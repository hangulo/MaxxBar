import Foundation

/// Predicts how much of a Claude quota window will still be unused when it resets ("waste forecast").
///
/// Weekly windows use a habit profile: the week is cut into 28 slots (7 weekdays x 4 six-hour dayparts), and
/// each slot's usual burn rate is the median over every past occurrence of that slot with enough readings.
/// The rest of the current window is filled in slot by slot, and slots with no history use this window's
/// own average rate. 5 hour windows are too bursty for a profile, so they use the current window's rate.
/// Pure: no file or clock access, so it can be tested.
enum QuotaWasteForecast {
    static let slotsPerDay = 4
    static let slotLength: TimeInterval = 6 * 3_600
    static let week: TimeInterval = 7 * 86_400
    static let fiveHours: TimeInterval = 5 * 3_600
    /// A slot occurrence counts when readings cover at least this much of it.
    static let minimumSlotCoverage: TimeInterval = 2 * 3_600
    /// Readings further apart than this are not trusted to say when the usage happened.
    static let maximumGap: TimeInterval = 12 * 3_600
    /// "Finish at 90%": the share worth keeping in reserve for the last hours before a reset.
    static let targetLeftPercent = 10

    struct Point: Equatable {
        var at: Date
        var remaining: Int
        var resetAt: Date?
        var plan: String?
    }

    /// Usage is converted to Pro units so history from an older plan still describes habits on the current one.
    /// Max 5x is about 5 Pro allowances and Max 20x about 20; Anthropic does not publish exact weekly ratios.
    static func planScale(_ plan: String?) -> Double {
        switch ClaudePlanTimeline.normalized(plan) {
        case "Max 20x": return 20
        case "Max 5x": return 5
        default: return 1
        }
    }

    struct SlotKey: Hashable {
        var day: Date
        var daypart: Int
    }

    /// Usual burn per slot of the week, in Pro units per hour. Index = weekday (0 = Sunday) * 4 + daypart.
    struct Profile: Equatable {
        var unitsPerHour: [Int: Double]
        /// Distinct calendar weeks that contributed at least one slot.
        var weeks: Int

        var isEmpty: Bool { unitsPerHour.isEmpty }

        /// Average use per day across the slots that have history, in Pro units.
        var unitsPerDay: Double? {
            guard !unitsPerHour.isEmpty else { return nil }
            let mean = unitsPerHour.values.reduce(0, +) / Double(unitsPerHour.count)
            return mean * 24
        }
    }

    static func slotIndex(_ date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date) - 1
        let daypart = min(calendar.component(.hour, from: date) / 6, slotsPerDay - 1)
        return weekday * slotsPerDay + daypart
    }

    /// The end of the six-hour daypart that holds `date`, always later than `date`.
    /// Boundaries are wall-clock times (06:00, 12:00, 18:00, midnight), so a day with a DST change still splits at
    /// them. Adding hours to midnight would land at 05:00 on a fall-back day, before a 05:30 cursor, and the loops
    /// that walk slots would never advance.
    static func slotEnd(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let daypart = min(calendar.component(.hour, from: date) / 6, slotsPerDay - 1)
        let next = daypart + 1
        let end = next >= slotsPerDay
            ? calendar.date(byAdding: .day, value: 1, to: start)
            : calendar.date(bySettingHour: next * 6, minute: 0, second: 0, of: start)
        guard let end, end > date else { return date.addingTimeInterval(3_600) }
        return end
    }

    /// Builds the habit profile from a weekly series, oldest first.
    static func profile(from points: [Point], calendar: Calendar = .current) -> Profile {
        var used: [SlotKey: Double] = [:]
        var covered: [SlotKey: TimeInterval] = [:]
        let sorted = points.sorted { $0.at < $1.at }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let gap = b.at.timeIntervalSince(a.at)
            guard gap > 0, gap <= maximumGap,
                  ClaudePlanTimeline.normalized(a.plan) == ClaudePlanTimeline.normalized(b.plan),
                  b.remaining <= a.remaining else { continue }
            if let resetA = a.resetAt, let resetB = b.resetAt, abs(resetA.timeIntervalSince(resetB)) > 3_600 { continue }
            let units = Double(a.remaining - b.remaining) * planScale(a.plan)
            // Spread the drop evenly over the gap, split at daypart boundaries.
            var cursor = a.at
            while cursor < b.at {
                let end = min(slotEnd(after: cursor, calendar: calendar), b.at)
                let piece = end.timeIntervalSince(cursor)
                let daypart = min(calendar.component(.hour, from: cursor) / 6, slotsPerDay - 1)
                let key = SlotKey(day: calendar.startOfDay(for: cursor), daypart: daypart)
                covered[key, default: 0] += piece
                used[key, default: 0] += units * piece / gap
                cursor = end
            }
        }

        var rates: [Int: [Double]] = [:]
        var weeks = Set<Int>()
        for (key, seconds) in covered where seconds >= minimumSlotCoverage {
            let index = calendar.component(.weekday, from: key.day) - 1
            rates[index * slotsPerDay + key.daypart, default: []].append((used[key] ?? 0) / (seconds / 3_600))
            let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: key.day)
            weeks.insert((week.yearForWeekOfYear ?? 0) * 100 + (week.weekOfYear ?? 0))
        }
        return Profile(unitsPerHour: rates.mapValues(median), weeks: weeks.count)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// This window's own burn rate in Pro units per hour: readings with the same reset time and plan, back to the
    /// first rise. Nil when they span less than `minimumSpan`.
    static func currentWindowRate(_ points: [Point], current: Point, minimumSpan: TimeInterval) -> Double? {
        guard let resetAt = current.resetAt else { return nil }
        var start = current
        for point in points.sorted(by: { $0.at < $1.at }).reversed() where point.at < current.at {
            guard let reset = point.resetAt, abs(reset.timeIntervalSince(resetAt)) < 3_600,
                  ClaudePlanTimeline.normalized(point.plan) == ClaudePlanTimeline.normalized(current.plan),
                  point.remaining >= start.remaining else { break }
            start = point
        }
        let span = current.at.timeIntervalSince(start.at)
        guard span >= minimumSpan else { return nil }
        return Double(start.remaining - current.remaining) * planScale(current.plan) / (span / 3_600)
    }

    struct Forecast: Equatable {
        enum Method: Equatable {
            /// Habit profile, with this window's rate for slots that have no history.
            case habits
            /// Only this window's average rate (not enough history yet).
            case thisWindow
        }

        var resetAt: Date
        var remainingNow: Int
        /// Percent expected to be used between now and the reset.
        var expectedUse: Int
        /// Percent expected to expire unused at the reset.
        var predictedLeft: Int
        var method: Method
        /// Share of the time until reset that the habit profile covers, 0...1.
        var profileCoverage: Double
        var weeksOfHistory: Int
        /// Typical use per day on the current plan, in percent; nil without a profile.
        var typicalDayPercent: Double?

        /// Extra percent to spend before the reset to finish with only `targetLeftPercent` left.
        var spendToTarget: Int { max(predictedLeft - QuotaWasteForecast.targetLeftPercent, 0) }

        /// The predicted leftover expressed as days of usual use, when a profile exists.
        var leftoverInTypicalDays: Double? {
            guard let typicalDayPercent, typicalDayPercent > 0.5 else { return nil }
            return Double(predictedLeft) / typicalDayPercent
        }
    }

    /// Forecast for a weekly window. `history` is the series for that window, oldest first, without the current
    /// reading; `current` is the latest reading. Nil when the reset time is unknown or nothing predicts the rate.
    static func weekly(history: [Point], current: Point, now: Date, calendar: Calendar = .current) -> Forecast? {
        guard let resetAt = current.resetAt, resetAt > now else { return nil }
        let past = history.filter { $0.at < current.at }
        let habits = profile(from: past + [current], calendar: calendar)
        let fallback = currentWindowRate(past, current: current, minimumSpan: 6 * 3_600)
        guard !habits.isEmpty || fallback != nil else { return nil }

        var units = 0.0
        var profiled: TimeInterval = 0
        var cursor = now
        while cursor < resetAt {
            let end = min(slotEnd(after: cursor, calendar: calendar), resetAt)
            let hours = end.timeIntervalSince(cursor) / 3_600
            if let rate = habits.unitsPerHour[slotIndex(cursor, calendar: calendar)] {
                units += rate * hours
                profiled += end.timeIntervalSince(cursor)
            } else if let fallback {
                units += fallback * hours
            }
            cursor = end
        }
        let total = resetAt.timeIntervalSince(now)
        let coverage = total > 0 ? profiled / total : 0
        // With no fallback, uncovered slots count as idle; say so through low coverage instead of guessing.
        let scale = planScale(current.plan)
        let expected = min(Int((units / scale).rounded()), current.remaining)
        return Forecast(
            resetAt: resetAt,
            remainingNow: current.remaining,
            expectedUse: expected,
            predictedLeft: current.remaining - expected,
            method: habits.isEmpty ? .thisWindow : .habits,
            profileCoverage: coverage,
            weeksOfHistory: habits.weeks,
            typicalDayPercent: habits.unitsPerDay.map { $0 / scale }
        )
    }

    /// Forecast for the 5 hour window at the current window's own pace. Nil when the window is idle (nothing used
    /// yet), the reset time is unknown, or the window is too young to have a pace.
    static func fiveHour(history: [Point], current: Point, now: Date) -> Forecast? {
        guard let resetAt = current.resetAt, resetAt > now, current.remaining < 100 else { return nil }
        let past = history.filter { $0.at < current.at }
        guard let rate = currentWindowRate(past, current: current, minimumSpan: 10 * 60) else { return nil }
        let hours = resetAt.timeIntervalSince(now) / 3_600
        let expected = min(Int((rate * hours / planScale(current.plan)).rounded()), current.remaining)
        return Forecast(
            resetAt: resetAt, remainingNow: current.remaining, expectedUse: expected,
            predictedLeft: current.remaining - expected, method: .thisWindow,
            profileCoverage: 0, weeksOfHistory: 0, typicalDayPercent: nil
        )
    }

    /// Average left at the last `count` weekly resets in the ledger, to check the forecast against.
    static func recentWeeklyLeftAverage(_ records: [QuotaWindowRecord], kind: QuotaWindowRecord.Kind = .weekly,
                                        model: String? = nil, count: Int = 4) -> (average: Int, count: Int)? {
        let recent = records
            .filter { $0.kind == kind && $0.model == model }
            .sorted { $0.windowResetAt < $1.windowResetAt }
            .suffix(count)
        guard !recent.isEmpty else { return nil }
        let mean = Double(recent.reduce(0) { $0 + $1.leftPercent }) / Double(recent.count)
        return (Int(mean.rounded()), recent.count)
    }

    // MARK: Series from quota history

    static func weeklyPoints(_ history: [LLMQuotaHistorySample]) -> [Point] {
        history.compactMap { sample in
            sample.claudeWeeklyRemainingPercent.map {
                Point(at: sample.sampledAt, remaining: $0, resetAt: sample.claudeWeeklyResetAt, plan: plan(sample))
            }
        }
    }

    static func fiveHourPoints(_ history: [LLMQuotaHistorySample]) -> [Point] {
        history.compactMap { sample in
            sample.claudeFiveHourRemainingPercent.map {
                Point(at: sample.sampledAt, remaining: $0, resetAt: sample.claudeFiveHourResetAt, plan: plan(sample))
            }
        }
    }

    static func modelWeeklyPoints(_ history: [LLMQuotaHistorySample], model: String) -> [Point] {
        history.compactMap { sample in
            sample.claudeModelWeeklyRemaining?[model].map {
                Point(at: sample.sampledAt, remaining: $0, resetAt: sample.claudeModelWeeklyResetAt?[model], plan: plan(sample))
            }
        }
    }

    private static func plan(_ sample: LLMQuotaHistorySample) -> String {
        ClaudePlanTimeline.normalized(sample.claudePlanType) ?? ClaudePlanTimeline.entry(at: sample.sampledAt).plan
    }
}
