import Foundation

let t0 = Date(timeIntervalSinceReferenceDate: 817_000_000) // after the Max 5x change, so the plan stays fixed
func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
func sample(
    _ minutes: Double, fiveLeft: Int? = nil, fiveReset: Double? = nil, weekLeft: Int? = nil, weekReset: Double? = nil,
    plan: String? = "Max 5x", fable: Int? = nil, fableReset: Double? = nil
) -> LLMQuotaHistorySample {
    LLMQuotaHistorySample(
        sampledAt: at(minutes), primaryRemainingPercent: nil, weeklyRemainingPercent: nil,
        claudeWeeklyRemainingPercent: weekLeft, claudeFiveHourRemainingPercent: fiveLeft, claudePlanType: plan,
        claudeSource: "endpoint", claudeFiveHourResetAt: fiveReset.map(at), claudeWeeklyResetAt: weekReset.map(at),
        claudeModelWeeklyRemaining: fable.map { ["Fable": $0] },
        claudeModelWeeklyResetAt: fableReset.map { ["Fable": at($0)] }
    )
}

// Normal close: the reading 10 minutes before the reset is what was left.
var history = [
    sample(0, fiveLeft: 90, fiveReset: 300, weekLeft: 80),
    sample(290, fiveLeft: 40, fiveReset: 300, weekLeft: 70),
    sample(310, fiveLeft: 100, fiveReset: 610, weekLeft: 70)
]
var records = QuotaWindowLedger.closedWindows(in: history, now: at(320))
assert(records.count == 1, "\(records)")
assert(records[0].kind == .fiveHour && records[0].leftPercent == 40 && records[0].lastUsedPercent == 60)
assert(!records[0].lowConfidence && records[0].sampleAgeAtResetSeconds == 600)
assert(records[0].weeklyAllUsedPercentAtClose == 30 && records[0].plan == "Max 5x")

// Close after a gap: the last reading is two hours old, so it is low confidence.
history = [
    sample(0, fiveLeft: 50, fiveReset: 300),
    sample(180, fiveLeft: 45, fiveReset: 300),
    sample(900, fiveLeft: 95, fiveReset: 1_200)
]
records = QuotaWindowLedger.closedWindows(in: history, now: at(910))
assert(records.count == 1 && records[0].leftPercent == 45 && records[0].lowConfidence, "\(records)")
assert(records[0].windowResetAt == at(300))

// A window whose reset passed while nothing was sampled closes from the last reading.
records = QuotaWindowLedger.closedWindows(in: [sample(0, fiveLeft: 70, fiveReset: 100)], now: at(200))
assert(records.count == 1 && records[0].leftPercent == 70 && records[0].lowConfidence)

// Dedupe: reset times that jitter by seconds are one window, and existing records are not added again.
history = [
    sample(0, fiveLeft: 60, fiveReset: 300),
    sample(295, fiveLeft: 50, fiveReset: 300.01),
    sample(320, fiveLeft: 99, fiveReset: 620)
]
records = QuotaWindowLedger.closedWindows(in: history, now: at(330))
assert(records.count == 1, "\(records)")
let again = QuotaWindowLedger.closedWindows(in: history + [sample(400, fiveLeft: 98, fiveReset: 620)], now: at(410))
assert(QuotaWindowLedger.newRecords(again, existing: records).isEmpty)

// A reset that moves an hour or more later means the window ended early.
history = [sample(0, fiveLeft: 70, fiveReset: 300), sample(100, fiveLeft: 100, fiveReset: 500)]
records = QuotaWindowLedger.closedWindows(in: history, now: at(110))
assert(records.count == 1 && records[0].windowResetAt == at(300))

// Plan change: a jump in remaining percent from an upgrade is not a close.
let upgrade = ClaudePlanTimeline.entries[1].from
let old = Date(timeIntervalSinceReferenceDate: 0)
let beforeUpgrade = LLMQuotaHistorySample(
    sampledAt: upgrade.addingTimeInterval(-3_600), primaryRemainingPercent: nil, weeklyRemainingPercent: nil,
    claudeWeeklyRemainingPercent: 10
)
let afterUpgrade = LLMQuotaHistorySample(
    sampledAt: upgrade.addingTimeInterval(3_600), primaryRemainingPercent: nil, weeklyRemainingPercent: nil,
    claudeWeeklyRemainingPercent: 82
)
_ = old
records = QuotaWindowLedger.closedWindows(in: [beforeUpgrade, afterUpgrade], now: upgrade.addingTimeInterval(7_200))
assert(records.isEmpty, "\(records)")
history = [sample(0, weekLeft: 20, weekReset: 5_000, plan: "pro"), sample(60, weekLeft: 85, weekReset: 5_000, plan: "max_5x")]
assert(QuotaWindowLedger.closedWindows(in: history, now: at(70)).isEmpty)

