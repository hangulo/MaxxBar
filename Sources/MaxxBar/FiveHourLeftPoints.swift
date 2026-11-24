import Foundation

/// Points for a 5h line drawn under a weekly chart. The 5h window refills every few hours, often with no
/// reading in between, so when a reading's reset time passes before the next reading (or before `end`) the
/// line steps straight up to 100 at that reset instead of sloping toward the next value.
enum FiveHourLeftPoints {
    struct Reading {
        let at: Date
        let left: Int
        let resetAt: Date?
    }

    static func make(_ readings: [Reading], from start: Date, to end: Date) -> [(at: Date, left: Int)] {
        let sorted = readings.sorted { $0.at < $1.at }
        var points: [(at: Date, left: Int)] = []
        for (index, reading) in sorted.enumerated() {
            points.append((at: reading.at, left: reading.left))
            let next = index + 1 < sorted.count ? sorted[index + 1].at : end
            if let resetAt = reading.resetAt, resetAt > reading.at, resetAt < next, reading.left < 100 {
                points.append((at: resetAt, left: reading.left))
                points.append((at: resetAt, left: 100))
            }
        }
        // Keep the last point before the range so the line starts at the left edge.
        let inside = points.filter { $0.at >= start }
        guard let before = points.last(where: { $0.at < start }) else { return inside }
        return [(at: start, left: before.left)] + inside
    }
}
