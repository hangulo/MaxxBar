import Foundation

typealias E = ClaudeQuotaEstimator
let start = Date(timeIntervalSince1970: 1_800_000_000)
let reset5h = start.addingTimeInterval(4 * 3_600)
let nextReset5h = reset5h.addingTimeInterval(5 * 3_600)

func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
func reading(_ minutes: Double, _ used: Double, reset: Date = reset5h, plan: String? = "Max 5x", kind: E.Kind = .fiveHour) -> E.Reading {
    E.Reading(at: at(minutes), kind: kind, usedPercent: used, resetAt: reset, plan: plan, source: "endpoint")
}
/// One point per minute from `from` through `to`, `perMinute` tokens each; weighted tokens are a tenth.
func points(_ from: Int, _ to: Int, perMinute: Double = 1_000, weightedRatio: Double = 0.1) -> [E.UsagePoint] {
    (from...to).map { E.UsagePoint(at: at(Double($0)), tokens: perMinute, weightedTokens: perMinute * weightedRatio) }
}

// Ledger: tokens strictly after the start and through the end.
let ledger = E.Ledger(points(1, 10))
assert(ledger.tokens(after: at(0), through: at(10), weighted: false) == 10_000)
assert(ledger.tokens(after: at(5), through: at(10), weighted: false) == 5_000)
assert(ledger.tokens(after: at(5), through: at(5), weighted: false) == 0)
assert(ledger.tokens(after: at(0), through: at(10), weighted: true) == 1_000)

// Pairs: 10 minutes of 1,000 tokens per minute moves the reading 2 percent: 5,000 tokens per percent.
let usage = points(1, 60)
let readings = [reading(0, 10), reading(10, 12), reading(20, 14), reading(30, 16)]
let calibration = E.calibrate(readings: readings, usage: usage, kind: .fiveHour, plan: "Max 5x", since: .distantPast)!
assert(calibration.pairs == 3 && abs(calibration.tokensPerPercent - 5_000) < 0.001, "\(calibration)")
assert(!calibration.weighted, "equal spreads keep raw tokens")

// Too little data: two moving pairs, or too few percent moved, means no estimate.
assert(E.calibrate(readings: Array(readings.prefix(3)), usage: usage, kind: .fiveHour, plan: "Max 5x", since: .distantPast) == nil)
let tiny = [reading(0, 10), reading(10, 11), reading(20, 11), reading(30, 11.5), reading(40, 12)]
assert(E.calibrate(readings: tiny, usage: usage, kind: .fiveHour, plan: "Max 5x", since: .distantPast) == nil)
assert(E.calibrate(readings: readings, usage: [], kind: .fiveHour, plan: "Max 5x", since: .distantPast) == nil, "no tokens")

// Plan cutoff: readings on another plan never pair, and planStart finds the current plan's first reading.
let mixed = [reading(0, 10, plan: "Pro"), reading(10, 12, plan: "Pro"), reading(20, 14, plan: "Pro"), reading(30, 16)]
assert(E.calibrate(readings: mixed, usage: usage, kind: .fiveHour, plan: "Max 5x", since: .distantPast) == nil)
assert(E.planStart(of: mixed, plan: "Max 5x") == at(30))
assert(E.planStart(of: readings, plan: "Max 5x") == at(0))
assert(E.planStart(of: mixed, plan: "Pro") == nil, "a plan that is no longer current has no start")
// The `since` cutoff drops earlier pairs.
assert(E.calibrate(readings: readings, usage: usage, kind: .fiveHour, plan: "Max 5x", since: at(5)) == nil)

// Reset boundary: a pair straddling a reset (different reset times) is not a pair, and a drop is skipped.
let straddling = [reading(0, 80), reading(10, 82), reading(20, 84), reading(30, 2, reset: nextReset5h), reading(40, 4, reset: nextReset5h)]
let straddled = E.calibrate(readings: straddling, usage: usage, kind: .fiveHour, plan: "Max 5x", since: .distantPast)
assert(straddled?.pairs == 3 && abs(straddled!.tokensPerPercent - 5_000) < 0.001, "\(String(describing: straddled))")
let dropped = [reading(0, 10), reading(10, 12), reading(20, 9), reading(30, 11), reading(40, 13)]
assert(E.calibrate(readings: dropped, usage: usage, kind: .fiveHour, plan: "Max 5x", since: .distantPast)?.pairs == 3)
// Reset times that wobble by seconds are still one window.
assert(E.sameWindow(reading(0, 1), reading(1, 1, reset: reset5h.addingTimeInterval(2))))
assert(!E.sameWindow(reading(0, 1), reading(1, 1, kind: .weekly)))

