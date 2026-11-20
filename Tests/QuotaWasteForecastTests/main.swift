import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
calendar.firstWeekday = 1
// Sunday 4 Jan 1970 00:00 UTC; weekly resets fall on Sundays at midnight.
let sunday = Date(timeIntervalSince1970: 3 * 86_400)
let hour: TimeInterval = 3_600
let week = QuotaWasteForecast.week
func t(_ weeks: Int, _ hours: Double) -> Date { sunday.addingTimeInterval(Double(weeks) * week + hours * hour) }
typealias Point = QuotaWasteForecast.Point

/// Hourly readings for one past week: 1% (Max 5x) or `rate` per hour used on Monday 12:00 to 18:00, idle otherwise.
func habitWeek(_ index: Int, plan: String = "Max 5x", rate: Int = 1) -> [Point] {
    var left = 100
    return (0..<168).map { h in
        if h > 36 && h <= 42 { left -= rate } // Monday is hours 24 to 47
        return Point(at: t(index, Double(h)), remaining: left, resetAt: t(index + 1, 0), plan: plan)
    }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }

// Habit profile: two past weeks with a Monday afternoon burst; forecast from Monday 08:00 of week 2.
var history = habitWeek(0) + habitWeek(1)
history += (0...32).map { Point(at: t(2, Double($0)), remaining: 100, resetAt: t(3, 0), plan: "Max 5x") }
var current = history.removeLast()
let profile = QuotaWasteForecast.profile(from: history + [current], calendar: calendar)
assert(profile.weeks == 3, "\(profile.weeks)")
assert(near(profile.unitsPerHour[1 * 4 + 2] ?? -1, 5), "\(profile.unitsPerHour)") // Monday 12-18: 1% of Max 5x per hour
assert(profile.unitsPerHour[1 * 4 + 1] == 0)
var forecast = QuotaWasteForecast.weekly(history: history, current: current, now: current.at, calendar: calendar)!
assert(forecast.method == .habits)
assert(forecast.expectedUse == 6 && forecast.predictedLeft == 94, "\(forecast)")
assert(near(forecast.profileCoverage, 1), "\(forecast.profileCoverage)")
assert(forecast.spendToTarget == 84)
assert(near(forecast.typicalDayPercent ?? 0, 24.0 / 28, 0.001), "\(String(describing: forecast.typicalDayPercent))")

// Past the burst, nothing more is expected this week.
let afterBurst = Point(at: t(2, 50), remaining: 100, resetAt: t(3, 0), plan: "Max 5x")
forecast = QuotaWasteForecast.weekly(history: history, current: afterBurst, now: afterBurst.at, calendar: calendar)!
assert(forecast.expectedUse == 0 && forecast.predictedLeft == 100)

// History from an older plan is rescaled: 5% of Pro per hour is 1% of Max 5x.
history = habitWeek(0, plan: "Pro", rate: 5) + habitWeek(1, plan: "Pro", rate: 5)
forecast = QuotaWasteForecast.weekly(history: history, current: current, now: current.at, calendar: calendar)!
assert(forecast.expectedUse == 6, "\(forecast)")

// No usable profile (readings 16 hours apart): this week's own pace, 0.25% per hour, for the 136 hours left.
history = [
    Point(at: t(0, 0), remaining: 100, resetAt: t(1, 0), plan: "Max 5x"),
    Point(at: t(0, 16), remaining: 96, resetAt: t(1, 0), plan: "Max 5x")
]
current = Point(at: t(0, 32), remaining: 92, resetAt: t(1, 0), plan: "Max 5x")
forecast = QuotaWasteForecast.weekly(history: history, current: current, now: current.at, calendar: calendar)!
assert(forecast.method == .thisWindow && forecast.weeksOfHistory == 0)
assert(forecast.expectedUse == 34 && forecast.predictedLeft == 58, "\(forecast)")
assert(forecast.typicalDayPercent == nil && forecast.leftoverInTypicalDays == nil)

// A fast pace runs out before the reset: nothing expires.
current = Point(at: t(0, 32), remaining: 40, resetAt: t(1, 0), plan: "Max 5x")
forecast = QuotaWasteForecast.weekly(history: history, current: current, now: current.at, calendar: calendar)!
assert(forecast.predictedLeft == 0 && forecast.expectedUse == 40 && forecast.spendToTarget == 0)

// A previous window's readings do not set this window's pace.
history = [Point(at: t(0, 100), remaining: 10, resetAt: t(1, 0), plan: "Max 5x")]
current = Point(at: t(1, 1), remaining: 99, resetAt: t(2, 0), plan: "Max 5x")
assert(QuotaWasteForecast.weekly(history: history, current: current, now: current.at, calendar: calendar) == nil)

// Unknown or past reset time: no forecast.
assert(QuotaWasteForecast.weekly(history: [], current: Point(at: t(0, 1), remaining: 50, resetAt: nil, plan: nil), now: t(0, 1)) == nil)
assert(QuotaWasteForecast.weekly(history: [], current: Point(at: t(0, 1), remaining: 50, resetAt: t(0, 0), plan: nil), now: t(0, 1)) == nil)

// 5 hour window: 20% used in 2 hours, 3 hours to go, so 30% more and 50% left in the window.
let fiveReset = t(0, 5)
history = [Point(at: t(0, 0), remaining: 100, resetAt: fiveReset, plan: "Max 5x"), Point(at: t(0, 1), remaining: 92, resetAt: fiveReset, plan: "Max 5x")]
current = Point(at: t(0, 2), remaining: 80, resetAt: fiveReset, plan: "Max 5x")
forecast = QuotaWasteForecast.fiveHour(history: history, current: current, now: current.at)!
assert(forecast.expectedUse == 30 && forecast.predictedLeft == 50, "\(forecast)")
// Idle window, or one too young to have a pace: nothing to say.
assert(QuotaWasteForecast.fiveHour(history: history, current: Point(at: t(0, 2), remaining: 100, resetAt: fiveReset, plan: nil), now: t(0, 2)) == nil)
assert(QuotaWasteForecast.fiveHour(history: [], current: current, now: current.at) == nil)

