import Foundation
import IOKit.hid

struct HelperSnapshot: Codable {
    var source: String
    var generatedAt: Date
    var requiresPrivileges: Bool
    var temperatures: [TemperatureSensor]
    var fans: [FanSensor]
    var cpuTemperatureCelsius: Double?
    var gpuTemperatureCelsius: Double?
    var cpuFrequencyGHz: Double?
    var gpuFrequencyGHz: Double?
    var cpuPowerWatts: Double?
    var gpuPowerWatts: Double?
    var errors: [String]
}

struct TemperatureSensor: Codable {
    var label: String
    var celsius: Double
    var rawName: String?
}

struct FanSensor: Codable {
    var label: String
    var rpm: Int
    var rawName: String?
}

@main
enum SensorHelperMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if CommandLine.arguments.contains("--probe") {
            printProbe()
            return
        }

        if let outputPath = value(after: "--write", in: arguments) {
            writeSnapshot(to: outputPath)
            return
        }

        if CommandLine.arguments.contains("--daemon") {
            runDaemon(arguments: arguments)
            return
        }

        let snapshot = SensorCollector.collect()
        print(snapshot: snapshot)
    }

    private static func runDaemon(arguments: [String]) {
        let outputPath = value(after: "--output", in: arguments) ?? "/Library/Application Support/MenuBarStats/sensors.json"
        let interval = value(after: "--interval", in: arguments).flatMap(Double.init) ?? 3

        while true {
            writeSnapshot(to: outputPath)
            Thread.sleep(forTimeInterval: max(interval, 1))
        }
    }

    private static func writeSnapshot(to outputPath: String) {
        let snapshot = SensorCollector.collect()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            let outputURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temporaryURL = outputURL.appendingPathExtension("tmp")
            try data.write(to: temporaryURL, options: .atomic)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            fputs("failed to write sensor snapshot: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func print(snapshot: HelperSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fputs("failed to encode sensor snapshot: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func printProbe() {
        for sample in HIDSensorReader.readRawSamples() {
            let value = sample.celsius.map { String(format: "%.2f C", $0) } ?? "-"
            Swift.print("\(sample.product) usagePage=\(sample.usagePage) usage=\(sample.usage) value=\(value) raw=\(sample.rawValue.map(String.init) ?? "-")")
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }

        return arguments[arguments.index(after: index)]
    }
}

enum SensorCollector {
    static func collect() -> HelperSnapshot {
        var errors: [String] = []
        let hidTemperatures = HIDSensorReader.readTemperatureSensors()
        if hidTemperatures.isEmpty {
            errors.append("No readable HID temperature sensors found.")
        }

        let powerMetrics = PowerMetricsReader.read()
        errors.append(contentsOf: powerMetrics.errors)

        let temperatures = labeledTemperatures(from: hidTemperatures)
        let cpuTemperature = averageTemperature(containing: ["CPU", "Efficiency", "Performance"], in: temperatures)
        let gpuTemperature = averageTemperature(containing: ["GPU", "Graphics"], in: temperatures)

        return HelperSnapshot(
            source: "MenuBarStatsSensorHelper",
            generatedAt: Date(),
            requiresPrivileges: powerMetrics.requiresPrivileges,
            temperatures: temperatures,
            fans: [],
            cpuTemperatureCelsius: cpuTemperature,
            gpuTemperatureCelsius: gpuTemperature,
            cpuFrequencyGHz: powerMetrics.cpuFrequencyGHz,
            gpuFrequencyGHz: powerMetrics.gpuFrequencyGHz,
            cpuPowerWatts: powerMetrics.cpuPowerWatts,
            gpuPowerWatts: powerMetrics.gpuPowerWatts,
            errors: errors
        )
    }

    private static func labeledTemperatures(from samples: [RawHIDSample]) -> [TemperatureSensor] {
        samples.compactMap { sample in
            guard let celsius = sample.celsius, celsius > -40, celsius < 130 else { return nil }
            return TemperatureSensor(label: label(for: sample.product), celsius: celsius, rawName: sample.product)
        }
    }

    private static func label(for product: String) -> String {
        let lowercased = product.lowercased()
        if lowercased.contains("battery") { return "Battery" }
        if lowercased.contains("gpu") || lowercased.contains("graphics") { return "Graphics" }
        if lowercased.contains("ssd") || lowercased.contains("nand") { return "SSD" }
        if lowercased.contains("wifi") || lowercased.contains("wi-fi") { return "Wi-Fi" }
        if lowercased.contains("palm") { return "Palm Rest" }
        if lowercased.contains("air") { return "Airflow" }
        if lowercased.contains("ecpu") || lowercased.contains("eff") { return "CPU Efficiency Cores" }
        if lowercased.contains("pcpu") || lowercased.contains("perf") { return "CPU Performance Cores" }
        return product.replacingOccurrences(of: "PMU ", with: "")
    }

    private static func averageTemperature(containing tokens: [String], in temperatures: [TemperatureSensor]) -> Double? {
        let lowered = tokens.map { $0.lowercased() }
        let matches = temperatures.filter { sensor in
            let label = sensor.label.lowercased()
            return lowered.contains { label.contains($0) }
        }
        guard !matches.isEmpty else { return nil }
        return matches.map(\.celsius).reduce(0, +) / Double(matches.count)
    }
}

struct RawHIDSample {
    var product: String
    var usagePage: Int
    var usage: Int
    var rawValue: Int?
    var celsius: Double?
}

enum HIDSensorReader {
    static func readTemperatureSensors() -> [RawHIDSample] {
        readRawSamples().filter { $0.celsius != nil }
    }

    static func readRawSamples() -> [RawHIDSample] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: 0xFF00,
            kIOHIDDeviceUsageKey: 5
        ] as CFDictionary)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { return [] }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return devices.flatMap(readSamples(from:)).sorted { lhs, rhs in
            lhs.product < rhs.product
        }
    }

    private static func readSamples(from device: IOHIDDevice) -> [RawHIDSample] {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "HID Sensor"
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return []
        }

        return elements.compactMap { element -> RawHIDSample? in
            let type = IOHIDElementGetType(element)
            guard type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Axis || type == kIOHIDElementTypeFeature else {
                return nil
            }

            var unmanagedValue: Unmanaged<IOHIDValue>!
            let result = IOHIDDeviceGetValue(device, element, &unmanagedValue)
            guard result == kIOReturnSuccess, unmanagedValue != nil else { return nil }
            let valueRef = unmanagedValue.takeUnretainedValue()

            let rawValue = IOHIDValueGetIntegerValue(valueRef)
            let usagePage = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            let celsius = decodeTemperature(rawValue: rawValue, logicalMin: IOHIDElementGetLogicalMin(element), logicalMax: IOHIDElementGetLogicalMax(element))

            return RawHIDSample(
                product: product,
                usagePage: usagePage,
                usage: usage,
                rawValue: rawValue,
                celsius: celsius
            )
        }
    }

    private static func decodeTemperature(rawValue: Int, logicalMin: CFIndex, logicalMax: CFIndex) -> Double? {
        if rawValue == 0 { return nil }

        let candidates = [
            Double(rawValue),
            Double(rawValue) / 100,
            Double(rawValue) / 256,
            Double(rawValue) / 1_000
        ]

        if logicalMin < 0 || logicalMax > 1_000 {
            return candidates.first { $0 > -40 && $0 < 130 }
        }

        return candidates.first { $0 > -40 && $0 < 130 }
    }
}

