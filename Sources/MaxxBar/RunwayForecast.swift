import Foundation

/// When a quota window runs out at the current burn rate, if that happens before the window resets.
enum RunwayForecast {
    struct Reading {
        let at: Date
        let remainingPercent: Int
        let resetAt: Date?
        let plan: String?
    }

    /// Readings of one window, oldest first, ending with the current one. Only readings from the current
    /// window and plan are used: a reset or a plan change rescales the percentages, so a rate cannot cross it.
    /// `minimumSpan` keeps a couple of close readings from producing a wild rate.
    static func emptyAt(_ readings: [Reading], minimumSpan: TimeInterval) -> Date? {
        guard let current = readings.last, let resetAt = current.resetAt, current.remainingPercent > 0 else {
            return nil
        }
        var start = current
        for reading in readings.reversed().dropFirst() {
            guard let readingReset = reading.resetAt,
                  abs(readingReset.timeIntervalSince(resetAt)) < 120,
                  reading.plan == current.plan,
                  // Usage only goes down within a window; a rise means a new window or plan.
                  reading.remainingPercent >= start.remainingPercent else { break }
            start = reading
        }
        let span = current.at.timeIntervalSince(start.at)
        let used = start.remainingPercent - current.remainingPercent
        guard span >= minimumSpan, used > 0 else { return nil }
        let secondsLeft = Double(current.remainingPercent) / (Double(used) / span)
        let emptyAt = current.at.addingTimeInterval(secondsLeft)
        return emptyAt < resetAt ? emptyAt : nil
    }
}
