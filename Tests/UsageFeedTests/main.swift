import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 00:00 PST

// Hourly buckets: calls in the same hour merge, old and synthetic calls are dropped, cost uses the model's rates.
let call = LLMTokenCall(
    timestamp: now.addingTimeInterval(-600),
    inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 100_000
)
var older = call
older.timestamp = now.addingTimeInterval(-8 * 86_400)
var yesterday = call
yesterday.timestamp = now.addingTimeInterval(-3_600 * 5)
let buckets = LLMUsageBucket.hourly(
    provider: "Claude",
    calls: [(call, "claude-opus-4-8"), (call, "claude-opus-4-8"), (older, "claude-opus-4-8"),
            (call, "<synthetic>"), (yesterday, "claude-haiku-4-5")],
    now: now,
    calendar: calendar
)
assert(buckets.count == 2, "\(buckets)")
assert(buckets[1].requests == 2 && buckets[1].tokens == 2_200_000)
// Opus: 1M fresh input at $5 + 0.1M output at $25 = $7.50 per call.
assert(abs(buckets[1].estimatedCostUSD - 15.0) < 0.0001, "\(buckets[1].estimatedCostUSD)")
assert(buckets[0].hourStart < buckets[1].hourStart)

let emptySnapshot = LLMUsageSnapshot(
    email: nil, planType: nil, limits: [], creditsBalance: nil, resetCreditCount: nil, resetCreditExpirations: [],
    lastUpdated: nil, localFiveHourTokens: 0, localWeeklyTokens: 0, localWeeklyThreads: 0, localWindows: [],
    costEstimates: [], recentSessions: [], topWeeklySessions: [], error: nil
)

// Feed: providers, daily roll-up by local day, rounding.
var snapshot = emptySnapshot
snapshot.limits = [
    LLMUsageLimit(
        name: "Claude",
        primary: LLMUsageWindow(label: "5h", usedPercent: 30, remainingPercent: 70, resetAt: now.addingTimeInterval(3_600), windowSeconds: 18_000),
        secondary: LLMUsageWindow(label: "Weekly", usedPercent: 10, remainingPercent: 90, resetAt: now.addingTimeInterval(86_400), windowSeconds: 604_800),
        checkedAt: now.addingTimeInterval(-60),
        source: "endpoint"
    )
]
snapshot.providerAccounts = [LLMProviderAccount(provider: "Claude", email: "x@example.com", displayName: nil, organizationName: nil, planName: "Max 5x")]
snapshot.usageBuckets = buckets
let feed = UsageFeed(snapshot: snapshot, now: now, calendar: calendar, appVersion: "test")
assert(feed.schemaVersion == 1 && feed.schema == "maxxbar.usage-feed")
assert(feed.providers.count == 1)
let claude = feed.providers[0]
assert(claude.plan == "Max 5x" && claude.source == "endpoint")
assert(claude.fiveHour?.remainingPercent == 70 && claude.weekly?.remainingPercent == 90)
assert(feed.hourly.count == 2)
// 23:50 and 19:00 on 14 Jan local are the same day.
assert(feed.daily.count == 1 && feed.daily[0].date == "2027-01-14", "\(feed.daily)")
assert(feed.daily[0].totals.requests == 3)

// The account email never goes into the feed.
let data = try UsageFeed.encoder().encode(feed)
let text = String(decoding: data, as: UTF8.self)
assert(!text.contains("example.com"))
assert(text.contains("\"remainingPercent\" : 70"))