struct PowerMetricsSnapshot {
    var requiresPrivileges: Bool
    var cpuFrequencyGHz: Double?
    var gpuFrequencyGHz: Double?
    var cpuPowerWatts: Double?
    var gpuPowerWatts: Double?
    var errors: [String]
}

enum PowerMetricsReader {
    static func read() -> PowerMetricsSnapshot {
        guard getuid() == 0 else {
            return PowerMetricsSnapshot(
                requiresPrivileges: true,
                cpuFrequencyGHz: nil,
                gpuFrequencyGHz: nil,
                cpuPowerWatts: nil,
                gpuPowerWatts: nil,
                errors: ["powermetrics requires root privileges."]
            )
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        task.arguments = [
            "--samplers", "cpu_power,gpu_power,thermal",
            "-n", "1",
            "-i", "1000",
            "--show-extra-power-info"
        ]

        let output = Pipe()
        let errorOutput = Pipe()
        task.standardOutput = output
        task.standardError = errorOutput

        do {
            try task.run()
        } catch {
            return PowerMetricsSnapshot(
                requiresPrivileges: false,
                cpuFrequencyGHz: nil,
                gpuFrequencyGHz: nil,
                cpuPowerWatts: nil,
                gpuPowerWatts: nil,
                errors: ["failed to run powermetrics: \(error.localizedDescription)"]
            )
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        var errors: [String] = []
        if task.terminationStatus != 0 {
            errors.append(errorText.isEmpty ? "powermetrics exited with \(task.terminationStatus)." : errorText)
        }

        return PowerMetricsSnapshot(
            requiresPrivileges: false,
            cpuFrequencyGHz: firstGHz(in: text, patterns: ["CPU.*?([0-9]+(?:\\.[0-9]+)?)\\s*GHz", "frequency.*?([0-9]+(?:\\.[0-9]+)?)\\s*GHz"]),
            gpuFrequencyGHz: firstGHz(in: text, patterns: ["GPU.*?([0-9]+(?:\\.[0-9]+)?)\\s*GHz"]),
            cpuPowerWatts: firstWatts(in: text, patterns: ["CPU Power:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(mW|W)", "CPU.*?power.*?([0-9]+(?:\\.[0-9]+)?)\\s*(mW|W)"]),
            gpuPowerWatts: firstWatts(in: text, patterns: ["GPU Power:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(mW|W)", "GPU.*?power.*?([0-9]+(?:\\.[0-9]+)?)\\s*(mW|W)"]),
            errors: errors
        )
    }

    private static func firstGHz(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            if let match = firstMatch(in: text, pattern: pattern), let value = Double(match[1]) {
                return value
            }
        }
        return nil
    }

    private static func firstWatts(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            if let match = firstMatch(in: text, pattern: pattern), let value = Double(match[1]) {
                let unit = match.count > 2 ? match[2] : "W"
                return unit == "mW" ? value / 1_000 : value
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}
