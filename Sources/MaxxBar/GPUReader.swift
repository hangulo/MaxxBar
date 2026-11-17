import Foundation
import IOKit

/// GPU utilization from the IOAccelerator registry entry, the same counters Activity Monitor's GPU
/// history uses. Read in-process; no helper or privileges needed.
enum GPUReader {
    struct Reading: Equatable {
        var utilizationPercent: Int?
        var rendererPercent: Int?
        var memoryInUseBytes: UInt64?
    }

    static func read() -> Reading {
        var reading = Reading()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return reading
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            let status = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
            IOObjectRelease(entry)
            guard status == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let stats = dictionary["PerformanceStatistics"] as? [String: Any] else { continue }
            // With more than one GPU, report the busiest.
            if let device = number(stats["Device Utilization %"]), device >= (reading.utilizationPercent ?? -1) {
                reading.utilizationPercent = min(max(device, 0), 100)
                reading.rendererPercent = number(stats["Renderer Utilization %"]).map { min(max($0, 0), 100) }
                reading.memoryInUseBytes = (stats["In use system memory"] as? NSNumber)?.uint64Value
            }
        }
        return reading
    }

    private static func number(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
