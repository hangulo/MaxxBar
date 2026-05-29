import Darwin
import AppKit
import Foundation
import MachO

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

struct LLMUsageWindow: Equatable {
    var label: String
    var usedPercent: Int
    var remainingPercent: Int
    var resetAt: Date?
    var windowSeconds: Int
}

struct LLMUsageLimit: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var primary: LLMUsageWindow?
    var secondary: LLMUsageWindow?
}

struct LLMLocalUsageWindow: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var tokens: UInt64
    var threads: Int
}

struct LLMUsageSession: Identifiable, Equatable {
    var id: String
    var title: String
    var projectName: String
    var modelName: String
    var preview: String
    var rolloutPath: String
    var tokens: UInt64
    var updatedAt: Date?

    var detail: String {
        "\(projectName) • \(modelName)"
    }
}

struct LLMQuotaHistorySample: Identifiable, Equatable {
    var id = UUID()
    var sampledAt: Date
    var primaryRemainingPercent: Int?
    var weeklyRemainingPercent: Int?
}

struct LLMUsageSnapshot: Equatable {
    var email: String?
    var planType: String?
    var limits: [LLMUsageLimit]
    var creditsBalance: String?
    var lastUpdated: Date?
    var localFiveHourTokens: UInt64
    var localWeeklyTokens: UInt64
    var localWeeklyThreads: Int
    var localWindows: [LLMLocalUsageWindow]
    var recentSessions: [LLMUsageSession]
    var topWeeklySessions: [LLMUsageSession]
    var error: String?
}

