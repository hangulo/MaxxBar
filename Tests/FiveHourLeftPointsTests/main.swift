import Foundation

let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3_600) }
func reading(_ hours: Double, _ left: Int, reset: Double?) -> FiveHourLeftPoints.Reading {
    FiveHourLeftPoints.Reading(at: at(hours), left: left, resetAt: reset.map(at))
}

// Readings inside one window are drawn as they are.
let plain = FiveHourLeftPoints.make([reading(0, 90, reset: 4), reading(1, 70, reset: 4)], from: at(0), to: at(2))
assert(plain.map(\.left) == [90, 70])

// A reset between two readings steps up to 100 at the reset time, not along a slope.
let stepped = FiveHourLeftPoints.make([reading(0, 40, reset: 2), reading(3, 95, reset: 7)], from: at(0), to: at(4))
assert(stepped.map(\.left) == [40, 40, 100, 95])
assert(stepped[1].at == at(2) && stepped[2].at == at(2))

// A reset that passed after the last reading also steps up before now.
let tail = FiveHourLeftPoints.make([reading(0, 10, reset: 1)], from: at(0), to: at(3))
assert(tail.map(\.left) == [10, 10, 100])

// A full window does not add a step, and an unknown reset adds nothing.
assert(FiveHourLeftPoints.make([reading(0, 100, reset: 1)], from: at(0), to: at(3)).count == 1)
assert(FiveHourLeftPoints.make([reading(0, 50, reset: nil)], from: at(0), to: at(3)).count == 1)

// The last point before the range is carried to the left edge.
let edge = FiveHourLeftPoints.make([reading(-3, 20, reset: -1), reading(1, 80, reset: 4)], from: at(0), to: at(2))
assert(edge.first.map { $0.at == at(0) && $0.left == 100 } == true)
assert(edge.map(\.left) == [100, 80])

print("5h line checks passed")