// Round trip and change detection.
let decoded = try UsageFeed.decoder().decode(UsageFeed.self, from: data)
assert(decoded.providers == feed.providers && decoded.daily == feed.daily)
var later = UsageFeed(snapshot: snapshot, now: now.addingTimeInterval(120), calendar: calendar, appVersion: "test")
assert(later.sameContent(as: feed))
var polled = snapshot
polled.limits[0].checkedAt = now.addingTimeInterval(60)
later = UsageFeed(snapshot: polled, now: now.addingTimeInterval(120), calendar: calendar, appVersion: "test")
assert(later.sameContent(as: feed), "a checkedAt move under 5 minutes is not a change")
polled.limits[0].checkedAt = now.addingTimeInterval(600)
later = UsageFeed(snapshot: polled, now: now.addingTimeInterval(700), calendar: calendar, appVersion: "test")
assert(!later.sameContent(as: feed))
polled = snapshot
polled.limits[0].primary?.remainingPercent = 69
later = UsageFeed(snapshot: polled, now: now, calendar: calendar, appVersion: "test")
assert(!later.sameContent(as: feed))

// Closed windows: kept for 30 days, sorted, and a new close is a content change.
let oldClose = UsageFeed.ClosedWindow(provider: "Claude", kind: "fiveHour", model: nil, resetAt: now.addingTimeInterval(-40 * 86_400),
                                      usedPercent: 50, leftPercent: 50, lowConfidence: false, backfilled: true, plan: "Pro")
let lateClose = UsageFeed.ClosedWindow(provider: "Claude", kind: "weekly", model: nil, resetAt: now.addingTimeInterval(-3_600),
                                       usedPercent: 26, leftPercent: 74, lowConfidence: false, backfilled: false, plan: "Max 5x")
var earlyClose = lateClose
earlyClose.kind = "weeklyModel"
earlyClose.model = "Fable"
earlyClose.resetAt = now.addingTimeInterval(-7_200)
let withWindows = UsageFeed(snapshot: snapshot, closedWindows: [lateClose, oldClose, earlyClose], now: now, calendar: calendar, appVersion: "test")
assert(withWindows.closedWindows.map(\.kind) == ["weeklyModel", "weekly"], "\(withWindows.closedWindows)")
assert(!withWindows.sameContent(as: feed))
assert(feed.closedWindows.isEmpty)
let windowText = String(decoding: try UsageFeed.encoder().encode(withWindows), as: UTF8.self)
assert(windowText.contains("\"leftPercent\" : 74"))

// Estimates are marked, with the real reading beside them; measured values say so.
assert(claude.fiveHour?.basis == "measured" && claude.fiveHour?.measuredUsedPercent == nil)
var estimatedSnapshot = snapshot
estimatedSnapshot.limits[0].primary?.measuredUsedPercent = 30
estimatedSnapshot.limits[0].primary?.usedPercent = 36
estimatedSnapshot.limits[0].primary?.remainingPercent = 64
let estimatedFeed = UsageFeed(snapshot: estimatedSnapshot, now: now, calendar: calendar, appVersion: "test")
let estimatedWindow = estimatedFeed.providers[0].fiveHour!
assert(estimatedWindow.basis == "estimated" && estimatedWindow.remainingPercent == 64)
assert(estimatedWindow.measuredRemainingPercent == 70 && estimatedWindow.measuredUsedPercent == 30)
assert(estimatedFeed.providers[0].weekly?.basis == "measured")
assert(estimatedFeed.providers[0].checkedAt == claude.checkedAt, "checkedAt stays the real reading's time")
// A feed written before these fields existed still decodes.
let legacyWindow = try UsageFeed.decoder().decode(UsageFeed.Window.self, from: Data(#"{"remainingPercent":70,"usedPercent":30,"windowSeconds":18000}"#.utf8))
assert(legacyWindow.basis == nil && legacyWindow.measuredUsedPercent == nil)

// Writer: writes once, skips identical content, skips an empty snapshot.
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("usage-feed-\(UUID().uuidString)")
let target = dir.appendingPathComponent("usage-feed.json")
assert(!UsageFeedWriter.publish(emptySnapshot, to: target))
assert(UsageFeedWriter.publish(snapshot, to: target))
assert(!UsageFeedWriter.publish(snapshot, to: target))
assert(FileManager.default.fileExists(atPath: target.path))
try? FileManager.default.removeItem(at: dir)

print("usage feed tests passed")