@MainActor
final class MemoryModel: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot(
        pressurePercent: 0,
        usedPercent: 0,
        breakdown: MemoryBreakdown(app: 0, wired: 0, compressed: 0, free: 0),
        processes: [],
        processRows: [],
        pageIns: 0,
        pageOuts: 0,
        cumulativePageIns: 0,
        cumulativePageOuts: 0,
        swapUsed: 0,
        swapTotal: 0
    )
    @Published private(set) var history: [MemoryBreakdown] = []
    @Published private(set) var sensors = SensorSnapshot.empty
    @Published private(set) var cpuGPU = CPUGPUSnapshot.empty
    @Published private(set) var network = NetworkSnapshot.empty
    @Published private(set) var llmUsage = LLMUsageSnapshot.empty
    @Published private(set) var llmQuotaHistory: [LLMQuotaHistorySample] = []
    private var previousCumulativePageIns: UInt64?
    private var previousCumulativePageOuts: UInt64?
    private var previousCPUInfo: CPUReader.CPULoadInfo?
    private var previousNetworkCounters: NetworkReader.NetworkCounters?
    private var networkHistory: [NetworkSample] = []
    private var previousLLMUsageRefresh: Date?
    private var previousLLMQuotaSample: Date?
    private var isRefreshing = false

    init() {}

    init(
        snapshot: MemorySnapshot,
        history: [MemoryBreakdown],
        network: NetworkSnapshot = .demo,
        llmUsage: LLMUsageSnapshot = .demo,
        llmQuotaHistory: [LLMQuotaHistorySample] = .demo
    ) {
        self.snapshot = snapshot
        self.history = history
        self.network = network
        self.llmUsage = llmUsage
        self.llmQuotaHistory = llmQuotaHistory
    }

    func refresh() {
        let stats = MemoryReader.read()
        var displayStats = stats
        displayStats.pageIns = delta(from: previousCumulativePageIns, to: stats.cumulativePageIns)
        displayStats.pageOuts = delta(from: previousCumulativePageOuts, to: stats.cumulativePageOuts)
        previousCumulativePageIns = stats.cumulativePageIns
        previousCumulativePageOuts = stats.cumulativePageOuts
        snapshot = displayStats
        sensors = SensorReader.read()
        let cpuResult = CPUReader.read(previous: previousCPUInfo, sensors: sensors)
        previousCPUInfo = cpuResult.current
        cpuGPU = cpuResult.snapshot
        let networkResult = NetworkReader.read(previous: previousNetworkCounters, history: networkHistory)
        previousNetworkCounters = networkResult.counters
        networkHistory = networkResult.snapshot.history
        network = networkResult.snapshot
        llmUsage = LLMUsageReader.read()
        previousLLMUsageRefresh = Date()
        sampleLLMQuotaIfNeeded(force: true)
        history.append(stats.breakdown)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }

    func refreshInBackground(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard !isRefreshing else { return }
        isRefreshing = true

        let previousPageIns = previousCumulativePageIns
        let previousPageOuts = previousCumulativePageOuts
        let previousCPUInfo = previousCPUInfo
        let previousNetworkCounters = previousNetworkCounters
        let networkHistory = networkHistory
        let previousLLMUsage = llmUsage
        let previousLLMUsageRefresh = previousLLMUsageRefresh

        DispatchQueue.global(qos: .utility).async {
            let result = Self.collectRefresh(
                previousPageIns: previousPageIns,
                previousPageOuts: previousPageOuts,
                previousCPUInfo: previousCPUInfo,
                previousNetworkCounters: previousNetworkCounters,
                networkHistory: networkHistory,
                previousLLMUsage: previousLLMUsage,
                previousLLMUsageRefresh: previousLLMUsageRefresh
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apply(result)
                self.isRefreshing = false
                completion?()
            }
        }
    }

    private struct RefreshResult {
        let stats: MemorySnapshot
        let displayStats: MemorySnapshot
        let sensors: SensorSnapshot
        let cpuResult: (snapshot: CPUGPUSnapshot, current: CPUReader.CPULoadInfo?)
        let networkResult: (snapshot: NetworkSnapshot, counters: NetworkReader.NetworkCounters?)
        let llmUsage: LLMUsageSnapshot
        let llmUsageRefresh: Date?
    }

    nonisolated private static func collectRefresh(
        previousPageIns: UInt64?,
        previousPageOuts: UInt64?,
        previousCPUInfo: CPUReader.CPULoadInfo?,
        previousNetworkCounters: NetworkReader.NetworkCounters?,
        networkHistory: [NetworkSample],
        previousLLMUsage: LLMUsageSnapshot,
        previousLLMUsageRefresh: Date?
    ) -> RefreshResult {
        let stats = MemoryReader.read()
        var displayStats = stats
        displayStats.pageIns = deltaValue(from: previousPageIns, to: stats.cumulativePageIns)
        displayStats.pageOuts = deltaValue(from: previousPageOuts, to: stats.cumulativePageOuts)
        let sensors = SensorReader.read()
        let cpuResult = CPUReader.read(previous: previousCPUInfo, sensors: sensors)
        let networkResult = NetworkReader.read(previous: previousNetworkCounters, history: networkHistory)
        let shouldRefreshLLMUsage = previousLLMUsageRefresh.map { Date().timeIntervalSince($0) > 60 } ?? true
        let llmUsage = shouldRefreshLLMUsage ? LLMUsageReader.read() : previousLLMUsage

        return RefreshResult(
            stats: stats,
            displayStats: displayStats,
            sensors: sensors,
            cpuResult: cpuResult,
            networkResult: networkResult,
            llmUsage: llmUsage,
            llmUsageRefresh: shouldRefreshLLMUsage ? Date() : previousLLMUsageRefresh
        )
    }

    private func apply(_ result: RefreshResult) {
        previousCumulativePageIns = result.stats.cumulativePageIns
        previousCumulativePageOuts = result.stats.cumulativePageOuts
        snapshot = result.displayStats
        sensors = result.sensors
        previousCPUInfo = result.cpuResult.current
        cpuGPU = result.cpuResult.snapshot
        previousNetworkCounters = result.networkResult.counters
        networkHistory = result.networkResult.snapshot.history
        network = result.networkResult.snapshot
        llmUsage = result.llmUsage
        previousLLMUsageRefresh = result.llmUsageRefresh
        sampleLLMQuotaIfNeeded()
        history.append(result.stats.breakdown)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }

    private func delta(from previous: UInt64?, to current: UInt64) -> UInt64 {
        guard let previous, current >= previous else { return 0 }
        return current - previous
    }

    nonisolated private static func deltaValue(from previous: UInt64?, to current: UInt64) -> UInt64 {
        guard let previous, current >= previous else { return 0 }
        return current - previous
    }

    private func sampleLLMQuotaIfNeeded(force: Bool = false) {
        guard let limit = llmUsage.limits.first(where: { $0.name == "Codex" }) ?? llmUsage.limits.first else { return }
        let now = Date()
        if !force,
           let previousLLMQuotaSample,
           now.timeIntervalSince(previousLLMQuotaSample) < llmQuotaSampleInterval {
            return
        }

        llmQuotaHistory.append(
            LLMQuotaHistorySample(
                sampledAt: now,
                primaryRemainingPercent: limit.primary?.remainingPercent,
                weeklyRemainingPercent: limit.secondary?.remainingPercent
            )
        )
        previousLLMQuotaSample = now

        if llmQuotaHistory.count > 144 {
            llmQuotaHistory.removeFirst(llmQuotaHistory.count - 144)
        }
    }

    private var llmQuotaSampleInterval: TimeInterval {
        if llmQuotaHistory.count < 5 {
            return 60
        }
        if llmQuotaHistory.count < 12 {
            return 300
        }
        return 600
    }
}

extension NetworkSnapshot {
    static let empty = NetworkSnapshot(
        location: "Automatic",
        interfaceName: nil,
        interfaceDisplayName: "Not Connected",
        publicIP: nil,
        ipAddresses: [],
        ethernetConnected: false,
        pingTarget: "istatmenus.app",
        pingMilliseconds: nil,
        uploadBytesPerSecond: 0,
        downloadBytesPerSecond: 0,
        history: Array(repeating: NetworkSample(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0), count: 48),
        processes: []
    )