// Weighting by model is used only when it fits better: here raw tokens jump around, weighted ones do not.
var noisy: [E.UsagePoint] = []
for minute in 1...30 {
    let heavy = minute <= 10 // the first pair used a model whose tokens weigh less
    noisy.append(E.UsagePoint(at: at(Double(minute)), tokens: heavy ? 3_000 : 1_000, weightedTokens: 100))
}
let weightedFit = E.calibrate(readings: readings, usage: noisy, kind: .fiveHour, plan: "Max 5x", since: .distantPast)!
assert(weightedFit.weighted && abs(weightedFit.tokensPerPercent - 500) < 0.001, "\(weightedFit)")

// Estimate: last reading plus tokens since, snapped to each reading, never down, clamped.
let last = reading(30, 16)
let estimate = E.estimate(from: last, calibration: calibration, ledger: E.Ledger(usage), now: at(40))!
assert(abs(estimate.usedPercent - 18) < 0.001, "\(estimate)")
assert(E.estimate(from: last, calibration: calibration, ledger: E.Ledger(usage), now: at(30)) == nil, "no time passed")
assert(E.estimate(from: reading(60, 30), calibration: calibration, ledger: E.Ledger(usage), now: at(90)) == nil, "no tokens since")
assert(E.estimate(from: last, calibration: calibration, ledger: E.Ledger(usage), now: reset5h) == nil, "window has reset")
// Never decreasing: a rescan that counts fewer tokens keeps the previous estimate for the same reading.
let fewer = E.estimate(from: last, calibration: calibration, ledger: E.Ledger(points(31, 35)), now: at(41), previous: estimate)!
assert(fewer.usedPercent == estimate.usedPercent)
// A new real reading is the new base: the estimate snaps to it even when it is lower.
let snapped = E.estimate(from: reading(41, 17), calibration: calibration, ledger: E.Ledger(usage), now: at(46), previous: estimate)!
assert(abs(snapped.usedPercent - 18) < 0.001, "\(snapped)")
// Clamping at 100 and at 0.
let huge = E.estimate(from: reading(30, 98), calibration: calibration, ledger: E.Ledger(points(31, 60, perMinute: 1_000_000)), now: at(60))!
assert(huge.usedPercent == 100)
let negative = E.estimate(from: reading(30, -5), calibration: calibration, ledger: E.Ledger(points(31, 31, perMinute: 1)), now: at(31))!
assert(negative.usedPercent == 0)
assert(E.estimate(from: last, calibration: E.Calibration(tokensPerPercent: 0, weighted: false, pairs: 3), ledger: E.Ledger(usage), now: at(40)) == nil)

// Reading log: dedupes, keeps 8 days, seeds only real endpoint readings from history.
let merged = ClaudeReadingLog.merge([reading(0, 10)], adding: [reading(0, 10), reading(10, 12), reading(10, 40, kind: .weekly)], now: at(20))
assert(merged.count == 3)
assert(ClaudeReadingLog.merge(merged, adding: [], now: at(20).addingTimeInterval(9 * 86_400)).isEmpty)
let history = [
    LLMQuotaHistorySample(sampledAt: at(0), primaryRemainingPercent: nil, weeklyRemainingPercent: nil,
                          claudeWeeklyRemainingPercent: 60, claudeFiveHourRemainingPercent: 90,
                          claudePlanType: "Max 5x", claudeSource: "endpoint", claudeFiveHourResetAt: reset5h),
    LLMQuotaHistorySample(sampledAt: at(5), primaryRemainingPercent: nil, weeklyRemainingPercent: nil,
                          claudeWeeklyRemainingPercent: 60, claudeFiveHourRemainingPercent: 88,
                          claudePlanType: "Max 5x", claudeSource: "cache")
]
let seeded = ClaudeReadingLog.seed(from: history)
assert(seeded.count == 2 && seeded.allSatisfy { $0.at == at(0) })
assert(seeded.first { $0.kind == .fiveHour }?.usedPercent == 10 && seeded.first { $0.kind == .weekly }?.usedPercent == 40)
// The log file round-trips and is only rewritten when something is added.
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-readings-\(UUID().uuidString)")
let logURL = dir.appendingPathComponent("claude-readings.json")
let first = ClaudeReadingLog.record([reading(0, 10)], now: at(1), url: logURL)
assert(first.count == 1)
let second = ClaudeReadingLog.record([reading(0, 10), reading(10, 12)], now: at(11), url: logURL)
assert(second.count == 2 && ClaudeReadingLog.record([], now: at(12), url: logURL) == second)
try? FileManager.default.removeItem(at: dir)

print("Claude quota estimator checks passed")
