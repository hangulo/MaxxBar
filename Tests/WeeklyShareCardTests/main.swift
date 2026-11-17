import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let t0 = Date(timeIntervalSinceReferenceDate: 817_000_000) // after the Max 5x change
func days(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

func weekly(_ resetDays: Double, left: Int, plan: String = "Max 5x", lowConfidence: Bool = false) -> QuotaWindowRecord {
    QuotaWindowRecord(
        kind: .weekly, model: nil, windowResetAt: days(resetDays), lastUsedPercent: 100 - left, leftPercent: left,
        lastSampleAt: days(resetDays).addingTimeInterval(-600), sampleAgeAtResetSeconds: lowConfidence ? 5_400 : 600,
        lowConfidence: lowConfidence, weeklyAllUsedPercentAtClose: nil, plan: plan, source: "endpoint", backfilled: false
    )
}

var requested: (Date, Date)?
let ledger: (Date, Date) -> [String: APICostDay] = { start, end in
    requested = (start, end)
    var result: [String: APICostDay] = [:]
    var day = start
    var turns = 10
    while day <= end {
        result[APICostLedger.dayKey(day, calendar: calendar)] = APICostDay(costUSD: 1.5, inputTokens: 900, outputTokens: 100, requests: turns)
        turns += 10
        day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return result
}

// Last full week beats the 4 week baseline: rescued = baseline left minus this week's left.
var records = [weekly(-35, left: 90), weekly(-28, left: 50), weekly(-21, left: 40), weekly(-14, left: 30), weekly(-7, left: 40), weekly(0, left: 15)]
var five = weekly(0.1, left: 3); five.kind = .fiveHour
records.append(five)
var summary = WeeklyShareCard.summary(records: records, live: nil, plan: nil, period: .lastFullWeek, now: days(1), calendar: calendar, loadDays: ledger)!
assert(!summary.inProgress && summary.usedPercent == 85 && summary.leftPercent == 15)
assert(summary.baselineWeeks == 4 && summary.baselineLeftPercent == 40, "\(summary)")
assert(summary.rescuedPoints == 25)
assert(summary.resetAt == days(0))
assert(summary.days.count == 7 && summary.turns == 280 && summary.activeDays == 7 && summary.tokens == 7_000)
assert(abs(summary.apiValueUSD - 10.5) < 0.001)
assert(calendar.startOfDay(for: days(0)) == requested!.1, "activity ends on the reset day")

// A week that left more than usual has no rescued figure, but keeps the baseline.
records = [weekly(-14, left: 20), weekly(-7, left: 20), weekly(0, left: 35)]
summary = WeeklyShareCard.summary(records: records, live: nil, plan: nil, period: .lastFullWeek, now: days(1), calendar: calendar, loadDays: ledger)!
assert(summary.rescuedPoints == nil && summary.baselineLeftPercent == 20)

// Weeks on another plan do not count toward the baseline.
records = [weekly(-14, left: 60, plan: "Pro"), weekly(-7, left: 70, plan: "Pro"), weekly(0, left: 30)]
summary = WeeklyShareCard.summary(records: records, live: nil, plan: nil, period: .lastFullWeek, now: days(1), calendar: calendar, loadDays: ledger)!
assert(summary.baselineLeftPercent == nil && summary.baselineWeeks == 0 && summary.rescuedPoints == nil)

// Low confidence carries through with the reading age.
summary = WeeklyShareCard.summary(records: [weekly(0, left: 30, lowConfidence: true)], live: nil, plan: nil, period: .lastFullWeek, now: days(1), calendar: calendar, loadDays: ledger)!
assert(summary.lowConfidence && summary.lastReadingMinutesBeforeReset == 90)

// So far: uses the live week, never claims a rescue, and activity ends today.
let live = WeeklyShareCard.LiveWeek(usedPercent: 44, resetAt: days(5))
summary = WeeklyShareCard.summary(records: [weekly(-7, left: 50), weekly(-2, left: 10)], live: live, plan: "max_5x", period: .thisWeekSoFar, now: days(1), calendar: calendar, loadDays: ledger)!
assert(summary.inProgress && summary.usedPercent == 44 && summary.leftPercent == 56 && summary.rescuedPoints == nil)
assert(summary.plan == "Max 5x" && summary.baselineLeftPercent == 30)
assert(calendar.startOfDay(for: days(1)) == requested!.1)

// Falls back to the live week with no closed week, and to nil with nothing at all.
summary = WeeklyShareCard.summary(records: [], live: live, plan: nil, period: .lastFullWeek, now: days(1), calendar: calendar, loadDays: ledger)!
assert(summary.inProgress)
assert(WeeklyShareCard.summary(records: [], live: nil, plan: nil, period: .thisWeekSoFar, now: days(1), calendar: calendar, loadDays: ledger) == nil)

// A weekly reset still in the future is not a closed week.
summary = WeeklyShareCard.summary(records: [weekly(3, left: 10)], live: live, plan: nil, period: .lastFullWeek, now: days(1), calendar: calendar, loadDays: ledger)!
assert(summary.inProgress)

print("weekly share card tests passed")
