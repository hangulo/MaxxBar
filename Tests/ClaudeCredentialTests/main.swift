import Foundation

func credential(_ token: String, expires: Double, refresh: String? = "refresh") -> ClaudeOAuthCredential {
    var oauth: [String: Any] = ["accessToken": token, "expiresAt": expires * 1000,
        "refreshTokenExpiresAt": 3_000_000_000.0, "scopes": ["user:profile"]]
    oauth["refreshToken"] = refresh
    return ClaudeOAuthCredential(data: try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth]))!
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
var now = Date(timeIntervalSince1970: 1_000_000)
var current: ClaudeOAuthCredential? = credential("valid", expires: 1_000_100)
var runs = 0
// What Claude Code leaves in its storage after a keep-alive request.
var outcome: () -> ClaudeOAuthCredential? = { credential("refreshed-\(runs)", expires: now.timeIntervalSince1970 + 28_800) }
let keepAlive: () -> ClaudeKeepAliveRun = {
    runs += 1
    current = outcome()
    return ClaudeKeepAliveRun(exitCode: 0, duration: 2, errorClass: nil)
}
func manager(_ name: String, enabled: Bool = true) -> ClaudeCredentialManager {
    ClaudeCredentialManager(load: { current }, keepAlive: keepAlive,
                            stateURL: directory.appendingPathComponent("\(name).json"),
                            logURL: directory.appendingPathComponent("\(name).log"),
                            clock: { now }, enabled: enabled)
}

// A valid token is used as-is, even close to expiry: Claude Code refreshes only after expiry.
let keeper = manager("keeper")
var result = keeper.read()
assert(result.accessToken == "valid" && !result.refreshed && runs == 0)

// After expiry: one keep-alive run, verified, and flagged so usage is read right away.
now = now.addingTimeInterval(200)
result = keeper.read()
assert(result.accessToken == "refreshed-1" && result.refreshed && runs == 1 && keeper.state == nil)
// A rejected token (HTTP 401) also triggers one run.
now = now.addingTimeInterval(60)
result = keeper.read(rejectedAccessToken: "refreshed-1")
assert(result.accessToken == "refreshed-2" && runs == 2)
// Another Claude process already rotated the rejected token: nothing runs.
assert(keeper.read(rejectedAccessToken: "old").accessToken == "refreshed-2" && runs == 2)

// Failure: retry once after 10 minutes, then stop until the credential changes. Never loops.
let failing = manager("failing")
current = credential("expired", expires: now.timeIntervalSince1970 - 1)
let stale = current
outcome = { stale }
result = failing.read()
assert(result.accessToken == nil && result.error!.contains("trying again") && runs == 3 && failing.state?.attempts == 1)
now = now.addingTimeInterval(300)
result = failing.read()
assert(result.error!.contains("trying again") && runs == 3)
now = now.addingTimeInterval(301)
result = failing.read()
assert(result.error == ClaudeCredentialManager.gaveUpMessage && runs == 4)
now = now.addingTimeInterval(7_200)
assert(failing.read().error == ClaudeCredentialManager.gaveUpMessage && runs == 4)
// The attempt count survives a restart.
assert(manager("failing").read().error == ClaudeCredentialManager.gaveUpMessage && runs == 4)
// A new sign-in starts fresh.
current = credential("signed-in", expires: now.timeIntervalSince1970 + 28_800)
assert(failing.read().accessToken == "signed-in" && runs == 4)

// Verification rejects empty, unchanged, older or refresh-less results.
func rejects(_ name: String, _ after: ClaudeOAuthCredential?) {
    current = credential("needs-\(name)", expires: now.timeIntervalSince1970 - 10)
    outcome = { after }
    let before = runs
    let read = manager(name).read()
    assert(read.accessToken == nil && !read.refreshed && runs == before + 1, name)
}
rejects("emptied", nil)
rejects("older", credential("older-token", expires: now.timeIntervalSince1970 - 20))
rejects("no-refresh", credential("no-refresh-token", expires: now.timeIntervalSince1970 + 3_600, refresh: nil))

// Disabled: an expired sign-in only explains what to do; nothing runs.
current = credential("disabled-expired", expires: now.timeIntervalSince1970 - 1)
let before = runs
result = manager("disabled", enabled: false).read()
assert(result.accessToken == nil && result.error == ClaudeCredentialManager.expiredMessage
    && result.signInProblem == .expired && runs == before)

// Missing or empty credential: clear message, nothing runs.
current = nil
result = manager("missing").read()
assert(result.error == ClaudeCredentialManager.signedOutMessage && result.signInProblem == .signedOut && runs == before)

// Signed out at the time limit: Claude Code keeps the item with empty tokens, loginEnded and the end date.
let endedJSON = #"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0,"loginEnded":"time_limit","refreshTokenExpiresAt":1700000000000}}"#
let ended = ClaudeStoredSignIn(data: Data(endedJSON.utf8))!
assert(ended.credential == nil && ended.loginEnded == "time_limit"
    && ended.endsAt == Date(timeIntervalSince1970: 1_700_000_000))
