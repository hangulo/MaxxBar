import Foundation

let t0 = Date(timeIntervalSince1970: 1_000_000)
let reset = t0.addingTimeInterval(5 * 3_600)
func reading(_ minutes: Double, _ percent: Int, reset: Date? = reset, plan: String? = "Max 5x") -> RunwayForecast.Reading {
    RunwayForecast.Reading(at: t0.addingTimeInterval(minutes * 60), remainingPercent: percent, resetAt: reset, plan: plan)
}

// 40% used in 30 minutes leaves 60% for another 45 minutes: empty at 1h15, before the 5h reset.
let fast = RunwayForecast.emptyAt([reading(0, 100), reading(10, 80), reading(30, 60)], minimumSpan: 1_200)
assert(fast.map { abs($0.timeIntervalSince(t0.addingTimeInterval(75 * 60))) < 1 } == true)

// A slow burn lasts until the reset: nothing to show.
assert(RunwayForecast.emptyAt([reading(0, 100), reading(60, 95)], minimumSpan: 1_200) == nil)

// Too short a span gives no forecast.
assert(RunwayForecast.emptyAt([reading(0, 100), reading(5, 90)], minimumSpan: 1_200) == nil)

// Readings from the previous window or plan are not used.
let otherWindow = reset.addingTimeInterval(-18_000)
assert(RunwayForecast.emptyAt([reading(0, 100, reset: otherWindow), reading(30, 40)], minimumSpan: 1_200) == nil)
assert(RunwayForecast.emptyAt([reading(0, 100, plan: "Pro"), reading(30, 40)], minimumSpan: 1_200) == nil)

// Without a known reset time there is nothing to compare against.
assert(RunwayForecast.emptyAt([reading(0, 100, reset: nil), reading(30, 40, reset: nil)], minimumSpan: 1_200) == nil)

// A rise inside the list (new window) stops the walk back.
let afterRise = RunwayForecast.emptyAt([reading(0, 20), reading(10, 90), reading(40, 30)], minimumSpan: 1_200)
assert(afterRise != nil)
print("Runway forecast checks passed")