    static var demo: NetworkSnapshot {
        var samples: [NetworkSample] = []
        for index in 0..<48 {
            let upload = UInt64(80_000 + (index * 37 % 140) * 3_000)
            let download = UInt64(70_000 + (index * 53 % 160) * 3_200)
            samples.append(NetworkSample(uploadBytesPerSecond: upload, downloadBytesPerSecond: download))
        }

        return NetworkSnapshot(
            location: "Automatic",
            interfaceName: "en0",
            interfaceDisplayName: "AirPort Network",
            publicIP: "11.22.33.44",
            ipAddresses: ["192.168.6.36"],
            ethernetConnected: false,
            pingTarget: "istatmenus.app",
            pingMilliseconds: 22,
            uploadBytesPerSecond: 467_000,
            downloadBytesPerSecond: 496_000,
            history: samples,
            processes: [
                NetworkProcess(name: "macOS", path: "/System/Library/CoreServices/Finder.app", appPath: "/System/Library/CoreServices/Finder.app", uploadBytesPerSecond: 8_800_000, downloadBytesPerSecond: 8_800_000),
                NetworkProcess(name: "Safari", path: "/Applications/Safari.app", appPath: "/Applications/Safari.app", uploadBytesPerSecond: 120_000, downloadBytesPerSecond: 540_000)
            ]
        )
    }
}

extension Array where Element == LLMQuotaHistorySample {
    static let demo: [LLMQuotaHistorySample] = [
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-2_400), primaryRemainingPercent: 48, weeklyRemainingPercent: 84),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-1_800), primaryRemainingPercent: 46, weeklyRemainingPercent: 83),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-1_200), primaryRemainingPercent: 44, weeklyRemainingPercent: 82),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-600), primaryRemainingPercent: 42, weeklyRemainingPercent: 81),
        LLMQuotaHistorySample(sampledAt: Date(), primaryRemainingPercent: 42, weeklyRemainingPercent: 81)
    ]
}

extension LLMUsageSnapshot {
    static let empty = LLMUsageSnapshot(
        email: nil,
        planType: nil,
        limits: [],
        creditsBalance: nil,
        lastUpdated: nil,
        localFiveHourTokens: 0,
        localWeeklyTokens: 0,
        localWeeklyThreads: 0,
        localWindows: [],
        recentSessions: [],
        topWeeklySessions: [],
        error: nil
    )

    static let demo = LLMUsageSnapshot(
        email: "you@example.com",
        planType: "prolite",
        limits: [
            LLMUsageLimit(
                name: "Codex",
                primary: LLMUsageWindow(label: "5h", usedPercent: 58, remainingPercent: 42, resetAt: Date().addingTimeInterval(4_860), windowSeconds: 18_000),
                secondary: LLMUsageWindow(label: "Weekly", usedPercent: 19, remainingPercent: 81, resetAt: Date().addingTimeInterval(255_000), windowSeconds: 604_800)
            )
        ],
        creditsBalance: "0",
        lastUpdated: Date(),
        localFiveHourTokens: 200_670_848,
        localWeeklyTokens: 216_176_212,
        localWeeklyThreads: 17,
        localWindows: [
            LLMLocalUsageWindow(label: "1h", tokens: 24_100_000, threads: 2),
            LLMLocalUsageWindow(label: "5h", tokens: 200_670_848, threads: 6),
            LLMLocalUsageWindow(label: "24h", tokens: 208_400_000, threads: 9),
            LLMLocalUsageWindow(label: "7d", tokens: 216_176_212, threads: 17)
        ],
        recentSessions: [
            LLMUsageSession(
                id: "demo-1",
                title: "MenuBarStats LLM usage tab",
                projectName: "Menu bar stats",
                modelName: "GPT-5 Codex",
                preview: "Added usage windows and advanced local session detail.",
                rolloutPath: "",
                tokens: 84_200_000,
                updatedAt: Date().addingTimeInterval(-420)
            ),
            LLMUsageSession(
                id: "demo-2",
                title: "Sensor helper",
                projectName: "Menu bar stats",
                modelName: "GPT-5 Codex",
                preview: "Built native helper for thermal and fan data.",
                rolloutPath: "",
                tokens: 31_500_000,
                updatedAt: Date().addingTimeInterval(-7_200)
            )
        ],
        topWeeklySessions: [
            LLMUsageSession(
                id: "demo-1",
                title: "MenuBarStats LLM usage tab",
                projectName: "Menu bar stats",
                modelName: "GPT-5 Codex",
                preview: "Added usage windows and advanced local session detail.",
                rolloutPath: "",
                tokens: 84_200_000,
                updatedAt: Date().addingTimeInterval(-420)
            ),
            LLMUsageSession(
                id: "demo-3",
                title: "CPU/GPU panel",
                projectName: "Menu bar stats",
                modelName: "GPT-5 Codex",
                preview: "Compared CPU and GPU data with iStat style panels.",
                rolloutPath: "",
                tokens: 58_700_000,
                updatedAt: Date().addingTimeInterval(-86_400)
            )
        ],
        error: nil
    )
}