let endedManager = ClaudeCredentialManager(loadSignIn: { ended }, keepAlive: keepAlive,
    stateURL: directory.appendingPathComponent("ended.json"), clock: { now })
result = endedManager.read()
assert(result.accessToken == nil && result.signInProblem == .timeLimit && runs == before)
assert(result.error == "Your Claude Code sign-in reached its time limit and was signed out. Click Sign in again to reconnect.")
assert(result.signInEndsAt == ended.endsAt && endedManager.lastSignIn.problem == .timeLimit)
// Any other empty item is a plain sign-out.
let other = ClaudeStoredSignIn(data: Data(#"{"claudeAiOauth":{"accessToken":"","refreshToken":""}}"#.utf8))!
result = ClaudeCredentialManager(loadSignIn: { other }, keepAlive: keepAlive,
    stateURL: directory.appendingPathComponent("other.json"), clock: { now }).read()
assert(result.error == "Claude Code is signed out. Click Sign in again to reconnect." && result.signInProblem == .signedOut)

// The end date of a usable sign-in is passed along, and warned about only in its last 7 days.
let endsAt = now.addingTimeInterval(6 * 86_400)
var stored = ClaudeStoredSignIn(credential: credential("ending", expires: now.timeIntervalSince1970 + 3_600), endsAt: endsAt)
let ending = ClaudeCredentialManager(loadSignIn: { stored }, keepAlive: keepAlive,
    stateURL: directory.appendingPathComponent("ending.json"), clock: { now })
result = ending.read()
assert(result.accessToken == "ending" && result.signInEndsAt == endsAt && result.signInProblem == nil)
assert(ending.read().signInEndsAt == endsAt) // from the cache
let warning = ClaudeCredentialManager.signInWarning(endsAt: endsAt, now: now)!
assert(warning.hasPrefix("Claude Code sign-in ends ") && warning.hasSuffix(". Sign in again before then to stay connected."), warning)
assert(!warning.contains("\u{2014}"))
assert(ClaudeCredentialManager.signInWarning(endsAt: now.addingTimeInterval(8 * 86_400), now: now) == nil)
assert(ClaudeCredentialManager.signInWarning(endsAt: now.addingTimeInterval(-60), now: now) == nil)
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .current
let sample = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 21, minute: 47))!
assert(ClaudeCredentialManager.signInWarning(endsAt: sample, now: sample.addingTimeInterval(-86_400))
    == "Claude Code sign-in ends Tue, Nov 24 at 9:47 PM. Sign in again before then to stay connected.")

// Sign in again: the unchanged credential is not taken as the new sign-in; a new valid one is adopted.
let baseline = ending.currentSignInFingerprint()
assert(!ending.adoptNewSignIn(replacing: baseline))
stored = ClaudeStoredSignIn(credential: nil, loginEnded: "time_limit")
assert(!ending.adoptNewSignIn(replacing: baseline))
stored = ClaudeStoredSignIn(credential: credential("new-login", expires: now.timeIntervalSince1970 + 28_800))
assert(ending.adoptNewSignIn(replacing: baseline) && ending.state == nil && ending.lastSignIn.problem == nil)
assert(ending.read().accessToken == "new-login")
assert(ClaudeOAuthCredential(data: Data(#"{"claudeAiOauth":{"accessToken":"","refreshToken":""}}"#.utf8)) == nil)

// State and log files never contain tokens.
for file in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
    let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
    assert(!text.contains("refreshed-") && !text.contains("expired") && !text.contains("needs-") && !text.contains("ending") && !text.contains("refresh\""), file)
}
let log = try String(contentsOf: directory.appendingPathComponent("keeper.log"), encoding: .utf8)
assert(log.contains("result=renewed") && log.contains("exit=0"))
// A valid token is cached until its expiry, so the Keychain is not read on every refresh.
var loads = 0
current = credential("cached", expires: now.timeIntervalSince1970 + 3_600)
let caching = ClaudeCredentialManager(load: { loads += 1; return current }, keepAlive: keepAlive,
                                      stateURL: directory.appendingPathComponent("caching.json"), clock: { now })
assert(caching.read().accessToken == "cached" && caching.read().accessToken == "cached" && loads == 1)
// A rejected token, or one past its expiry, is read again.
current = credential("rotated", expires: now.timeIntervalSince1970 + 7_200)
assert(caching.read(rejectedAccessToken: "cached").accessToken == "rotated" && loads == 2)
now = now.addingTimeInterval(7_300)
current = credential("next", expires: now.timeIntervalSince1970 + 3_600)
assert(caching.read().accessToken == "next" && loads == 3)
print("Claude keep-alive checks passed")
