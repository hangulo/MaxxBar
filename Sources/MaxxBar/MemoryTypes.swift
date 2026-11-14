import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

struct MemoryBreakdown: Equatable {
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var free: UInt64

    var total: UInt64 {
        app + wired + compressed + free
    }
}

struct ProcessMemory: Identifiable, Equatable {
    var id: String { "\(pid)-\(path)" }
    let pid: Int32
    let name: String
    let path: String
    let appPath: String?
    let bytes: UInt64
}

struct MemorySnapshot: Equatable {
    var pressurePercent: Int
    var usedPercent: Int
    var breakdown: MemoryBreakdown
    var processes: [ProcessMemory]
    var processRows: [ProcessMemory]
    var pageIns: UInt64
    var pageOuts: UInt64
    var cumulativePageIns: UInt64
    var cumulativePageOuts: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
}

struct SensorSnapshot: Equatable {
    var cpuTemperature: Double?
    var gpuTemperature: Double?
    var batteryTemperature: Double?
    var fanPercent: Int?
    var fanRPM: Int?
    var fanReadings: [FanReading]
    var temperatureReadings: [TemperatureReading]
    var amperage: Double?
    var power: Double?
    var voltage: Double?
    var frequencyGHz: Double?
    var lightLux: Int?
}

struct TemperatureReading: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let celsius: Double
}

struct FanReading: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let rpm: Int
}

struct CPUProcess: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let path: String
    let appPath: String?
    let cpuPercent: Double
    let rawCPUPercent: Double
}

enum CPUCoreKind: Equatable {
    case efficiency
    case performance
}

struct CPUCoreLoad: Identifiable, Equatable {
    var id: Int { index }
    let index: Int
    let kind: CPUCoreKind
    let percent: Int
}

struct CPUGPUSnapshot: Equatable {
    var cpuGHz: Double?
    var cpuTemperature: Double?
    var cpuUserPercent: Int
    var cpuSystemPercent: Int
    var cpuIdlePercent: Int
    var efficiencyPercent: Int
    var performancePercent: Int
    var coreLoads: [CPUCoreLoad]
    var processes: [CPUProcess]
    var gpuPercent: Int?
    var gpuMemoryPercent: Int?
    var gpuTemperature: Double?
    var gpuGHz: Double?
    var fps: Int?
    var loadAverages: [Double]
    var uptime: String
}

struct NetworkSample: Equatable {
    var uploadBytesPerSecond: UInt64
    var downloadBytesPerSecond: UInt64
}

struct NetworkProcess: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let path: String
    let appPath: String?
    let uploadBytesPerSecond: UInt64
    let downloadBytesPerSecond: UInt64
}

struct NetworkSnapshot: Equatable {
    var location: String
    var interfaceName: String?
    var interfaceDisplayName: String
    var publicIP: String?
    var ipAddresses: [String]
    var ethernetConnected: Bool
    var pingTarget: String
    var pingMilliseconds: Int?
    var uploadBytesPerSecond: UInt64
    var downloadBytesPerSecond: UInt64
    var history: [NetworkSample]
    var processes: [NetworkProcess]
}
