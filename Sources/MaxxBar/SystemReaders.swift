import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

enum MemoryReader {
    static func read(includeProcesses: Bool = true, precisePressure: Bool = true) -> MemorySnapshot {
        let pageSize = readPageSize()
        let vm = readVMStats()
        let free = UInt64(vm.free_count) * pageSize
        let speculative = UInt64(vm.speculative_count) * pageSize
        let fileBacked = UInt64(vm.external_page_count) * pageSize
        let wired = UInt64(vm.wire_count) * pageSize
        let compressed = UInt64(vm.compressor_page_count) * pageSize
        let total = max(ProcessInfo.processInfo.physicalMemory, 1)
        let available = min(free + speculative + fileBacked, total)
        let reserved = min(wired + compressed + available, total)
        let app = total - reserved
        let used = min(app + wired + compressed, total)
        let estimatedPressure = Int((Double(used) / Double(total) * 100).rounded())
        let pressure = precisePressure ? readPressurePercent() ?? estimatedPressure : estimatedPressure
        let usedPercent = Int((Double(used) / Double(total) * 100).rounded())
        let swap = readSwap()
        let processSnapshot = includeProcesses ? readTopProcesses() : (grouped: [ProcessMemory](), rows: [ProcessMemory]())

        return MemorySnapshot(
            pressurePercent: min(max(pressure, 0), 100),
            usedPercent: min(max(usedPercent, 0), 100),
            breakdown: MemoryBreakdown(app: app, wired: wired, compressed: compressed, free: available),
            processes: processSnapshot.grouped,
            processRows: processSnapshot.rows,
            pageIns: 0,
            pageOuts: 0,
            cumulativePageIns: UInt64(vm.pageins) * pageSize,
            cumulativePageOuts: UInt64(vm.pageouts) * pageSize,
            swapUsed: swap.used,
            swapTotal: swap.total
        )
    }

