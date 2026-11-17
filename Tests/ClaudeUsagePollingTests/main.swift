import Foundation

let now = Date(timeIntervalSince1970: 1_800_000_000)
let data = Data("usage fixture".utf8)
var state = ClaudeUsagePollingState(credentialID: "account-a")
state.succeeded(data: data, at: now)
assert(state.nextAllowedAt == now)
state.failed(status: 429, retryAfter: nil, message: "rate limited", at: now)
assert(state.usableData(at: now) == data)
assert(state.nextAllowedAt == now.addingTimeInterval(300))
state.failed(status: 429, retryAfter: "1800", message: "rate limited", at: now)
assert(state.nextAllowedAt == now.addingTimeInterval(1800))
state.failed(status: 429, retryAfter: "Fri, 15 Jan 2027 10:00:00 GMT", message: "rate limited", at: now)
assert(state.nextAllowedAt == Date(timeIntervalSince1970: 1_800_007_200))
for _ in 0..<10 {
    state.failed(status: 429, retryAfter: "invalid", message: "rate limited", at: now)
}
assert(state.nextAllowedAt == now.addingTimeInterval(3600))
let restored = try JSONDecoder().decode(ClaudeUsagePollingState.self, from: JSONEncoder().encode(state))
assert(restored.cachedData == data && restored.nextAllowedAt == state.nextAllowedAt)
assert(restored.rateLimitCount == state.rateLimitCount)
assert(state.usableData(at: now.addingTimeInterval(86_400)) == nil)
state.succeeded(data: data, at: now)
assert(state.rateLimitCount == 0 && state.lastError == nil)
state.failed(status: 401, retryAfter: nil, message: "unauthorized", at: now)
assert(state.cachedData == nil && state.fetchedAt == nil)
state.succeeded(data: data, at: now)
state.failed(status: nil, retryAfter: nil, message: "timeout", at: now)
assert(state.usableData(at: now) == data)
assert(state.nextAllowedAt == now.addingTimeInterval(60))
state.failed(status: 429, retryAfter: "1800", message: "rate limited", at: now)
let cooldown = state.nextAllowedAt
state.switchCredential(to: "account-b")
assert(state.credentialID == "account-b" && state.nextAllowedAt == cooldown)
assert(state.cachedData == nil && state.rateLimitCount > 0)