extension SensorSnapshot {
    static let empty = SensorSnapshot(
        cpuTemperature: nil,
        gpuTemperature: nil,
        batteryTemperature: nil,
        fanPercent: nil,
        fanRPM: nil,
        fanReadings: [],
        temperatureReadings: [],
        amperage: nil,
        power: nil,
        voltage: nil,
        frequencyGHz: CPUReader.currentFrequencyGHz(),
        lightLux: nil
    )
}

extension CPUGPUSnapshot {
    static let empty = CPUGPUSnapshot(
        cpuGHz: CPUReader.currentFrequencyGHz(),
        cpuTemperature: nil,
        cpuUserPercent: 0,
        cpuSystemPercent: 0,
        cpuIdlePercent: 100,
        efficiencyPercent: 0,
        performancePercent: 0,
        coreLoads: CPUReader.emptyCoreLoads(),
        processes: [],
        gpuPercent: nil,
        gpuMemoryPercent: nil,
        gpuTemperature: nil,
        gpuGHz: nil,
        fps: nil,
        loadAverages: CPUReader.loadAverages(),
        uptime: CPUReader.uptime()
    )
}

extension MemorySnapshot {
    static let demo = MemorySnapshot(
        pressurePercent: 14,
        usedPercent: 65,
        breakdown: MemoryBreakdown(
            app: 18_400_000_000,
            wired: 2_800_000_000,
            compressed: 1_500_000_000,
            free: 13_300_000_000
        ),
        processes: [
            ProcessMemory(pid: 101, name: "Google Chrome", path: "/Applications/Google Chrome.app", appPath: "/Applications/Google Chrome.app", bytes: 5_300_000_000),
            ProcessMemory(pid: 102, name: "WindowServer", path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", appPath: nil, bytes: 1_000_000_000),
            ProcessMemory(pid: 103, name: "Codex", path: "/Applications/Codex.app", appPath: "/Applications/Codex.app", bytes: 872_000_000),
            ProcessMemory(pid: 104, name: "Notes", path: "/System/Applications/Notes.app", appPath: "/System/Applications/Notes.app", bytes: 328_000_000),
            ProcessMemory(pid: 105, name: "Messages", path: "/System/Applications/Messages.app", appPath: "/System/Applications/Messages.app", bytes: 290_000_000)
        ],
        processRows: [
            ProcessMemory(pid: 201, name: "Google Chrome Helper", path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper", appPath: "/Applications/Google Chrome.app", bytes: 615_900_000),
            ProcessMemory(pid: 202, name: "Google Chrome Helper (Renderer)", path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", appPath: "/Applications/Google Chrome.app", bytes: 607_000_000),
            ProcessMemory(pid: 203, name: "Google Chrome", path: "/Applications/Google Chrome.app", appPath: "/Applications/Google Chrome.app", bytes: 425_100_000),
            ProcessMemory(pid: 204, name: "WindowServer", path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", appPath: nil, bytes: 1_000_000_000),
            ProcessMemory(pid: 205, name: "Codex Helper", path: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper", appPath: "/Applications/Codex.app", bytes: 501_900_000)
        ],
        pageIns: 0,
        pageOuts: 0,
        cumulativePageIns: 0,
        cumulativePageOuts: 0,
        swapUsed: 280_000_000,
        swapTotal: 1_000_000_000
    )
}

extension MemoryBreakdown {
    static func demoHistory() -> [MemoryBreakdown] {
        (0..<60).map { index in
            let app = UInt64(15_500_000_000 + (index % 18) * 140_000_000)
            let wired = UInt64(2_200_000_000 + (index % 9) * 75_000_000)
            let compressed = UInt64(1_000_000_000 + (index % 7) * 65_000_000)
            return MemoryBreakdown(
                app: app,
                wired: wired,
                compressed: compressed,
                free: 36_000_000_000 - app - wired - compressed
            )
        }
    }
}

enum MemoryReader {
    static func read() -> MemorySnapshot {
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
        let pressure = readPressurePercent() ?? Int((Double(used) / Double(total) * 100).rounded())
        let usedPercent = Int((Double(used) / Double(total) * 100).rounded())
        let swap = readSwap()
        let processSnapshot = readTopProcesses()

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
        let iStat = IStatSensorHistory.read()
        let batteryTemperature = battery.temperatureCelsius ?? native?.temperature(label: "Battery") ?? iStat.temperature(label: "Battery")
        let nativeFans = native?.fanReadings ?? []
        let fanReadings = nativeFans.isEmpty ? iStat.fanReadings : nativeFans
        let maxFanRPM = fanReadings.map(\.rpm).max()
        let fanPercent = maxFanRPM.map { $0 > 0 ? 100 : 0 }
        let preferredTemperatures = native?.temperatureReadings.isEmpty == false
            ? native?.temperatureReadings ?? []
            : iStat.temperatureReadings
        let temperatureReadings = preferredTemperatures.isEmpty
            ? batteryTemperature.map { [TemperatureReading(label: "Battery", celsius: $0)] } ?? []
            : preferredTemperatures.map { reading in
                reading.label == "Battery" && batteryTemperature != nil
                    ? TemperatureReading(label: reading.label, celsius: batteryTemperature!)
                    : reading
            }

        return SensorSnapshot(
            cpuTemperature: native?.cpuTemperatureCelsius ?? iStat.temperature(label: "CPU Performance Cores") ?? iStat.temperature(label: "CPU Efficiency Cores"),
            gpuTemperature: native?.gpuTemperatureCelsius ?? iStat.temperature(label: "Graphics"),
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
        let path = "/Library/Application Support/MenuBarStats/sensors.json"
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

private struct IStatSensorHistory {
    let temperatureReadings: [TemperatureReading]
    let fanReadings: [FanReading]

    func temperature(label: String) -> Double? {
        temperatureReadings.first { $0.label == label }?.celsius
    }

    static func read() -> IStatSensorHistory {
        let path = NSString(string: "~/Library/Application Support/iStat Menus 7/history/history.db").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            return IStatSensorHistory(temperatureReadings: [], fanReadings: [])
        }

        let query = """
        with latest as (select max(time) t from sensors where interval=5)
        select key, value from sensors, latest where time=t and interval=5 order by key;
        """
        let values = sqliteValues(databasePath: path, query: query)

        let temperatureMap: [(Int, String)] = [
            (24, "Airflow"),
            (7, "Battery"),
            (18, "CPU Efficiency Cores"),
            (19, "CPU Performance Cores"),
            (30, "Graphics"),
            (8, "Palm Rest"),
            (50, "SSD"),
            (9, "Wi-Fi")
        ]
        let temperatures = temperatureMap.compactMap { key, label -> TemperatureReading? in
            guard let value = values[key], value > 0, value < 130 else { return nil }
            return TemperatureReading(label: label, celsius: value)
        }

        let fanMap: [(Int, String)] = [
            (48, "Left Fan"),
            (49, "Right Fan")
        ]
        let fans = fanMap.compactMap { key, label -> FanReading? in
            guard let value = values[key], value >= 0, value < 10_000 else { return nil }
            return FanReading(label: label, rpm: Int(value.rounded()))
        }

        return IStatSensorHistory(temperatureReadings: temperatures, fanReadings: fans)
    }

    private static func sqliteValues(databasePath: String, query: String) -> [Int: Double] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [databasePath, query]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

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

        var values: [Int: Double] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|")
            guard parts.count == 2,
                  let key = Int(parts[0]),
                  let value = Double(parts[1]) else {
                continue
            }
            values[key] = value
        }

        return values
    }
}

enum NetworkReader {
    struct NetworkCounters: Equatable {
        let interfaceName: String
        let receivedBytes: UInt64
        let sentBytes: UInt64
        let timestamp: Date
    }

    private struct InterfaceInfo {
        var name: String
        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var isUp: Bool = false
        var isRunning: Bool = false
        var addresses: [String] = []
    }

    static func read(previous: NetworkCounters?, history: [NetworkSample]) -> (snapshot: NetworkSnapshot, counters: NetworkCounters?) {
        let interfaces = readInterfaces()
        let primary = primaryInterface(from: interfaces)
        let now = Date()

        guard let primary else {
            return (.empty, nil)
        }

        let counters = NetworkCounters(
            interfaceName: primary.name,
            receivedBytes: primary.receivedBytes,
            sentBytes: primary.sentBytes,
            timestamp: now
        )
        let rates = rates(from: previous, to: counters)
        let sample = NetworkSample(uploadBytesPerSecond: rates.upload, downloadBytesPerSecond: rates.download)
        let nextHistory = trimmed(history + [sample], limit: 48)

        let snapshot = NetworkSnapshot(
            location: "Automatic",
            interfaceName: primary.name,
            interfaceDisplayName: displayName(for: primary.name),
            publicIP: nil,
            ipAddresses: sortedAddresses(primary.addresses),
            ethernetConnected: ethernetConnected(in: interfaces),
            pingTarget: "istatmenus.app",
            pingMilliseconds: nil,
            uploadBytesPerSecond: rates.upload,
            downloadBytesPerSecond: rates.download,
            history: nextHistory,
            processes: [
                NetworkProcess(
                    name: "System Total",
                    path: "/System/Library/CoreServices/Finder.app",
                    appPath: "/System/Library/CoreServices/Finder.app",
                    uploadBytesPerSecond: rates.upload,
                    downloadBytesPerSecond: rates.download
                )
            ]
        )

        return (snapshot, counters)
    }

    private static func readInterfaces() -> [InterfaceInfo] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }
        defer { freeifaddrs(first) }

        var interfaces: [String: InterfaceInfo] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            let entry = current.pointee
            let name = String(cString: entry.ifa_name)
            var info = interfaces[name] ?? InterfaceInfo(name: name)
            info.isUp = info.isUp || (entry.ifa_flags & UInt32(IFF_UP)) != 0
            info.isRunning = info.isRunning || (entry.ifa_flags & UInt32(IFF_RUNNING)) != 0

            if let dataPointer = entry.ifa_data {
                let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                info.receivedBytes = max(info.receivedBytes, UInt64(data.ifi_ibytes))
                info.sentBytes = max(info.sentBytes, UInt64(data.ifi_obytes))
            }

            if let address = entry.ifa_addr,
               let ip = ipAddress(from: address),
               !info.addresses.contains(ip) {
                info.addresses.append(ip)
            }

            interfaces[name] = info
            cursor = entry.ifa_next
        }

        return Array(interfaces.values)
    }

    private static func ipAddress(from address: UnsafeMutablePointer<sockaddr>) -> String? {
        let family = Int32(address.pointee.sa_family)
        guard family == AF_INET || family == AF_INET6 else {
            return nil
        }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        let text = host.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return "" }
            return String(cString: baseAddress)
        }
        guard !text.hasPrefix("127."), text != "::1", !text.hasPrefix("fe80:") else {
            return nil
        }
        return text
    }

