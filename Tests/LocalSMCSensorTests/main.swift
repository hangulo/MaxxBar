import Foundation
// Physical-unit fixtures cover the byte order and fixed-point scaling used by hardware.
assert(LocalSMCSensors.decode(type: 0x66706532, bytes: [0x17, 0x70]) == 1500)
assert(LocalSMCSensors.decode(type: 0x66706532, bytes: [0, 0]) == 0)
assert(LocalSMCSensors.decode(type: 0x73703738, bytes: [0x41, 0x80]) == 65.5)
assert(LocalSMCSensors.decode(type: 0x73703738, bytes: [0xff, 0x80]) == -0.5)
let cpu: Float = 65.5
assert(LocalSMCSensors.decode(type: 0x666c7420, bytes: withUnsafeBytes(of: cpu, Array.init)) == 65.5)
let invalid: Float = .nan
assert(LocalSMCSensors.decode(type: 0x666c7420, bytes: withUnsafeBytes(of: invalid, Array.init)) == nil)
assert(LocalSMCSensors.decode(type: 0x666c7420, bytes: [0]) == nil)
assert(LocalSMCSensors.decode(type: 0x73703738, bytes: []) == nil)
assert(LocalSMCSensors.decode(type: 0, bytes: [1, 2]) == nil)
print("Sensor decoding checks passed")
