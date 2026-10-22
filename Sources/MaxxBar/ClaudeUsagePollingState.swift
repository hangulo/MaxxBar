import Foundation

/// Persist only usage data and a credential fingerprint, never the OAuth token.
struct ClaudeUsagePollingState: Codable {
    var credentialID: String
    var cachedData: Data?
    var fetchedAt: Date?
    /// Earliest next request after a failure (429 backoff, timeouts); successful reads leave it at the read time.
    var nextAllowedAt: Date = .distantPast
    var rateLimitCount = 0
    var lastError: String?
    // Optional so cache files written by earlier versions still decode.
    var floorLevel: Int?
    var floorChangedAt: Date?
    var readingChanged: Bool?

    static let activeInterval: TimeInterval = 120
    static let normalInterval: TimeInterval = 300
    static let idleInterval: TimeInterval = 900
    static let idleAfter: TimeInterval = 1_800
    static let manualCheckMinimumAge: TimeInterval = 30
    private static let floorSteps: [TimeInterval] = [120, 240, 480, 900]

    /// Readings up to five minutes old count as live; older ones carry their check time, which the card shows
    /// and the menu bar marks with "~". Shared by endpoint and status line readings.
    static let staleAfter: TimeInterval = 300
    static func staleMarker(checkedAt: Date?, now: Date) -> Date? {
        guard let checkedAt, now.timeIntervalSince(checkedAt) > staleAfter else { return nil }
        return checkedAt
    }

    static func load(from url: URL) -> ClaudeUsagePollingState? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ClaudeUsagePollingState.self, from: $0) }
    }

    func usableData(at now: Date) -> Data? {
        guard let fetchedAt, now.timeIntervalSince(fetchedAt) < 86_400 else { return nil }
        return cachedData
    }

    /// Claude Code refreshes its OAuth token regularly. Keep the cooldown across a credential
    /// change so a new token cannot bypass a 429; only the cached usage belongs to the old one.
    mutating func switchCredential(to id: String) {
        guard id != credentialID else { return }
        self = ClaudeUsagePollingState(
            credentialID: id, nextAllowedAt: nextAllowedAt, rateLimitCount: rateLimitCount,
            floorLevel: floorLevel, floorChangedAt: floorChangedAt
        )
    }

    /// The shortest allowed gap between scheduled reads; doubles after each 429 (2 → 4 → 8 → 15 min).
    var activeFloor: TimeInterval { Self.floorSteps[min(max(floorLevel ?? 0, 0), Self.floorSteps.count - 1)] }

    /// The floor steps back down once per hour without a 429.
    mutating func decayFloor(at now: Date) {
        while let level = floorLevel, level > 0, let changed = floorChangedAt, now.timeIntervalSince(changed) >= 3_600 {
            floorLevel = level - 1
            floorChangedAt = changed.addingTimeInterval(3_600)
        }
    }

    var fiveHourUtilization: Double? { Self.fiveHourUtilization(in: cachedData) }

    /// Active (Claude in use, usage moving, or 5h ≥ 70%): 2 min. Normal: 5 min. Idle 30+ min: 15 min.
    func refreshInterval(lastActivity: Date?, at now: Date) -> TimeInterval {
        let activeSinceRead = lastActivity.map { activity in fetchedAt.map { activity > $0 } ?? true } ?? false
        let active = activeSinceRead || readingChanged == true || (fiveHourUtilization ?? 0) >= 70
        let idle = lastActivity.map { now.timeIntervalSince($0) >= Self.idleAfter } ?? true
        let base = active ? Self.activeInterval : (idle ? Self.idleInterval : Self.normalInterval)
        return max(base, activeFloor)
    }

    /// Whether a scheduled read may run now. A failure cooldown always applies.
    func isDue(at now: Date, interval: TimeInterval) -> Bool {
        guard now >= nextAllowedAt else { return false }
        guard usableData(at: now) != nil, let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= interval
    }

    /// "Check now": immediate unless a cooldown is active or the last read is under 30 seconds old.
    func allowsManualCheck(at now: Date) -> Bool { manualCheckBlockReason(at: now) == nil }

    /// Why "Check now" would not make a request, phrased for the card; nil when it will.
    func manualCheckBlockReason(at now: Date) -> String? {
        if now < nextAllowedAt {
            let time = nextAllowedAt.formatted(date: .omitted, time: .shortened)
            return lastError?.contains("429") == true ? "Rate limited, next try at \(time)" : "Next try at \(time)"
        }
        if let fetchedAt, now.timeIntervalSince(fetchedAt) < Self.manualCheckMinimumAge {
            return "Checked \(max(Int(now.timeIntervalSince(fetchedAt)), 0))s ago"
        }
        return nil
    }

    mutating func succeeded(data: Data, at now: Date) {
        let previous = fiveHourUtilization
        let current = Self.fiveHourUtilization(in: data)
        readingChanged = previous != nil && current != nil && previous != current
        cachedData = data
        fetchedAt = now
        nextAllowedAt = now
        rateLimitCount = 0
        lastError = nil
    }

    mutating func failed(status: Int?, retryAfter: String?, message: String, at now: Date) {
        lastError = message
        var delay: TimeInterval = 60
        if status == 429 {
            rateLimitCount = min(rateLimitCount + 1, 7)
            delay = min(300 * pow(2, Double(rateLimitCount - 1)), 3_600)
            floorLevel = min((floorLevel ?? 0) + 1, Self.floorSteps.count - 1)
            floorChangedAt = now
            if let retryAfter {
                if let seconds = TimeInterval(retryAfter), seconds.isFinite {
                    delay = max(delay, seconds)
                } else {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    if let date = formatter.date(from: retryAfter) {
                        delay = max(delay, date.timeIntervalSince(now))
                    }
                }
            }
        }
        if status == 401 || status == 403 {
            cachedData = nil
            fetchedAt = nil
            delay = 300
        }
        nextAllowedAt = now.addingTimeInterval(delay)
    }

    private static func fiveHourUtilization(in data: Data?) -> Double? {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let window = root["five_hour"] as? [String: Any] else { return nil }
        return (window["utilization"] as? NSNumber)?.doubleValue
    }
}