    private static func primaryInterface(from interfaces: [InterfaceInfo]) -> InterfaceInfo? {
        let usable = interfaces.filter {
            $0.isUp &&
            $0.isRunning &&
            !$0.addresses.isEmpty &&
            !$0.name.hasPrefix("lo") &&
            !$0.name.hasPrefix("awdl") &&
            !$0.name.hasPrefix("llw") &&
            !$0.name.hasPrefix("utun") &&
            !$0.name.hasPrefix("bridge") &&
            !$0.name.hasPrefix("gif") &&
            !$0.name.hasPrefix("stf") &&
            !$0.name.hasPrefix("pktap")
        }

        return usable.sorted { lhs, rhs in
            if lhs.name == "en0" { return true }
            if rhs.name == "en0" { return false }
            return (lhs.receivedBytes + lhs.sentBytes) > (rhs.receivedBytes + rhs.sentBytes)
        }.first
    }

    private static func rates(from previous: NetworkCounters?, to current: NetworkCounters) -> (upload: UInt64, download: UInt64) {
        guard let previous,
              previous.interfaceName == current.interfaceName else {
            return (0, 0)
        }

        let interval = max(current.timestamp.timeIntervalSince(previous.timestamp), 0.1)
        let uploadDelta = current.sentBytes >= previous.sentBytes ? current.sentBytes - previous.sentBytes : 0
        let downloadDelta = current.receivedBytes >= previous.receivedBytes ? current.receivedBytes - previous.receivedBytes : 0
        return (
            UInt64(Double(uploadDelta) / interval),
            UInt64(Double(downloadDelta) / interval)
        )
    }