    private static func readVMStats() -> vm_statistics64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        if result != KERN_SUCCESS {
            return vm_statistics64()
        }
        return stats
    }

    private static func readPageSize() -> UInt64 {
        var pageSize = vm_size_t()
        let result = host_page_size(mach_host_self(), &pageSize)
        guard result == KERN_SUCCESS else { return 16_384 }
        return UInt64(pageSize)
    }

    private static func readTopProcesses() -> (grouped: [ProcessMemory], rows: [ProcessMemory]) {
        let pathByPID = readProcessPaths()
        let memoryByPID = readActivityMonitorMemoryByPID()
        var groupedProcesses: [String: ProcessMemory] = [:]
        var processRows: [ProcessMemory] = []

        for (pid, bytes) in memoryByPID {
            guard let path = pathByPID[pid], bytes > 0 else {
                continue
            }

            let appPath = applicationPath(forExecutablePath: path)
            let displayName = processDisplayName(pid: pid, path: path, appPath: appPath)
            let rowName = executableDisplayName(path: path)
            let key = groupingKey(name: displayName, appPath: appPath)
            processRows.append(ProcessMemory(pid: pid, name: rowName, path: path, appPath: appPath, bytes: bytes))

            if let existing = groupedProcesses[key] {
                groupedProcesses[key] = ProcessMemory(
                    pid: existing.pid,
                    name: existing.name,
                    path: existing.path,
                    appPath: existing.appPath,
                    bytes: existing.bytes + bytes
                )
            } else {
                groupedProcesses[key] = ProcessMemory(pid: pid, name: displayName, path: path, appPath: appPath, bytes: bytes)
            }
        }

        return (
            Array(groupedProcesses.values.sorted { $0.bytes > $1.bytes }.prefix(5)),
            Array(processRows.sorted { $0.bytes > $1.bytes }.prefix(5))
        )
    }

    private static func readProcessPaths() -> [Int32: String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,comm="]

        let output = Pipe()
        let errorOutput = Pipe()
        task.standardOutput = output
        task.standardError = errorOutput

        do {
            try task.run()
        } catch {
            return [:]
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var pathByPID: [Int32: String] = [:]

        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let pid = Int32(parts[0]) else {
                continue
            }

            pathByPID[pid] = String(parts[1])
        }

        return pathByPID
    }

    private static func readActivityMonitorMemoryByPID() -> [Int32: UInt64] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        task.arguments = ["-l", "1", "-stats", "pid,mem", "-o", "mem"]

        let output = Pipe()
        task.standardOutput = output

        do {
            try task.run()
        } catch {
            return [:]
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var memoryByPID: [Int32: UInt64] = [:]

        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let bytes = parseTopMemory(String(parts[1])) else {
                continue
            }

            memoryByPID[pid] = bytes
        }

        return memoryByPID
    }

    private static func parseTopMemory(_ value: String) -> UInt64? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let suffix = trimmed.last else { return nil }
        let numberText = String(trimmed.dropLast())
        guard let number = Double(numberText) else { return nil }

        switch suffix {
        case "K":
            return UInt64(number * 1_000)
        case "M":
            return UInt64(number * 1_000_000)
        case "G":
            return UInt64(number * 1_000_000_000)
        default:
            return UInt64(trimmed)
        }
    }

    private static func readPressurePercent() -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/memory_pressure")
        task.arguments = ["-Q"]

        let output = Pipe()
        task.standardOutput = output

        do {
            try task.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.contains("System-wide memory free percentage") }),
              let rawPercent = line.split(separator: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "%")),
              let freePercent = Int(rawPercent) else {
            return nil
        }

        return 100 - freePercent
    }

    static func processDisplayName(pid: Int32, path: String, appPath: String?) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName,
           !name.isEmpty {
            return name
        }

        if let appPath {
            return URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        }

        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static func executableDisplayName(path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static func applicationPath(forExecutablePath path: String) -> String? {
        guard let appRange = path.range(of: ".app", options: [.caseInsensitive]) else {
            return nil
        }

        return String(path[..<appRange.upperBound])
    }

    private static func groupingKey(name: String, appPath: String?) -> String {
        if let appPath {
            return appPath
        }

        return name
    }

    private static func readSwap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }
}

enum SensorReader {
    static func read() -> SensorSnapshot {
        let battery = readBatteryTelemetry()
        let native = NativeSensorCache.read()
        let smc = LocalSMCSensors()
        let batteryTemperature = battery.temperatureCelsius ?? native?.temperature(label: "Battery")
        let nativeFans = native?.fanReadings ?? []
        let fanReadings = nativeFans.isEmpty
            ? (smc?.fanSpeeds ?? []).enumerated().map { FanReading(label: "Fan \($0.offset + 1)", rpm: $0.element) }
            : nativeFans
        let maxFanRPM = fanReadings.map(\.rpm).max()
        let fanPercent = maxFanRPM.map { $0 > 0 ? 100 : 0 }
        let preferredTemperatures = native?.temperatureReadings ?? []
        let temperatureReadings = preferredTemperatures.isEmpty
            ? batteryTemperature.map { [TemperatureReading(label: "Battery", celsius: $0)] } ?? []
            : preferredTemperatures.map { reading in
                reading.label == "Battery" && batteryTemperature != nil
                    ? TemperatureReading(label: reading.label, celsius: batteryTemperature!)
                    : reading
            }

        return SensorSnapshot(
            cpuTemperature: native?.cpuTemperatureCelsius ?? smc?.cpuTemperature,
            gpuTemperature: native?.gpuTemperatureCelsius ?? smc?.gpuTemperature,
            batteryTemperature: batteryTemperature,
            fanPercent: fanPercent,
            fanRPM: maxFanRPM,
            fanReadings: fanReadings,
            temperatureReadings: temperatureReadings,
            amperage: battery.systemCurrentAmps,
            power: battery.systemPowerWatts ?? battery.adapterPowerWatts,
            voltage: battery.systemVoltageVolts ?? battery.batteryVoltageVolts,
            frequencyGHz: native?.cpuFrequencyGHz ?? CPUReader.currentFrequencyGHz(),
            lightLux: nil
        )
    }

