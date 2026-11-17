import Foundation

/// Why MaxxBar wants a fresh Claude reading. Every request, whatever its trigger, passes the same gate:
/// the 429 cooldown, the hard minimum gap and the hourly call limit.
enum ClaudePollTrigger: String {
    /// The adaptive timer (3 min active, 5 min normal, 30 min idle).
    case scheduled
    /// The popover opened on a reading older than `eventMinimumAge`.
    case popoverOpened
    /// The Mac woke or was unlocked.
    case wake
    /// Local token use since the last reading is estimated to have moved the 5h window by `heavyUsePercent`.
    case heavyUse
    /// A reset time in the last reading has passed (detected by the polling state itself).
    case resetPassed
    /// "Check now", and the reading booked just before a known reset.
    case manual
}

/// Persist only usage data and a credential fingerprint, never the OAuth token.
struct ClaudeUsagePollingState: Codable, Equatable {
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
    /// Every request in the last hour, successful or not, for the hard gap and the hourly limit.
    var recentRequests: [Date]?

    // Estimates from local tokens fill the gaps between readings, so the timer runs slower than before
    // (it was 2 / 5 / 15 min) and the event triggers above ask at the moments a reading is worth most.
    static let activeInterval: TimeInterval = 180
    static let normalInterval: TimeInterval = 300
    static let idleInterval: TimeInterval = 1_800
    static let idleAfter: TimeInterval = 1_800
    /// No two requests are ever closer than this, whatever asked for them ("Check now" included).
    static let hardMinimumGap: TimeInterval = 60
    /// At most this many requests in any hour: the old 2-minute active schedule's rate, now a ceiling.
    static let hourlyRequestLimit = 30
    /// Popover, wake and heavy use triggers only ask when the reading is at least this old.
    static let eventMinimumAge: TimeInterval = 120
    /// Estimated 5h movement since the last reading that counts as heavy use.
    static let heavyUsePercent = 5.0
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
            floorLevel: floorLevel, floorChangedAt: floorChangedAt, recentRequests: recentRequests
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

    /// Active (Claude in use, usage moving, or 5h ≥ 70%): 3 min. Normal: 5 min. Idle 30+ min: 30 min.
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

    /// "Check now": immediate unless a cooldown, the hard gap or the hourly limit holds it back.
    func allowsManualCheck(at now: Date) -> Bool { manualCheckBlockReason(at: now) == nil }

    /// Why no request may be made right now, phrased for the card; nil when one may. Applies to every trigger.
    func manualCheckBlockReason(at now: Date) -> String? {
        if now < nextAllowedAt {
            let time = nextAllowedAt.formatted(date: .omitted, time: .shortened)
            return lastError?.contains("429") == true ? "Rate limited, next try at \(time)" : "Next try at \(time)"
        }
        if let last = [fetchedAt, recentRequests?.last].compactMap({ $0 }).max(),
           now.timeIntervalSince(last) < Self.hardMinimumGap {
            return "Checked \(max(Int(now.timeIntervalSince(last)), 0))s ago"
        }
        let lastHour = (recentRequests ?? []).filter { now.timeIntervalSince($0) < 3_600 }
        if lastHour.count >= Self.hourlyRequestLimit, let oldest = lastHour.min() {
            let time = oldest.addingTimeInterval(3_600).formatted(date: .omitted, time: .shortened)
            return "\(Self.hourlyRequestLimit) checks in the last hour, next at \(time)"
        }
        return nil
    }

    /// Whether `trigger` may make a request now. `liveFeed` is true while a fresh status line capture is
    /// already live, so only the timer (at its slower hourly pace), resets and "Check now" still ask.
    func allowsRequest(
        trigger: ClaudePollTrigger, at now: Date, interval: TimeInterval, liveFeed: Bool = false
    ) -> Bool {
        guard manualCheckBlockReason(at: now) == nil else { return false }
        switch trigger {
        case .manual, .resetPassed:
            return true
        case .scheduled:
            return isDue(at: now, interval: interval)
        case .popoverOpened, .wake, .heavyUse:
            guard !liveFeed else { return false }
            guard usableData(at: now) != nil, let fetchedAt else { return true }
            return now.timeIntervalSince(fetchedAt) >= Self.eventMinimumAge
        }
    }

    /// True when a 5h or weekly reset in the saved reading has passed since it was taken: the window
    /// it describes is over and a new reading is worth more than any estimate.
    func resetPassedSinceFetch(at now: Date) -> Bool {
        guard let fetchedAt, let data = cachedData,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return ["five_hour", "seven_day"].contains { key in
            guard let text = (root[key] as? [String: Any])?["resets_at"] as? String,
                  let reset = formatter.date(from: text) ?? plain.date(from: text) else { return false }
            return reset > fetchedAt && reset <= now
        }
    }

    private mutating func recordRequest(at now: Date) {
        recentRequests = ((recentRequests ?? []) + [now]).filter { now.timeIntervalSince($0) < 3_600 }
    }

    mutating func succeeded(data: Data, at now: Date) {
        let previous = fiveHourUtilization
        let current = Self.fiveHourUtilization(in: data)
        readingChanged = previous != nil && current != nil && previous != current
        recordRequest(at: now)
        cachedData = data
        fetchedAt = now
        nextAllowedAt = now
        rateLimitCount = 0
        lastError = nil
    }

    mutating func failed(status: Int?, retryAfter: String?, message: String, at now: Date) {
        recordRequest(at: now)
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