    private static func trimmed(_ history: [NetworkSample], limit: Int) -> [NetworkSample] {
        if history.count >= limit {
            return Array(history.suffix(limit))
        }

        return Array(repeating: NetworkSample(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0), count: limit - history.count) + history
    }

    private static func ethernetConnected(in interfaces: [InterfaceInfo]) -> Bool {
        interfaces.contains {
            $0.isUp &&
            $0.isRunning &&
            !$0.addresses.isEmpty &&
            $0.name.hasPrefix("en") &&
            $0.name != "en0"
        }
    }

    private static func displayName(for interfaceName: String) -> String {
        if interfaceName == "en0" {
            return readWiFiNetworkName() ?? "en0"
        }

        if interfaceName.hasPrefix("en") {
            return "Ethernet"
        }

        return interfaceName
    }

    private static func sortedAddresses(_ addresses: [String]) -> [String] {
        addresses.sorted { lhs, rhs in
            let lhsIPv4 = lhs.contains(".")
            let rhsIPv4 = rhs.contains(".")
            if lhsIPv4 != rhsIPv4 {
                return lhsIPv4
            }
            return lhs < rhs
        }
    }

    private static func readWiFiNetworkName() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-getairportnetwork", "en0"]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        if let range = text.range(of: "Current Wi-Fi Network:") {
            let name = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }

        return nil
    }
}

enum LLMUsageReader {
    private struct LocalCodexUsage {
        let fiveHourTokens: UInt64
        let weeklyTokens: UInt64
        let weeklyThreads: Int
        let windows: [LLMLocalUsageWindow]
        let recentSessions: [LLMUsageSession]
        let topWeeklySessions: [LLMUsageSession]
    }

    private final class HTTPResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        private var statusCode: Int?
        private var errorDescription: String?

        func set(data: Data?, response: URLResponse?, error: Error?) {
            lock.lock()
            self.data = data
            self.statusCode = (response as? HTTPURLResponse)?.statusCode
            self.errorDescription = error?.localizedDescription
            lock.unlock()
        }