    private struct BatteryTelemetry {
        var temperatureCelsius: Double?
        var systemCurrentAmps: Double?
        var systemPowerWatts: Double?
        var systemVoltageVolts: Double?
        var batteryVoltageVolts: Double?
        var adapterPowerWatts: Double?
    }

    private static func readBatteryTelemetry() -> BatteryTelemetry {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-r", "-n", "AppleSmartBattery"]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return BatteryTelemetry()
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return BatteryTelemetry()
        }

        return BatteryTelemetry(
            temperatureCelsius: integerValue(for: "Temperature", in: text).map { Double($0) / 100 },
            systemCurrentAmps: integerValue(for: "SystemCurrentIn", in: text).map { Double($0) / 1_000 },
            systemPowerWatts: integerValue(for: "SystemPowerIn", in: text).map { Double($0) / 1_000 },
            systemVoltageVolts: integerValue(for: "SystemVoltageIn", in: text).map { Double($0) / 1_000 },
            batteryVoltageVolts: integerValue(for: "Voltage", in: text).map { Double($0) / 1_000 },
            adapterPowerWatts: adapterWatts(in: text).map(Double.init)
        )
    }

    private static func integerValue(for key: String, in text: String) -> Int? {
        guard let keyRange = text.range(of: "\"\(key)\"") else { return nil }
        let remainder = text[keyRange.upperBound...]
        guard let equals = remainder.firstIndex(of: "=") else { return nil }
        let afterEquals = remainder[remainder.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let sign = afterEquals.first == "-" ? "-" : ""
        let digits = afterEquals.dropFirst(sign.isEmpty ? 0 : 1).prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(sign + String(digits))
    }

    private static func adapterWatts(in text: String) -> Int? {
        guard let adapterRange = text.range(of: "\"AdapterDetails\"") ?? text.range(of: "\"AppleRawAdapterDetails\"") else {
            return nil
        }

        let remainder = text[adapterRange.upperBound...]
        guard let wattsRange = remainder.range(of: "\"Watts\"") else {
            return nil
        }

        return integerValue(for: "Watts", in: String(remainder[wattsRange.lowerBound...]))
    }
}

private struct NativeSensorCache: Codable {
    struct Temperature: Codable {
        let label: String
        let celsius: Double
        let rawName: String?
    }

    struct Fan: Codable {
        let label: String
        let rpm: Int
        let rawName: String?
    }

    let source: String
    let generatedAt: Date?
    let requiresPrivileges: Bool
    let temperatures: [Temperature]
    let fans: [Fan]
    let cpuTemperatureCelsius: Double?
    let gpuTemperatureCelsius: Double?
    let cpuFrequencyGHz: Double?
    let gpuFrequencyGHz: Double?
    let cpuPowerWatts: Double?
    let gpuPowerWatts: Double?
    let errors: [String]

    var temperatureReadings: [TemperatureReading] {
        temperatures
            .filter { $0.celsius > -40 && $0.celsius < 130 }
            .map { TemperatureReading(label: $0.label, celsius: $0.celsius) }
    }

    var fanReadings: [FanReading] {
        fans
            .filter { $0.rpm >= 0 && $0.rpm < 10_000 }
            .map { FanReading(label: $0.label, rpm: $0.rpm) }
    }

    func temperature(label: String) -> Double? {
        temperatureReadings.first { $0.label == label }?.celsius
    }

    static func read() -> NativeSensorCache? {
        let path = "/Library/Application Support/MaxxBar/sensors.json"
        let url = URL(fileURLWithPath: path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 30,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(NativeSensorCache.self, from: data)
    }
}