// Unused 5 hour window: nothing was used, so nothing is recorded.
history = [sample(0, fiveLeft: 100, fiveReset: 300), sample(310, fiveLeft: 100, fiveReset: 610)]
assert(QuotaWindowLedger.closedWindows(in: history, now: at(320)).isEmpty)

// Per-model weekly (Fable), and a weekly reset with a reported time.
history = [
    sample(0, weekLeft: 50, weekReset: 1_000, fable: 70, fableReset: 999),
    sample(990, weekLeft: 30, weekReset: 1_000, fable: 40, fableReset: 999),
    sample(1_010, weekLeft: 100, weekReset: 11_080, fable: 100, fableReset: 11_079)
]
records = QuotaWindowLedger.closedWindows(in: history, now: at(1_020))
let fable = records.first { $0.kind == .weeklyModel }
assert(fable?.model == "Fable" && fable?.leftPercent == 40 && fable?.lowConfidence == false, "\(records)")
assert(records.first { $0.kind == .weekly }?.leftPercent == 30)

// Older weekly rows without reset times: the reset is inferred from the weekly schedule.
let anchor = at(20_000)
func weeklyOnly(_ date: Date, _ left: Int, reset: Date? = nil) -> LLMQuotaHistorySample {
    LLMQuotaHistorySample(
        sampledAt: date, primaryRemainingPercent: nil, weeklyRemainingPercent: nil,
        claudeWeeklyRemainingPercent: left, claudePlanType: "Max 5x", claudeWeeklyResetAt: reset
    )
}
let weekAgo = anchor.addingTimeInterval(-QuotaWindowLedger.week)
history = [
    weeklyOnly(weekAgo.addingTimeInterval(-600), 25),
    weeklyOnly(weekAgo.addingTimeInterval(600), 100),
    weeklyOnly(anchor.addingTimeInterval(-3_600), 60, reset: anchor)
]
records = QuotaWindowLedger.closedWindows(in: history, now: anchor.addingTimeInterval(-1_800))
assert(records.count == 1 && records[0].resetInferred && records[0].leftPercent == 25, "\(records)")
assert(records[0].windowResetAt == weekAgo)

// Summary for the card.
let summaryRecords = QuotaWindowLedger.closedWindows(in: [
    sample(0, fiveLeft: 60, fiveReset: 300), sample(295, fiveLeft: 20, fiveReset: 300),
    sample(310, fiveLeft: 90, fiveReset: 610), sample(600, fiveLeft: 40, fiveReset: 610), sample(620, fiveLeft: 100)
], now: at(630))
let summary = QuotaLeftAtReset(records: summaryRecords, now: at(630))
assert(summary.lastFiveHour?.leftPercent == 40 && summary.fiveHourCountWeek == 2 && summary.fiveHourAverageWeek == 30)

// Store: first run backfills, later runs append only what is new, and bad lines are skipped.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let file = directory.appendingPathComponent("llm-window-ledger.jsonl")
let first = QuotaWindowLedgerStore.appendClosedWindows(history: Array(summaryRecords.isEmpty ? [] : [
    sample(0, fiveLeft: 60, fiveReset: 300), sample(295, fiveLeft: 20, fiveReset: 300)
]), now: at(305), to: file)
assert(first.count == 1 && first[0].backfilled)
try! (String(contentsOf: file, encoding: .utf8) + "not json\n").write(to: file, atomically: true, encoding: .utf8)
let second = QuotaWindowLedgerStore.appendClosedWindows(history: [
    sample(0, fiveLeft: 60, fiveReset: 300), sample(295, fiveLeft: 20, fiveReset: 300),
    sample(310, fiveLeft: 90, fiveReset: 610), sample(600, fiveLeft: 40, fiveReset: 610)
], now: at(615), to: file)
assert(second.count == 2 && !second[1].backfilled, "\(second)")
assert(QuotaWindowLedgerStore.load(from: file).count == 2)

// Plan timeline.
assert(ClaudePlanTimeline.entry(at: upgrade.addingTimeInterval(-1)).plan == "Pro")
assert(ClaudePlanTimeline.entry(at: upgrade).monthlyUSD == 100)
assert(ClaudePlanTimeline.normalized("max_5x") == "Max 5x" && ClaudePlanTimeline.normalized("pro") == "Pro")

print("quota ledger tests passed")
