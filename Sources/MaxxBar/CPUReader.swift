import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

enum CPUReader {
    struct CoreTicks: Equatable {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    struct CPULoadInfo {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
        let coreTicks: [CoreTicks]
    }

    static func read(previous: CPULoadInfo?, sensors: SensorSnapshot = .empty) -> (snapshot: CPUGPUSnapshot, current: CPULoadInfo?) {
        let current = currentCPULoad()
        let percentages = cpuPercentages(previous: previous, current: current)
        let active = percentages.user + percentages.system
        let coreLoads = current.map { makeCoreLoads(previous: previous?.coreTicks, current: $0.coreTicks) } ?? emptyCoreLoads()
        let clusterPercentages = clusterPercentages(from: coreLoads)

        let snapshot = CPUGPUSnapshot(
            cpuGHz: sensors.frequencyGHz ?? currentFrequencyGHz(),
            cpuTemperature: sensors.cpuTemperature,
            cpuUserPercent: percentages.user,
            cpuSystemPercent: percentages.system,
            cpuIdlePercent: percentages.idle,
            efficiencyPercent: clusterPercentages.efficiency ?? min(max(active, 0), 100),
            performancePercent: clusterPercentages.performance ?? min(max(active, 0), 100),
            coreLoads: coreLoads,
            processes: readTopCPUProcesses(),
            gpuPercent: nil,
            gpuMemoryPercent: nil,
            gpuTemperature: sensors.gpuTemperature,
            gpuGHz: nil,
            fps: nil,
            loadAverages: loadAverages(),
            uptime: uptime()
        )

        return (snapshot, current)
    }

    static func emptyCoreLoads() -> [CPUCoreLoad] {
        let efficiencyCount = efficiencyCoreCount()
        let total = max(logicalCPUCount(), efficiencyCount)
        guard total > 0 else { return [] }
        return (0..<total).map { index in
            CPUCoreLoad(
                index: index,
                kind: index < efficiencyCount ? .efficiency : .performance,
                percent: 0
            )
        }
    }

    static func currentFrequencyGHz() -> Double? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        let result = sysctlbyname("hw.cpufrequency", &value, &size, nil, 0)
        guard result == 0, value > 0 else { return nil }
        return Double(value) / 1_000_000_000
    }

    static func loadAverages() -> [Double] {
        var averages = [Double](repeating: 0, count: 3)
        let count = getloadavg(&averages, 3)
        guard count > 0 else { return [0, 0, 0] }
        return averages
    }

