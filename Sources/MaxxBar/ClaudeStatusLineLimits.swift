import Foundation

/// Claude Code passes its status line command the subscription limits that arrive with
/// every API response. `Scripts/claude-statusline-tap.sh` saves that JSON so MaxxBar can
/// show live 5h / weekly usage without calling the rate-limited usage endpoint.
struct ClaudeStatusLineLimits: Equatable {
    struct Window: Equatable {
        var usedPercent: Double
        var resetAt: Date?
    }

    var capturedAt: Date
    var fiveHour: Window?
    var sevenDay: Window?

    static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/claude-statusline.json")
    }

    /// The tap rewrites the file on every status line update, so its modification time is the capture time.
    static func read(from url: URL = fileURL) -> ClaudeStatusLineLimits? {
        guard let data = try? Data(contentsOf: url),
              let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return nil
        }
        return parse(data, capturedAt: modified)
    }

    static func parse(_ data: Data, capturedAt: Date) -> ClaudeStatusLineLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any] else {
            return nil
        }
        func window(_ key: String) -> Window? {
            guard let payload = limits[key] as? [String: Any],
                  let used = (payload["used_percentage"] as? NSNumber)?.doubleValue,
                  used.isFinite else {
                return nil
            }
            let reset = (payload["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return Window(usedPercent: used, resetAt: reset)
        }
        let result = ClaudeStatusLineLimits(
            capturedAt: capturedAt,
            fiveHour: window("five_hour"),
            sevenDay: window("seven_day")
        )
        return result.fiveHour == nil && result.sevenDay == nil ? nil : result
    }

    /// A reset passing does not establish the new window's usage, so passed windows are dropped.
    func current(at now: Date) -> ClaudeStatusLineLimits? {
        func keep(_ window: Window?) -> Window? {
            guard let window else { return nil }
            if let reset = window.resetAt, reset <= now { return nil }
            return window
        }
        let result = ClaudeStatusLineLimits(capturedAt: capturedAt, fiveHour: keep(fiveHour), sevenDay: keep(sevenDay))
        return result.fiveHour == nil && result.sevenDay == nil ? nil : result
    }

    /// Claude Code only updates the status line while a session is active; older captures fall back to the usage endpoint.
    func isFresh(at now: Date, maxAge: TimeInterval = 1_800) -> Bool {
        now.timeIntervalSince(capturedAt) < maxAge
    }
}