// Recent weekly leftovers from the ledger.
func record(_ kind: QuotaWindowRecord.Kind, _ left: Int, _ weeks: Int, model: String? = nil) -> QuotaWindowRecord {
    QuotaWindowRecord(
        kind: kind, model: model, windowResetAt: t(weeks, 0), lastUsedPercent: 100 - left, leftPercent: left,
        lastSampleAt: t(weeks, 0), sampleAgeAtResetSeconds: 0, lowConfidence: false, backfilled: false
    )
}
let ledger = [record(.weekly, 0, 1), record(.weekly, 30, 2), record(.weekly, 10, 3), record(.weekly, 20, 4), record(.weekly, 40, 5),
              record(.fiveHour, 90, 5), record(.weeklyModel, 60, 5, model: "Fable")]
let recent = QuotaWasteForecast.recentWeeklyLeftAverage(ledger)!
assert(recent.average == 25 && recent.count == 4, "\(recent)")
assert(QuotaWasteForecast.recentWeeklyLeftAverage(ledger, kind: .weeklyModel, model: "Fable")!.average == 60)
assert(QuotaWasteForecast.recentWeeklyLeftAverage([]) == nil)

// Plan scale.
assert(QuotaWasteForecast.planScale("max_5x") == 5 && QuotaWasteForecast.planScale("Pro") == 1 && QuotaWasteForecast.planScale(nil) == 1)

// DST: on a fall-back day (1 Nov 2026 in Los Angeles) dayparts still end at 06:00 wall time, and walking slots
// across the change ends instead of looping forever on 05:00.
var pacific = Calendar(identifier: .gregorian)
pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let fallBack = pacific.date(from: DateComponents(year: 2026, month: 11, day: 1))!
let fiveThirty = fallBack.addingTimeInterval(6.5 * hour) // 05:30 PST, 6.5 hours after midnight PDT
let sixAM = QuotaWasteForecast.slotEnd(after: fiveThirty, calendar: pacific)
assert(sixAM == fallBack.addingTimeInterval(7 * hour), "\(sixAM)")
for minutes in stride(from: 0, to: 48 * 60, by: 15) {
    let date = fallBack.addingTimeInterval(Double(minutes) * 60 - 12 * hour)
    assert(QuotaWasteForecast.slotEnd(after: date, calendar: pacific) > date, "\(date)")
}
let dstHistory = (0..<48).map { h in
    Point(at: fallBack.addingTimeInterval(Double(h - 12) * hour), remaining: 100 - h / 4, resetAt: fallBack.addingTimeInterval(4 * 86_400), plan: "Max 5x")
}
let dstProfile = QuotaWasteForecast.profile(from: dstHistory, calendar: pacific)
assert(!dstProfile.isEmpty)
let dstNow = dstHistory.last!
assert(QuotaWasteForecast.weekly(history: Array(dstHistory.dropLast()), current: dstNow, now: dstNow.at, calendar: pacific) != nil)

// Weekly empty time for the menu bar. Two past weeks burn 1% per hour on Monday 12:00 to 18:00 and idle otherwise.
// With 4% left on Monday 08:00, the burst empties it 4 hours in, at 16:00, even though the last hours were idle.
var emptyHistory = habitWeek(0) + habitWeek(1)
emptyHistory += (0...31).map { Point(at: t(2, Double($0)), remaining: 4, resetAt: t(3, 0), plan: "Max 5x") }
var emptyCurrent = Point(at: t(2, 32), remaining: 4, resetAt: t(3, 0), plan: "Max 5x")
var emptyAt = QuotaWasteForecast.weeklyEmptyAt(history: emptyHistory, current: emptyCurrent, now: emptyCurrent.at, calendar: calendar)
assert(emptyAt.map { near($0.timeIntervalSince(t(2, 40)), 0, 1) } == true, "\(String(describing: emptyAt))")
// 10% outlasts the usual 6% burst: no warning.
emptyCurrent.remaining = 10
assert(QuotaWasteForecast.weeklyEmptyAt(history: emptyHistory, current: emptyCurrent, now: emptyCurrent.at, calendar: calendar) == nil)
// Less than a day into the week: no warning yet, however fast the start.
let freshWeek = Point(at: t(2, 20), remaining: 4, resetAt: t(3, 0), plan: "Max 5x")
assert(QuotaWasteForecast.weeklyEmptyAt(history: emptyHistory, current: freshWeek, now: freshWeek.at, calendar: calendar) == nil)
// No usable profile (readings 16 hours apart): this week's straight-line pace, 2.5% per hour, empties 20% in 8 hours.
emptyHistory = [
    Point(at: t(0, 0), remaining: 100, resetAt: t(1, 0), plan: "Max 5x"),
    Point(at: t(0, 16), remaining: 60, resetAt: t(1, 0), plan: "Max 5x")
]
emptyCurrent = Point(at: t(0, 32), remaining: 20, resetAt: t(1, 0), plan: "Max 5x")
emptyAt = QuotaWasteForecast.weeklyEmptyAt(history: emptyHistory, current: emptyCurrent, now: emptyCurrent.at, calendar: calendar)
assert(emptyAt.map { near($0.timeIntervalSince(t(0, 40)), 0, 1) } == true, "\(String(describing: emptyAt))")

print("waste forecast tests passed")