    static func uptime() -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let result = sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0)
        guard result == 0 else { return "-" }

        let elapsed = Int(Date().timeIntervalSince1970) - bootTime.tv_sec
        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        if days > 0 {
            return "\(days) days, \(hours) hours"
        }
        return "\(hours) hours"
    }

    private static func currentCPULoad() -> CPULoadInfo? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return CPULoadInfo(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3,
            coreTicks: currentCoreTicks()
        )
    }

    private static func currentCoreTicks() -> [CoreTicks] {
        var processorInfo: processor_info_array_t?
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else { return [] }
        defer {
            let byteCount = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: processorInfo), byteCount)
        }

        let cpuInfoStride = Int(CPU_STATE_MAX)
        let buffer = UnsafeBufferPointer(start: processorInfo, count: Int(infoCount))
        var ticks: [CoreTicks] = []
        ticks.reserveCapacity(Int(processorCount))

        for index in 0..<Int(processorCount) {
            let base = index * cpuInfoStride
            guard base + Int(CPU_STATE_NICE) < buffer.count else { break }
            ticks.append(
                CoreTicks(
                    user: UInt32(buffer[base + Int(CPU_STATE_USER)]),
                    system: UInt32(buffer[base + Int(CPU_STATE_SYSTEM)]),
                    idle: UInt32(buffer[base + Int(CPU_STATE_IDLE)]),
                    nice: UInt32(buffer[base + Int(CPU_STATE_NICE)])
                )
            )
        }

        return ticks
    }

    private static func cpuPercentages(previous: CPULoadInfo?, current: CPULoadInfo?) -> (user: Int, system: Int, idle: Int) {
        guard let previous, let current else {
            return (0, 0, 100)
        }

        let user = Int(current.user &- previous.user)
        let system = Int(current.system &- previous.system)
        let idle = Int(current.idle &- previous.idle)
        let nice = Int(current.nice &- previous.nice)
        let total = max(user + system + idle + nice, 1)
        return (
            Int((Double(user + nice) / Double(total) * 100).rounded()),
            Int((Double(system) / Double(total) * 100).rounded()),
            Int((Double(idle) / Double(total) * 100).rounded())
        )
    }

    private static func makeCoreLoads(previous: [CoreTicks]?, current: [CoreTicks]) -> [CPUCoreLoad] {
        guard !current.isEmpty else { return emptyCoreLoads() }
        let efficiencyCount = efficiencyCoreCount()
        let previous = previous ?? []

        return current.enumerated().map { index, currentTicks in
            let percent: Int
            if previous.indices.contains(index) {
                let previousTicks = previous[index]
                let user = Int(currentTicks.user &- previousTicks.user)
                let system = Int(currentTicks.system &- previousTicks.system)
                let idle = Int(currentTicks.idle &- previousTicks.idle)
                let nice = Int(currentTicks.nice &- previousTicks.nice)
                let total = max(user + system + idle + nice, 1)
                percent = Int((Double(user + system + nice) / Double(total) * 100).rounded())
            } else {
                percent = 0
            }

            return CPUCoreLoad(
                index: index,
                kind: index < efficiencyCount ? .efficiency : .performance,
                percent: min(max(percent, 0), 100)
            )
        }
    }

    private static func clusterPercentages(from coreLoads: [CPUCoreLoad]) -> (efficiency: Int?, performance: Int?) {
        func average(for kind: CPUCoreKind) -> Int? {
            let loads = coreLoads.filter { $0.kind == kind }.map(\.percent)
            guard !loads.isEmpty else { return nil }
            return Int((Double(loads.reduce(0, +)) / Double(loads.count)).rounded())
        }

        return (average(for: .efficiency), average(for: .performance))
    }

    private static func readTopCPUProcesses() -> [CPUProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,comm="]
        let output = Pipe()
        task.standardOutput = output

        do {
            try task.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var grouped: [String: CPUProcess] = [:]
        let normalizer = max(Double(logicalCPUCount()), 1)

        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]) else {
                continue
            }

            let path = String(parts[2])
            let appPath = MemoryReader.applicationPath(forExecutablePath: path)
            let name = MemoryReader.processDisplayName(pid: pid, path: path, appPath: appPath)
            let key = appPath ?? name
            let normalizedCPU = cpu / normalizer
            if let existing = grouped[key] {
                grouped[key] = CPUProcess(
                    name: existing.name,
                    path: existing.path,
                    appPath: existing.appPath,
                    cpuPercent: existing.cpuPercent + normalizedCPU,
                    rawCPUPercent: existing.rawCPUPercent + cpu
                )
            } else {
                grouped[key] = CPUProcess(
                    name: name,
                    path: path,
                    appPath: appPath,
                    cpuPercent: normalizedCPU,
                    rawCPUPercent: cpu
                )
            }
        }

        return Array(grouped.values.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
    }

    private static func efficiencyCoreCount() -> Int {
        for level in 0...3 {
            guard let name = sysctlString("hw.perflevel\(level).name"),
                  name.localizedCaseInsensitiveContains("Efficiency") else {
                continue
            }

            let count = sysctlInt("hw.perflevel\(level).logicalcpu")
            if count > 0 {
                return count
            }
        }

        return 0
    }

    private static func sysctlInt(_ name: String) -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        if sysctlbyname(name, &count, &size, nil, 0) == 0, count > 0 {
            return Int(count)
        }

        return 0
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func logicalCPUCount() -> Int {
        let count = sysctlInt("hw.logicalcpu")
        if count > 0 {
            return count
        }

        return max(ProcessInfo.processInfo.processorCount, 1)
    }
}

enum ByteFormat {
    static func memory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }

        let mb = Double(bytes) / 1_000_000
        if mb >= 1 {
            return String(format: "%.0f MB", mb)
        }

        let kb = Double(bytes) / 1_000
        return String(format: "%.0f KB", kb)
    }
}