let statusLineJSON = Data("""
{"session_id":"x","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":41,"resets_at":1799999000}}}
""".utf8)
let tapped = ClaudeStatusLineLimits.parse(statusLineJSON, capturedAt: now)!
assert(tapped.fiveHour == .init(usedPercent: 23.5, resetAt: Date(timeIntervalSince1970: 1_800_003_600)))
assert(tapped.sevenDay?.usedPercent == 41)
let current = tapped.current(at: now)!
assert(current.fiveHour != nil && current.sevenDay == nil)
assert(tapped.current(at: now.addingTimeInterval(7_200)) == nil)
assert(tapped.isFresh(at: now.addingTimeInterval(600)) && !tapped.isFresh(at: now.addingTimeInterval(1_800)))
assert(ClaudeStatusLineLimits.parse(Data(#"{"model":{}}"#.utf8), capturedAt: now) == nil)
assert(ClaudeStatusLineLimits.parse(Data(#"{"rate_limits":{}}"#.utf8), capturedAt: now) == nil)
// The saved reading can be reloaded without a token and still honors the 24-hour discard.
let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent("maxxbar-polling-\(UUID().uuidString).json")
defer { try? FileManager.default.removeItem(at: saveURL) }
var saved = ClaudeUsagePollingState(credentialID: "account:x")
saved.succeeded(data: data, at: now)
try JSONEncoder().encode(saved).write(to: saveURL)
let reloaded = ClaudeUsagePollingState.load(from: saveURL)!
assert(reloaded.usableData(at: now.addingTimeInterval(3_600)) == data)
assert(reloaded.usableData(at: now.addingTimeInterval(86_400)) == nil)
assert(ClaudeUsagePollingState.load(from: saveURL.appendingPathExtension("missing")) == nil)
// Adaptive schedule and 429 floor.
func usage(_ pct: Double) -> Data { Data("{\"five_hour\":{\"utilization\":\(pct)}}".utf8) }
var sched = ClaudeUsagePollingState(credentialID: "s")
sched.succeeded(data: usage(10), at: now)
assert(sched.refreshInterval(lastActivity: now.addingTimeInterval(60), at: now.addingTimeInterval(90)) == 180)
assert(sched.refreshInterval(lastActivity: now.addingTimeInterval(-600), at: now) == 300)
assert(sched.refreshInterval(lastActivity: now.addingTimeInterval(-3_600), at: now) == 1_800)
assert(sched.refreshInterval(lastActivity: nil, at: now) == 1_800)
sched.succeeded(data: usage(20), at: now)
assert(sched.readingChanged == true && sched.refreshInterval(lastActivity: nil, at: now) == 180)
sched.succeeded(data: usage(75), at: now)
sched.succeeded(data: usage(75), at: now)
assert(sched.readingChanged == false && sched.refreshInterval(lastActivity: nil, at: now) == 180)
assert(!sched.isDue(at: now.addingTimeInterval(100), interval: 120) && sched.isDue(at: now.addingTimeInterval(120), interval: 120))
assert(!sched.allowsManualCheck(at: now.addingTimeInterval(59)) && sched.allowsManualCheck(at: now.addingTimeInterval(61)))
sched.failed(status: 429, retryAfter: nil, message: "rate limited", at: now)
assert(sched.activeFloor == 240 && !sched.allowsManualCheck(at: now.addingTimeInterval(60)))
sched.failed(status: 429, retryAfter: nil, message: "rate limited", at: now)
sched.failed(status: 429, retryAfter: nil, message: "rate limited", at: now)
sched.failed(status: 429, retryAfter: nil, message: "rate limited", at: now)
assert(sched.activeFloor == 900 && sched.refreshInterval(lastActivity: now, at: now) == 900)
sched.decayFloor(at: now.addingTimeInterval(3_599))
assert(sched.activeFloor == 900)
sched.decayFloor(at: now.addingTimeInterval(7_200))
assert(sched.activeFloor == 240)
let floorRestored = try JSONDecoder().decode(ClaudeUsagePollingState.self, from: JSONEncoder().encode(sched))
assert(floorRestored.activeFloor == 240)
// Older cache files without the new fields still decode.
let legacy = try JSONDecoder().decode(ClaudeUsagePollingState.self, from: Data(#"{"credentialID":"x","nextAllowedAt":0,"rateLimitCount":0}"#.utf8))
assert(legacy.activeFloor == 120)
// "Check now" skip reasons: each blocked click explains itself, an allowed click returns nil.
var manual = ClaudeUsagePollingState(credentialID: "m")
assert(manual.manualCheckBlockReason(at: now) == nil)
manual.succeeded(data: usage(10), at: now)
assert(manual.manualCheckBlockReason(at: now.addingTimeInterval(12)) == "Checked 12s ago")
assert(manual.manualCheckBlockReason(at: now.addingTimeInterval(45)) == "Checked 45s ago", "the 60s hard gap holds Check now too")
assert(manual.manualCheckBlockReason(at: now.addingTimeInterval(61)) == nil && manual.allowsManualCheck(at: now.addingTimeInterval(61)))
manual.failed(status: 429, retryAfter: nil, message: "Claude usage requests are temporarily rate-limited (HTTP 429)", at: now)
assert(manual.manualCheckBlockReason(at: now.addingTimeInterval(60))!.hasPrefix("Rate limited, next try at "))
assert(!manual.allowsManualCheck(at: now.addingTimeInterval(60)) && manual.allowsManualCheck(at: now.addingTimeInterval(301)))
manual.failed(status: nil, retryAfter: nil, message: "Usage request timed out", at: now)
assert(manual.manualCheckBlockReason(at: now.addingTimeInterval(10))!.hasPrefix("Next try at "))
// Stale marker: a reading seconds old is live (no "~"); one over five minutes old carries its check time.
assert(ClaudeUsagePollingState.staleMarker(checkedAt: now, now: now.addingTimeInterval(10)) == nil)
assert(ClaudeUsagePollingState.staleMarker(checkedAt: now, now: now.addingTimeInterval(300)) == nil)
assert(ClaudeUsagePollingState.staleMarker(checkedAt: now, now: now.addingTimeInterval(301)) == now)
assert(ClaudeUsagePollingState.staleMarker(checkedAt: nil, now: now) == nil)

// Triggers: every one passes the cooldown, the 60s hard gap and the hourly limit; events want a reading 2+ min old.
var gate = ClaudeUsagePollingState(credentialID: "g")
assert(gate.allowsRequest(trigger: .popoverOpened, at: now, interval: 300), "no reading yet")
gate.succeeded(data: usage(10), at: now)
for trigger in [ClaudePollTrigger.manual, .resetPassed, .popoverOpened, .wake, .heavyUse, .scheduled] {
    assert(!gate.allowsRequest(trigger: trigger, at: now.addingTimeInterval(59), interval: 0), "hard gap: \(trigger)")
}
assert(gate.allowsRequest(trigger: .manual, at: now.addingTimeInterval(60), interval: 300))
assert(gate.allowsRequest(trigger: .resetPassed, at: now.addingTimeInterval(60), interval: 300))
assert(!gate.allowsRequest(trigger: .popoverOpened, at: now.addingTimeInterval(90), interval: 300))
assert(gate.allowsRequest(trigger: .popoverOpened, at: now.addingTimeInterval(120), interval: 300))
assert(gate.allowsRequest(trigger: .wake, at: now.addingTimeInterval(120), interval: 300))
assert(gate.allowsRequest(trigger: .heavyUse, at: now.addingTimeInterval(120), interval: 300))
assert(!gate.allowsRequest(trigger: .heavyUse, at: now.addingTimeInterval(120), interval: 300, liveFeed: true))
assert(!gate.allowsRequest(trigger: .scheduled, at: now.addingTimeInterval(120), interval: 300))
assert(gate.allowsRequest(trigger: .scheduled, at: now.addingTimeInterval(300), interval: 300))
// A 429 cooldown holds every trigger, "Check now" and resets included.
var cooled = gate
cooled.failed(status: 429, retryAfter: nil, message: "rate limited", at: now.addingTimeInterval(120))
for trigger in [ClaudePollTrigger.manual, .resetPassed, .popoverOpened, .scheduled] {
    assert(!cooled.allowsRequest(trigger: trigger, at: now.addingTimeInterval(400), interval: 0), "cooldown: \(trigger)")
}
// Hourly limit: 30 requests in an hour, then nothing until the oldest is an hour old.
var busy = ClaudeUsagePollingState(credentialID: "b")
for minute in 0..<30 { busy.succeeded(data: usage(Double(minute)), at: now.addingTimeInterval(Double(minute) * 61)) }
let afterBurst = now.addingTimeInterval(30 * 61)
assert(busy.recentRequests?.count == 30)
assert(!busy.allowsRequest(trigger: .manual, at: afterBurst, interval: 0))
assert(busy.manualCheckBlockReason(at: afterBurst)!.hasPrefix("30 checks in the last hour"))
assert(busy.allowsRequest(trigger: .manual, at: now.addingTimeInterval(3_600), interval: 0))
// Simulated worst case: every trigger firing every 15s for 3 hours never exceeds 30 calls in any hour.
var storm = ClaudeUsagePollingState(credentialID: "s")
var calls: [Date] = []
for tick in 0..<(3 * 240) {
    let time = now.addingTimeInterval(Double(tick) * 15)
    for trigger in [ClaudePollTrigger.manual, .resetPassed, .popoverOpened, .heavyUse, .scheduled]
    where storm.allowsRequest(trigger: trigger, at: time, interval: 180) {
        storm.succeeded(data: usage(1), at: time)
        calls.append(time)
    }
}
for call in calls { assert(calls.filter { $0 >= call && $0 < call.addingTimeInterval(3_600) }.count <= 30) }
assert(zip(calls, calls.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 60 })
// A reset in the saved reading that has passed since it was read is noticed once.
let resetData = Data(#"{"five_hour":{"utilization":40,"resets_at":"2027-01-15T09:00:00.000Z"},"seven_day":{"utilization":10,"resets_at":"2027-01-20T09:00:00Z"}}"#.utf8)
var resetState = ClaudeUsagePollingState(credentialID: "r")
let beforeReset = Date(timeIntervalSince1970: 1_800_000_000) // 08:00Z
resetState.succeeded(data: resetData, at: beforeReset)
assert(!resetState.resetPassedSinceFetch(at: beforeReset.addingTimeInterval(1_800)))
assert(resetState.resetPassedSinceFetch(at: beforeReset.addingTimeInterval(3_601)))
resetState.succeeded(data: resetData, at: beforeReset.addingTimeInterval(3_700))
assert(!resetState.resetPassedSinceFetch(at: beforeReset.addingTimeInterval(4_000)), "already read after the reset")
// Cache files from before these fields still decode, and the request log survives a credential switch.
assert(legacy.recentRequests == nil)
var switched = gate
switched.switchCredential(to: "other")
assert(switched.recentRequests == gate.recentRequests)
print("Claude polling checks passed")