        func snapshot() -> (data: Data?, statusCode: Int?, errorDescription: String?) {
            lock.lock()
            defer { lock.unlock() }
            return (data, statusCode, errorDescription)
        }
    }

    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let access_token: String?
        }

        let tokens: Tokens?
    }

    private struct WhamUsageResponse: Decodable {
        let email: String?
        let plan_type: String?
        let rate_limit: RateLimitPayload?
        let additional_rate_limits: [AdditionalRateLimit]?
        let credits: Credits?
    }

    private struct AdditionalRateLimit: Decodable {
        let limit_name: String?
        let rate_limit: RateLimitPayload?
    }

    private struct RateLimitPayload: Decodable {
        let primary_window: WindowPayload?
        let secondary_window: WindowPayload?
    }

    private struct WindowPayload: Decodable {
        let used_percent: Int?
        let limit_window_seconds: Int?
        let reset_at: TimeInterval?
    }

    private struct Credits: Decodable {
        let balance: String?
        let unlimited: Bool?
    }

    static func read() -> LLMUsageSnapshot {
        let local = readLocalCodexUsage()
        guard let token = readAccessToken() else {
            return LLMUsageSnapshot(
                email: nil,
                planType: nil,
                limits: [],
                creditsBalance: nil,
                lastUpdated: Date(),
                localFiveHourTokens: local.fiveHourTokens,
                localWeeklyTokens: local.weeklyTokens,
                localWeeklyThreads: local.weeklyThreads,
                localWindows: local.windows,
                recentSessions: local.recentSessions,
                topWeeklySessions: local.topWeeklySessions,
                error: "Codex auth not found"
            )
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = HTTPResultBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            resultBox.set(data: data, response: response, error: error)
            semaphore.signal()
        }.resume()

        let timeout = semaphore.wait(timeout: .now() + 4)
        if timeout == .timedOut {
            return snapshotWithLocalUsage(local, error: "Codex usage request timed out")
        }

        let httpResult = resultBox.snapshot()
        if let errorDescription = httpResult.errorDescription {
            return snapshotWithLocalUsage(local, error: errorDescription)
        }

        guard httpResult.statusCode == 200,
              let resultData = httpResult.data else {
            let status = httpResult.statusCode
            return snapshotWithLocalUsage(local, error: status.map { "Codex usage returned HTTP \($0)" } ?? "Codex usage unavailable")
        }

        do {
            let response = try JSONDecoder().decode(WhamUsageResponse.self, from: resultData)
            return LLMUsageSnapshot(
                email: response.email,
                planType: response.plan_type,
                limits: limits(from: response),
                creditsBalance: response.credits?.unlimited == true ? "Unlimited" : response.credits?.balance,
                lastUpdated: Date(),
                localFiveHourTokens: local.fiveHourTokens,
                localWeeklyTokens: local.weeklyTokens,
                localWeeklyThreads: local.weeklyThreads,
                localWindows: local.windows,
                recentSessions: local.recentSessions,
                topWeeklySessions: local.topWeeklySessions,
                error: nil
            )
        } catch {
            return snapshotWithLocalUsage(local, error: "Could not parse Codex usage")
        }
    }

    private static func limits(from response: WhamUsageResponse) -> [LLMUsageLimit] {
        var limits: [LLMUsageLimit] = []
        if let rateLimit = response.rate_limit {
            limits.append(LLMUsageLimit(name: "Codex", primary: window(from: rateLimit.primary_window), secondary: window(from: rateLimit.secondary_window)))
        }

        for additional in response.additional_rate_limits ?? [] {
            guard let rateLimit = additional.rate_limit else { continue }
            limits.append(LLMUsageLimit(name: additional.limit_name ?? "Model", primary: window(from: rateLimit.primary_window), secondary: window(from: rateLimit.secondary_window)))
        }

        return limits
    }

    private static func window(from payload: WindowPayload?) -> LLMUsageWindow? {
        guard let payload,
              let usedPercent = payload.used_percent,
              let windowSeconds = payload.limit_window_seconds else {
            return nil
        }

        return LLMUsageWindow(
            label: label(forWindowSeconds: windowSeconds),
            usedPercent: min(max(usedPercent, 0), 100),
            remainingPercent: min(max(100 - usedPercent, 0), 100),
            resetAt: payload.reset_at.map { Date(timeIntervalSince1970: $0) },
            windowSeconds: windowSeconds
        )
    }

    private static func label(forWindowSeconds seconds: Int) -> String {
        if seconds >= 604_800 {
            let weeks = max(Int((Double(seconds) / 604_800).rounded()), 1)
            return weeks == 1 ? "Weekly" : "\(weeks) Weeks"
        }
        if seconds >= 86_400 {
            return "\(Int(ceil(Double(seconds) / 86_400)))d"
        }
        if seconds >= 3_600 {
            return "\(Int(ceil(Double(seconds) / 3_600)))h"
        }
        return "\(Int(ceil(Double(seconds) / 60)))m"
    }

    private static func readAccessToken() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let token = auth.tokens?.access_token,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func readLocalCodexUsage() -> LocalCodexUsage {
        let databasePath = "\(NSHomeDirectory())/.codex/state_5.sqlite"
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return LocalCodexUsage(fiveHourTokens: 0, weeklyTokens: 0, weeklyThreads: 0, windows: [], recentSessions: [], topWeeklySessions: [])
        }

        let windows = [
            localWindow(databasePath: databasePath, label: "1h", seconds: 3_600),
            localWindow(databasePath: databasePath, label: "5h", seconds: 18_000),
            localWindow(databasePath: databasePath, label: "24h", seconds: 86_400),
            localWindow(databasePath: databasePath, label: "7d", seconds: 604_800)
        ]
        let fiveHour = windows.first(where: { $0.label == "5h" }) ?? LLMLocalUsageWindow(label: "5h", tokens: 0, threads: 0)
        let weekly = windows.first(where: { $0.label == "7d" }) ?? LLMLocalUsageWindow(label: "7d", tokens: 0, threads: 0)

        return LocalCodexUsage(
            fiveHourTokens: fiveHour.tokens,
            weeklyTokens: weekly.tokens,
            weeklyThreads: weekly.threads,
            windows: windows,
            recentSessions: sessions(databasePath: databasePath, mode: .recent),
            topWeeklySessions: sessions(databasePath: databasePath, mode: .highestWeekly)
        )
    }

    private static func localWindow(databasePath: String, label: String, seconds: Int) -> LLMLocalUsageWindow {
        let query = """
        select coalesce(sum(tokens_used),0), count(*)
        from threads
        where coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-\(seconds))*1000;
        """
        let row = sqliteRows(databasePath: databasePath, query: query).first ?? []
        return LLMLocalUsageWindow(
            label: label,
            tokens: row.indices.contains(0) ? UInt64(row[0]) ?? 0 : 0,
            threads: row.indices.contains(1) ? Int(row[1]) ?? 0 : 0
        )
    }

    private enum SessionQueryMode {
        case recent
        case highestWeekly
    }

    private static func sessions(databasePath: String, mode: SessionQueryMode) -> [LLMUsageSession] {
        let whereClause = mode == .highestWeekly
            ? "where tokens_used > 0 and coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-7*24*3600)*1000"
            : "where tokens_used > 0"
        let orderClause = mode == .highestWeekly
            ? "order by tokens_used desc, coalesce(updated_at_ms, updated_at * 1000) desc"
            : "order by coalesce(updated_at_ms, updated_at * 1000) desc"
        let query = """
        select
            id,
            replace(replace(coalesce(nullif(title,''),'Untitled'), char(10), ' '), char(9), ' '),
            coalesce(tokens_used,0),
            coalesce(updated_at_ms, updated_at * 1000),
            replace(replace(coalesce(nullif(model,''), nullif(model_provider,''), ''), char(10), ' '), char(9), ' '),
            replace(replace(coalesce(nullif(cwd,''), ''), char(10), ' '), char(9), ' '),
            replace(replace(coalesce(nullif(preview,''), nullif(first_user_message,''), ''), char(10), ' '), char(9), ' '),
            rollout_path
        from threads
        \(whereClause)
        \(orderClause)
        limit 5;
        """

        return sqliteRows(databasePath: databasePath, query: query).compactMap { row in
            guard row.count >= 8 else { return nil }
            let title = compactText(row[1], fallback: "Untitled")
            let tokens = UInt64(row[2]) ?? 0
            let updatedAt = TimeInterval(row[3]).map { Date(timeIntervalSince1970: $0 / 1000) }
            let model = compactText(row[4], fallback: "Model unavailable")
            let project = projectName(from: row[5])
            let preview = compactText(row[6], fallback: "No prompt preview stored")
            let rolloutPath = compactText(row[7], fallback: "")
            return LLMUsageSession(
                id: row[0],
                title: title,
                projectName: project,
                modelName: model,
                preview: preview,
                rolloutPath: rolloutPath,
                tokens: tokens,
                updatedAt: updatedAt
            )
        }
    }

    private static func sqliteUInt64(databasePath: String, query: String) -> UInt64 {
        let value = sqliteRows(databasePath: databasePath, query: query).first?.first
        return value.flatMap(UInt64.init) ?? 0
    }

    private static func sqliteRows(databasePath: String, query: String) -> [[String]] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = ["-batch", "-separator", "\t", databasePath, query]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    private static func snapshotWithLocalUsage(
        _ local: LocalCodexUsage,
        error: String
    ) -> LLMUsageSnapshot {
        LLMUsageSnapshot(
            email: nil,
            planType: nil,
            limits: [],
            creditsBalance: nil,
            lastUpdated: Date(),
            localFiveHourTokens: local.fiveHourTokens,
            localWeeklyTokens: local.weeklyTokens,
            localWeeklyThreads: local.weeklyThreads,
            localWindows: local.windows,
            recentSessions: local.recentSessions,
            topWeeklySessions: local.topWeeklySessions,
            error: error
        )
    }

    private static func compactText(_ text: String, fallback: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? fallback : trimmedText
    }

    private static func trimmed(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength - 1)
        return String(text[..<end]) + "..."
    }

    private static func projectName(from path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "Project unavailable" }
        return URL(fileURLWithPath: trimmedPath).lastPathComponent
    }
}

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

    static func rate(_ bytesPerSecond: UInt64) -> String {
        "\(memory(bytesPerSecond))/s"
    }

    static func compactRate(_ bytesPerSecond: UInt64) -> String {
        let mb = Double(bytesPerSecond) / 1_000_000
        if mb >= 1 {
            return String(format: "%.1f M", mb)
        }

        let kb = Double(bytesPerSecond) / 1_000
        return String(format: "%.0f K", kb)
    }
}
