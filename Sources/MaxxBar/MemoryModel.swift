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

struct LLMResetCreditExpiration: Identifiable, Equatable {
    var id: String { "\(Int(expiresAt.timeIntervalSince1970))-\(count)" }
    var count: Int
    var expiresAt: Date
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
    var tokenUsage: LLMTokenUsageSummary?
    var createdAt: Date?
    var updatedAt: Date?

    var detail: String {
        "\(projectName) • \(modelName)"
    }
}

struct LLMTokenUsageSummary: Equatable {
    var inputTokens: UInt64
    var cachedInputTokens: UInt64
    var outputTokens: UInt64
    var reasoningOutputTokens: UInt64
    var totalTokens: UInt64
    var turnCount: Int

    var nonCachedInputTokens: UInt64 {
        inputTokens >= cachedInputTokens ? inputTokens - cachedInputTokens : 0
    }

    var cacheHitPercent: Int {
        guard inputTokens > 0 else { return 0 }
        return Int((Double(cachedInputTokens) / Double(inputTokens) * 100).rounded())
    }

    func estimatedCost(for modelName: String) -> Double {
        let pricing = LLMTokenPricing.rates(for: modelName)
        return pricing.estimatedCost(
            freshInputTokens: nonCachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens
        )
    }

    func pricingLabel(for modelName: String) -> String {
        LLMTokenPricing.rates(for: modelName).label
    }
}

struct LLMTokenPricing: Equatable {
    static let gpt55 = LLMTokenPricing(label: "gpt-5.5 API", freshInputDollarsPerMillion: 5.0, cachedInputDollarsPerMillion: 0.5, outputDollarsPerMillion: 30.0)
    static let gpt54 = LLMTokenPricing(label: "gpt-5.4 API", freshInputDollarsPerMillion: 2.5, cachedInputDollarsPerMillion: 0.25, outputDollarsPerMillion: 15.0)
    static let gpt54Mini = LLMTokenPricing(label: "gpt-5.4-mini API", freshInputDollarsPerMillion: 0.75, cachedInputDollarsPerMillion: 0.075, outputDollarsPerMillion: 4.5)
    static let gpt54Nano = LLMTokenPricing(label: "gpt-5.4-nano API", freshInputDollarsPerMillion: 0.20, cachedInputDollarsPerMillion: 0.02, outputDollarsPerMillion: 1.25)
    static let gpt53Codex = LLMTokenPricing(label: "gpt-5.3-codex API", freshInputDollarsPerMillion: 1.75, cachedInputDollarsPerMillion: 0.175, outputDollarsPerMillion: 14.0)
    static let gpt51Codex = LLMTokenPricing(label: "gpt-5.1-codex API", freshInputDollarsPerMillion: 1.25, cachedInputDollarsPerMillion: 0.125, outputDollarsPerMillion: 10.0)
    static let codexMini = LLMTokenPricing(label: "codex-mini API", freshInputDollarsPerMillion: 1.5, cachedInputDollarsPerMillion: 0.375, outputDollarsPerMillion: 6.0)

    var label: String
    var freshInputDollarsPerMillion: Double
    var cachedInputDollarsPerMillion: Double
    var outputDollarsPerMillion: Double

    static func rates(for modelName: String) -> LLMTokenPricing {
        let model = modelName.lowercased()
        if model.hasPrefix("codex-mini") {
            return .codexMini
        }
        if model.hasPrefix("gpt-5.3-codex") || model.hasPrefix("gpt-5.2-codex") {
            return .gpt53Codex
        }
        if model.hasPrefix("gpt-5.1-codex") || model.hasPrefix("gpt-5-codex") {
            return .gpt51Codex
        }
        if model.hasPrefix("gpt-5.4-mini") {
            return .gpt54Mini
        }
        if model.hasPrefix("gpt-5.4-nano") {
            return .gpt54Nano
        }
        if model.hasPrefix("gpt-5.4") {
            return .gpt54
        }
        return .gpt55
    }

    func estimatedCost(
        freshInputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64
    ) -> Double {
        dollars(for: freshInputTokens, rate: freshInputDollarsPerMillion)
            + dollars(for: cachedInputTokens, rate: cachedInputDollarsPerMillion)
            + dollars(for: outputTokens, rate: outputDollarsPerMillion)
    }

    private func dollars(for tokens: UInt64, rate: Double) -> Double {
        Double(tokens) / 1_000_000 * rate
    }
}

struct LLMTokenCostEstimate: Identifiable, Equatable {
    static let freshInputDollarsPerMillion = LLMTokenPricing.gpt55.freshInputDollarsPerMillion
    static let cachedInputDollarsPerMillion = LLMTokenPricing.gpt55.cachedInputDollarsPerMillion
    static let outputDollarsPerMillion = LLMTokenPricing.gpt55.outputDollarsPerMillion

    var id: String { label }
    var label: String
    var sessionCount: Int
    var inputTokens: UInt64
    var cachedInputTokens: UInt64
    var outputTokens: UInt64
    var totalTokens: UInt64
    var windowStartedAt: Date
    var windowEndedAt: Date

    var freshInputTokens: UInt64 {
        inputTokens >= cachedInputTokens ? inputTokens - cachedInputTokens : 0
    }

    var cacheHitPercent: Int {
        guard inputTokens > 0 else { return 0 }
        return Int((Double(cachedInputTokens) / Double(inputTokens) * 100).rounded())
    }

    var estimatedCost: Double {
        LLMTokenPricing.gpt55.estimatedCost(
            freshInputTokens: freshInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens
        )
    }
}

struct LLMUsageWindowLogEntry: Codable, Equatable {
    var recordedAt: Date
    var windowLabel: String
    var windowStartedAt: Date
    var windowEndedAt: Date
    var sessionCount: Int
    var totalInputTokens: UInt64
    var cachedInputTokens: UInt64
    var freshInputTokens: UInt64
    var outputTokens: UInt64
    var totalTokens: UInt64
    var cacheHitPercent: Int
    var estimatedCostUSD: Double
    var freshInputDollarsPerMillion: Double
    var cachedInputDollarsPerMillion: Double
    var outputDollarsPerMillion: Double

    init(recordedAt: Date = Date(), estimate: LLMTokenCostEstimate) {
        self.recordedAt = recordedAt
        self.windowLabel = estimate.label
        self.windowStartedAt = estimate.windowStartedAt
        self.windowEndedAt = estimate.windowEndedAt
        self.sessionCount = estimate.sessionCount
        self.totalInputTokens = estimate.inputTokens
        self.cachedInputTokens = estimate.cachedInputTokens
        self.freshInputTokens = estimate.freshInputTokens
        self.outputTokens = estimate.outputTokens
        self.totalTokens = estimate.totalTokens
        self.cacheHitPercent = estimate.cacheHitPercent
        self.estimatedCostUSD = estimate.estimatedCost
        self.freshInputDollarsPerMillion = LLMTokenCostEstimate.freshInputDollarsPerMillion
        self.cachedInputDollarsPerMillion = LLMTokenCostEstimate.cachedInputDollarsPerMillion
        self.outputDollarsPerMillion = LLMTokenCostEstimate.outputDollarsPerMillion
    }
}

struct LLMQuotaHistorySample: Identifiable, Equatable, Codable {
    var id = UUID()
    var sampledAt: Date
    var primaryRemainingPercent: Int?
    var weeklyRemainingPercent: Int?
    var planType: String? = nil
}

private struct LLMQuotaActivitySignature: Equatable {
    var primaryRemainingPercent: Int?
    var weeklyRemainingPercent: Int?
    var planType: String?
    var localFiveHourTokens: UInt64
    var localWeeklyTokens: UInt64
    var localWeeklyThreads: Int
    var latestSessionUpdateSecond: Int?

    init(usage: LLMUsageSnapshot, limit: LLMUsageLimit) {
        self.primaryRemainingPercent = limit.primary?.remainingPercent
        self.weeklyRemainingPercent = limit.secondary?.remainingPercent
        self.planType = usage.planType
        self.localFiveHourTokens = usage.localFiveHourTokens
        self.localWeeklyTokens = usage.localWeeklyTokens
        self.localWeeklyThreads = usage.localWeeklyThreads
        self.latestSessionUpdateSecond = (usage.recentSessions + usage.topWeeklySessions)
            .compactMap(\.updatedAt)
            .map { Int($0.timeIntervalSince1970) }
            .max()
    }
}

struct LLMUsageSnapshot: Equatable {
    var email: String?
    var planType: String?
    var limits: [LLMUsageLimit]
    var creditsBalance: String?
    var resetCreditCount: Int?
    var resetCreditExpirations: [LLMResetCreditExpiration]
    var lastUpdated: Date?
    var localFiveHourTokens: UInt64
    var localWeeklyTokens: UInt64
    var localWeeklyThreads: Int
    var localWindows: [LLMLocalUsageWindow]
    var costEstimates: [LLMTokenCostEstimate]
    var recentSessions: [LLMUsageSession]
    var topWeeklySessions: [LLMUsageSession]
    var error: String?
}

struct AIUsageCounter: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let count: Int
}

struct AIWorkflowPath: Identifiable, Equatable {
    var id: String { "\(before)|\(surface)|\(after)|\(useCase)" }
    let before: String
    let surface: String
    let after: String
    let useCase: String
    let count: Int
}

struct AITransferFlow: Identifiable, Equatable {
    var id: String { "\(source)|\(destination)|\(useCase)" }
    let source: String
    let destination: String
    let useCase: String
    let count: Int
    let confidence: String
}

struct MaxxMomentSummary: Identifiable, Equatable {
    var id: String { "\(ts.timeIntervalSince1970)-\(app)-\(note)" }
    let ts: Date
    let sentiment: String
    let app: String
    let surface: String?
    let note: String
    let screenshotPath: String?
}

struct AIUsageSnapshot: Equatable {
    var sampledAt: Date?
    var activeApp: String
    var activeSite: String?
    var activeTool: String?
    var activeSurface: String?
    var activeUseCase: String
    var sessionsToday: Int
    var sessionsSevenDays: Int
    var timeTodaySeconds: TimeInterval
    var timeSevenDaysSeconds: TimeInterval
    var averageSessionSeconds: TimeInterval
    var contextConfidence: String
    var topTools: [AIUsageCounter]
    var topBeforeApps: [AIUsageCounter]
    var topAfterApps: [AIUsageCounter]
    var workflowPaths: [AIWorkflowPath]
    var copyEventsToday: Int
    var pasteEventsToday: Int
    var topCopiedFrom: [AIUsageCounter]
    var topPastedInto: [AIUsageCounter]
    var transferFlows: [AITransferFlow]
    var momentsToday: Int
    var lastMomentAt: Date?
    var recentMoments: [MaxxMomentSummary]
    var lastError: String?

    var insightEventsToday: Int {
        sessionsToday + copyEventsToday + pasteEventsToday + momentsToday
    }
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
    @Published private(set) var aiUsage = AIUsageSnapshot.empty
    private var previousCumulativePageIns: UInt64?
    private var previousCumulativePageOuts: UInt64?
    private var previousCPUInfo: CPUReader.CPULoadInfo?
    private var previousNetworkCounters: NetworkReader.NetworkCounters?
    private var networkHistory: [NetworkSample] = []
    private var previousLLMUsageRefresh: Date?
    private var previousLLMQuotaSample: Date?
    private var previousLLMQuotaActivitySignature: LLMQuotaActivitySignature?
    private var isRefreshing = false
    private var isRefreshingStatus = false
    private var isRefreshingLLMUsage = false
    private static let llmQuotaHistoryLimit = 4_320

    init() {
        llmQuotaHistory = Self.loadLLMQuotaHistory()
        previousLLMQuotaSample = llmQuotaHistory.last?.sampledAt
    }

    init(
        snapshot: MemorySnapshot,
        history: [MemoryBreakdown],
        network: NetworkSnapshot = .demo,
        llmUsage: LLMUsageSnapshot = .demo,
        aiUsage: AIUsageSnapshot = .demo,
        llmQuotaHistory: [LLMQuotaHistorySample] = .demo
    ) {
        self.snapshot = snapshot
        self.history = history
        self.network = network
        self.llmUsage = llmUsage
        self.aiUsage = aiUsage
        self.llmQuotaHistory = llmQuotaHistory
    }

    func applyDemoSnapshots() {
        sensors = .demo
        cpuGPU = CPUReader.read(previous: nil, sensors: .demo).snapshot
        network = .demo
        llmUsage = .demo
        aiUsage = .demo
        llmQuotaHistory = .demo
    }

    func seedInitialMemorySnapshot() {
        let stats = MemoryReader.read(includeProcesses: false, precisePressure: false)
        snapshot = stats
        previousCumulativePageIns = stats.cumulativePageIns
        previousCumulativePageOuts = stats.cumulativePageOuts
        history = [stats.breakdown]
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
        aiUsage = AIUsageReader.recordAndRead(memory: snapshot, cpuGPU: cpuGPU, llmUsage: llmUsage)
        previousLLMUsageRefresh = Date()
        sampleLLMQuotaIfNeeded(force: true)
        history.append(stats.breakdown)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }

    func captureLLMQuotaSample() {
        sampleLLMQuotaIfNeeded(force: true)
    }

    func refreshInBackground(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard !isRefreshing else { return }
        isRefreshing = true

        let previousPageIns = previousCumulativePageIns
        let previousPageOuts = previousCumulativePageOuts
        let previousCPUInfo = previousCPUInfo
        let previousNetworkCounters = previousNetworkCounters
        let networkHistory = networkHistory

        DispatchQueue.global(qos: .utility).async {
            let result = Self.collectRefresh(
                previousPageIns: previousPageIns,
                previousPageOuts: previousPageOuts,
                previousCPUInfo: previousCPUInfo,
                previousNetworkCounters: previousNetworkCounters,
                networkHistory: networkHistory
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apply(result)
                self.isRefreshing = false
                completion?()
            }
        }
    }

    func refreshStatusInBackground(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard !isRefreshingStatus else { return }
        isRefreshingStatus = true

        let previousPageIns = previousCumulativePageIns
        let previousPageOuts = previousCumulativePageOuts

        DispatchQueue.global(qos: .utility).async {
            let stats = MemoryReader.read(includeProcesses: false, precisePressure: false)
            var displayStats = stats
            displayStats.pageIns = Self.deltaValue(from: previousPageIns, to: stats.cumulativePageIns)
            displayStats.pageOuts = Self.deltaValue(from: previousPageOuts, to: stats.cumulativePageOuts)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.previousCumulativePageIns = stats.cumulativePageIns
                self.previousCumulativePageOuts = stats.cumulativePageOuts
                self.snapshot = displayStats
                self.aiUsage = AIUsageReader.recordAndRead(memory: displayStats, cpuGPU: self.cpuGPU, llmUsage: self.llmUsage)
                self.history.append(stats.breakdown)
                if self.history.count > 60 {
                    self.history.removeFirst(self.history.count - 60)
                }
                self.isRefreshingStatus = false
                completion?()
            }
        }
    }

    func refreshLLMUsageInBackground(force: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard !isRefreshingLLMUsage else { return }
        if !force,
           let previousLLMUsageRefresh,
           Date().timeIntervalSince(previousLLMUsageRefresh) < 60 {
            completion?()
            return
        }

        isRefreshingLLMUsage = true
        DispatchQueue.global(qos: .utility).async {
            let usage = LLMUsageReader.read()
            let refreshedAt = Date()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.llmUsage = usage
                self.aiUsage = AIUsageReader.recordAndRead(memory: self.snapshot, cpuGPU: self.cpuGPU, llmUsage: usage)
                self.previousLLMUsageRefresh = refreshedAt
                self.logFiveHourUsageWindow(from: usage)
                self.sampleLLMQuotaIfNeeded()
                self.isRefreshingLLMUsage = false
                completion?()
            }
        }
    }

    func openFiveHourUsageLog() {
        guard let url = Self.fiveHourUsageReportURL ?? Self.fiveHourUsageLogURL else { return }
        do {
            try Self.writeFiveHourUsageReport()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            NSWorkspace.shared.open(url)
        } catch {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func captureMaxxMoment(sentiment: String, note: String, includeScreenshot: Bool) {
        aiUsage = AIUsageReader.captureMoment(
            memory: snapshot,
            cpuGPU: cpuGPU,
            llmUsage: llmUsage,
            sentiment: sentiment,
            note: note,
            includeScreenshot: includeScreenshot
        )
    }

    func openAIUsageReport() {
        guard let url = AIUsageReader.writeReport() else { return }
        NSWorkspace.shared.open(url)
    }

    func recordClipboardEvent(_ eventType: String) {
        aiUsage = AIUsageReader.recordClipboardEvent(eventType)
    }

    func startDeepTrace() {
        TraceworkLauncher.openHub()
    }

    private struct RefreshResult {
        let stats: MemorySnapshot
        let displayStats: MemorySnapshot
        let sensors: SensorSnapshot
        let cpuResult: (snapshot: CPUGPUSnapshot, current: CPUReader.CPULoadInfo?)
        let networkResult: (snapshot: NetworkSnapshot, counters: NetworkReader.NetworkCounters?)
    }

    nonisolated private static func collectRefresh(
        previousPageIns: UInt64?,
        previousPageOuts: UInt64?,
        previousCPUInfo: CPUReader.CPULoadInfo?,
        previousNetworkCounters: NetworkReader.NetworkCounters?,
        networkHistory: [NetworkSample]
    ) -> RefreshResult {
        let stats = MemoryReader.read()
        var displayStats = stats
        displayStats.pageIns = deltaValue(from: previousPageIns, to: stats.cumulativePageIns)
        displayStats.pageOuts = deltaValue(from: previousPageOuts, to: stats.cumulativePageOuts)
        let sensors = SensorReader.read()
        let cpuResult = CPUReader.read(previous: previousCPUInfo, sensors: sensors)
        let networkResult = NetworkReader.read(previous: previousNetworkCounters, history: networkHistory)

        return RefreshResult(
            stats: stats,
            displayStats: displayStats,
            sensors: sensors,
            cpuResult: cpuResult,
            networkResult: networkResult
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
        aiUsage = AIUsageReader.recordAndRead(memory: result.displayStats, cpuGPU: cpuGPU, llmUsage: llmUsage)
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
        let activitySignature = LLMQuotaActivitySignature(usage: llmUsage, limit: limit)
        if !force,
           let previousLLMQuotaSample,
           now.timeIntervalSince(previousLLMQuotaSample) < llmQuotaSampleInterval(for: activitySignature) {
            return
        }

        llmQuotaHistory.append(
            LLMQuotaHistorySample(
                sampledAt: now,
                primaryRemainingPercent: limit.primary?.remainingPercent,
                weeklyRemainingPercent: limit.secondary?.remainingPercent,
                planType: llmUsage.planType
            )
        )
        previousLLMQuotaSample = now
        previousLLMQuotaActivitySignature = activitySignature

        if llmQuotaHistory.count > Self.llmQuotaHistoryLimit {
            llmQuotaHistory.removeFirst(llmQuotaHistory.count - Self.llmQuotaHistoryLimit)
        }

        saveLLMQuotaHistory()
    }

    private func llmQuotaSampleInterval(for activitySignature: LLMQuotaActivitySignature) -> TimeInterval {
        if previousLLMQuotaActivitySignature == activitySignature {
            return 3_600
        }

        if llmQuotaHistory.count < 5 {
            return 60
        }
        if llmQuotaHistory.count < 12 {
            return 300
        }
        return 600
    }

    private static var llmQuotaHistoryURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("MaxxBar", isDirectory: true)
            .appendingPathComponent("llm-quota-history.json")
    }

    private static var fiveHourUsageLogURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("MaxxBar", isDirectory: true)
            .appendingPathComponent("llm-5h-usage-windows.jsonl")
    }

    private static var fiveHourUsageReportURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("MaxxBar", isDirectory: true)
            .appendingPathComponent("llm-5h-usage-windows.html")
    }

    private static func loadLLMQuotaHistory() -> [LLMQuotaHistorySample] {
        guard let url = llmQuotaHistoryURL,
              let data = try? Data(contentsOf: url),
              let samples = try? JSONDecoder().decode([LLMQuotaHistorySample].self, from: data) else {
            return []
        }

        return Array(samples.sorted { $0.sampledAt < $1.sampledAt }.suffix(llmQuotaHistoryLimit))
    }

    private func saveLLMQuotaHistory() {
        guard let url = Self.llmQuotaHistoryURL,
              let data = try? JSONEncoder().encode(llmQuotaHistory) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence is best-effort; the live graph should keep working if this write fails.
        }
    }

    private func logFiveHourUsageWindow(from usage: LLMUsageSnapshot) {
        guard let estimate = usage.costEstimates.first(where: { $0.label.lowercased() == "5h" }),
              let url = Self.fiveHourUsageLogURL,
              let line = Self.logLine(for: LLMUsageWindowLogEntry(estimate: estimate)) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            handle.write(line)
            try Self.writeFiveHourUsageReport()
        } catch {
            // The app should never block live stats because the usage log could not be written.
        }
    }

    private static func logLine(for entry: LLMUsageWindowLogEntry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return nil }
        data.append(0x0A)
        return data
    }

    private static func writeFiveHourUsageReport() throws {
        guard let reportURL = fiveHourUsageReportURL,
              let logURL = fiveHourUsageLogURL else {
            return
        }

        let entries = readFiveHourUsageLog(from: logURL)
        let html = fiveHourUsageHTML(entries: entries, rawLogURL: logURL)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try html.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private static func readFiveHourUsageLog(from url: URL) -> [LLMUsageWindowLogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(LLMUsageWindowLogEntry.self, from: data)
            }
            .sorted { $0.windowEndedAt > $1.windowEndedAt }
    }

    private static func fiveHourUsageHTML(entries: [LLMUsageWindowLogEntry], rawLogURL: URL) -> String {
        let latest = entries.first
        let rows = entries.map { entry in
            """
            <tr>
              <td>\(html(entry.windowLabel))</td>
              <td>\(html(dateRange(entry.windowStartedAt, entry.windowEndedAt)))</td>
              <td>\(html(dateTime(entry.recordedAt)))</td>
              <td class="num">\(entry.sessionCount)</td>
              <td class="num">\(tokenString(entry.freshInputTokens))</td>
              <td class="num">\(tokenString(entry.cachedInputTokens))</td>
              <td class="num">\(tokenString(entry.outputTokens))</td>
              <td class="num">\(tokenString(entry.totalTokens))</td>
              <td class="num">\(entry.cacheHitPercent)%</td>
              <td class="num">\(dollarString(entry.estimatedCostUSD))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let latestCards = latest.map { entry in
            """
            <section class="summary">
              <div><span>Window</span><strong>\(html(dateRange(entry.windowStartedAt, entry.windowEndedAt)))</strong></div>
              <div><span>API Est.</span><strong>\(dollarString(entry.estimatedCostUSD))</strong></div>
              <div><span>Cache Hit</span><strong>\(entry.cacheHitPercent)%</strong></div>
              <div><span>Fresh Input</span><strong>\(tokenString(entry.freshInputTokens))</strong></div>
              <div><span>Cached Input</span><strong>\(tokenString(entry.cachedInputTokens))</strong></div>
              <div><span>Output</span><strong>\(tokenString(entry.outputTokens))</strong></div>
            </section>
            """
        } ?? """
        <section class="empty">No 5h usage samples have been recorded yet.</section>
        """

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>MaxxBar Codex 5h Usage Log</title>
          <style>
            :root { color-scheme: dark; --bg:#161922; --panel:#222638; --panel2:#2b3050; --text:#f7f7fb; --muted:#a8abb8; --blue:#0a84ff; --yellow:#ffcc24; }
            body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; background:var(--bg); color:var(--text); }
            main { max-width:1120px; margin:0 auto; padding:28px; }
            h1 { margin:0 0 6px; font-size:28px; color:var(--blue); }
            p { margin:0 0 20px; color:var(--muted); }
            .summary { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:10px; margin:18px 0 20px; }
            .summary div, .empty { background:var(--panel); border-radius:8px; padding:12px 14px; }
            .summary span { display:block; color:var(--muted); font-size:12px; font-weight:650; text-transform:uppercase; letter-spacing:.02em; }
            .summary strong { display:block; margin-top:5px; font-size:22px; }
            table { width:100%; border-collapse:collapse; background:var(--panel); border-radius:8px; overflow:hidden; }
            th, td { padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.07); text-align:left; white-space:nowrap; }
            th { color:var(--blue); font-size:12px; text-transform:uppercase; letter-spacing:.03em; background:var(--panel2); }
            td { color:rgba(247,247,251,.9); font-size:14px; }
            .num { text-align:right; font-variant-numeric:tabular-nums; }
            a { color:var(--blue); }
            footer { margin-top:16px; color:var(--muted); font-size:12px; }
          </style>
        </head>
        <body>
          <main>
            <h1>Codex 5h Usage Log</h1>
            <p>API-equivalent estimate using fresh input, cached input, and output token pricing. Subscription usage may not map directly to API billing.</p>
            \(latestCards)
            <table>
              <thead>
                <tr>
                  <th>Window</th>
                  <th>Start-End</th>
                  <th>Recorded</th>
                  <th class="num">Sessions</th>
                  <th class="num">Fresh</th>
                  <th class="num">Cached</th>
                  <th class="num">Output</th>
                  <th class="num">Total</th>
                  <th class="num">Cache</th>
                  <th class="num">API Est.</th>
                </tr>
              </thead>
              <tbody>
                \(rows)
              </tbody>
            </table>
            <footer>Raw JSONL: <a href="file://\(html(rawLogURL.path))">\(html(rawLogURL.path))</a></footer>
          </main>
        </body>
        </html>
        """
    }

    private static func tokenString(_ value: UInt64) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private static func dollarString(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "$%.0f", value)
        }
        if value >= 10 {
            return String(format: "$%.1f", value)
        }
        return String(format: "$%.2f", value)
    }

    private static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private static func dateRange(_ start: Date, _ end: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "MMM d, h:mm a"
            let startText = formatter.string(from: start)
            formatter.dateFormat = "h:mm a"
            return "\(startText)-\(formatter.string(from: end))"
        }

        formatter.dateFormat = "MMM d, h:mm a"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }

    private static func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-6_000), primaryRemainingPercent: 99, weeklyRemainingPercent: 84, planType: "plus"),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-5_340), primaryRemainingPercent: 92, weeklyRemainingPercent: 83, planType: "plus"),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-4_680), primaryRemainingPercent: 56, weeklyRemainingPercent: 77, planType: "plus"),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-4_080), primaryRemainingPercent: 34, weeklyRemainingPercent: 74, planType: "plus"),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-3_420), primaryRemainingPercent: 11, weeklyRemainingPercent: 70, planType: "plus"),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-2_760), primaryRemainingPercent: 0, weeklyRemainingPercent: 68, planType: "plus"),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-2_100), primaryRemainingPercent: 0, weeklyRemainingPercent: 68, planType: "plus"),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-1_440), primaryRemainingPercent: 99, weeklyRemainingPercent: 100, planType: "prolite")
    ]
}

extension LLMUsageSnapshot {
    static let empty = LLMUsageSnapshot(
        email: nil,
        planType: nil,
        limits: [],
        creditsBalance: nil,
        resetCreditCount: nil,
        resetCreditExpirations: [],
        lastUpdated: nil,
        localFiveHourTokens: 0,
        localWeeklyTokens: 0,
        localWeeklyThreads: 0,
        localWindows: [],
        costEstimates: [],
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
        resetCreditCount: 2,
        resetCreditExpirations: [
            LLMResetCreditExpiration(count: 1, expiresAt: Date().addingTimeInterval(86_400 * 6)),
            LLMResetCreditExpiration(count: 1, expiresAt: Date().addingTimeInterval(86_400 * 13))
        ],
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
        costEstimates: [
            LLMTokenCostEstimate(
                label: "5h",
                sessionCount: 6,
                inputTokens: 95_000_000,
                cachedInputTokens: 88_000_000,
                outputTokens: 420_000,
                totalTokens: 95_420_000,
                windowStartedAt: Date().addingTimeInterval(-18_000),
                windowEndedAt: Date()
            ),
            LLMTokenCostEstimate(
                label: "Weekly",
                sessionCount: 17,
                inputTokens: 126_800_000,
                cachedInputTokens: 120_200_000,
                outputTokens: 289_600,
                totalTokens: 127_089_600,
                windowStartedAt: Date().addingTimeInterval(-604_800),
                windowEndedAt: Date()
            )
        ],
        recentSessions: [
            LLMUsageSession(
                id: "demo-1",
                title: "MaxxBar LLM usage tab",
                projectName: "MaxxBar",
                modelName: "GPT-5 Codex",
                preview: "Added usage windows and advanced local session detail.",
                rolloutPath: "",
                tokens: 84_200_000,
                tokenUsage: LLMTokenUsageSummary(inputTokens: 70_000_000, cachedInputTokens: 48_000_000, outputTokens: 10_000_000, reasoningOutputTokens: 4_200_000, totalTokens: 84_200_000, turnCount: 28),
                createdAt: Date().addingTimeInterval(-8_400),
                updatedAt: Date().addingTimeInterval(-420)
            ),
            LLMUsageSession(
                id: "demo-2",
                title: "Sensor helper",
                projectName: "MaxxBar",
                modelName: "GPT-5 Codex",
                preview: "Built native helper for thermal and fan data.",
                rolloutPath: "",
                tokens: 31_500_000,
                tokenUsage: LLMTokenUsageSummary(inputTokens: 25_000_000, cachedInputTokens: 16_000_000, outputTokens: 4_500_000, reasoningOutputTokens: 2_000_000, totalTokens: 31_500_000, turnCount: 12),
                createdAt: Date().addingTimeInterval(-10_200),
                updatedAt: Date().addingTimeInterval(-7_200)
            )
        ],
        topWeeklySessions: [
            LLMUsageSession(
                id: "demo-1",
                title: "MaxxBar LLM usage tab",
                projectName: "MaxxBar",
                modelName: "GPT-5 Codex",
                preview: "Added usage windows and advanced local session detail.",
                rolloutPath: "",
                tokens: 84_200_000,
                tokenUsage: LLMTokenUsageSummary(inputTokens: 70_000_000, cachedInputTokens: 48_000_000, outputTokens: 10_000_000, reasoningOutputTokens: 4_200_000, totalTokens: 84_200_000, turnCount: 28),
                createdAt: Date().addingTimeInterval(-8_400),
                updatedAt: Date().addingTimeInterval(-420)
            ),
            LLMUsageSession(
                id: "demo-3",
                title: "CPU/GPU panel",
                projectName: "MaxxBar",
                modelName: "GPT-5 Codex",
                preview: "Compared CPU and GPU data with iStat style panels.",
                rolloutPath: "",
                tokens: 58_700_000,
                tokenUsage: LLMTokenUsageSummary(inputTokens: 47_000_000, cachedInputTokens: 30_000_000, outputTokens: 7_400_000, reasoningOutputTokens: 4_300_000, totalTokens: 58_700_000, turnCount: 19),
                createdAt: Date().addingTimeInterval(-90_000),
                updatedAt: Date().addingTimeInterval(-86_400)
            )
        ],
        error: nil
    )
}

extension AIUsageSnapshot {
    static let empty = AIUsageSnapshot(
        sampledAt: nil,
        activeApp: "Unknown",
        activeSite: nil,
        activeTool: nil,
        activeSurface: nil,
        activeUseCase: "Unknown",
        sessionsToday: 0,
        sessionsSevenDays: 0,
        timeTodaySeconds: 0,
        timeSevenDaysSeconds: 0,
        averageSessionSeconds: 0,
        contextConfidence: "None",
        topTools: [],
        topBeforeApps: [],
        topAfterApps: [],
        workflowPaths: [],
        copyEventsToday: 0,
        pasteEventsToday: 0,
        topCopiedFrom: [],
        topPastedInto: [],
        transferFlows: [],
        momentsToday: 0,
        lastMomentAt: nil,
        recentMoments: [],
        lastError: nil
    )

    static let demo = AIUsageSnapshot(
        sampledAt: Date(),
        activeApp: "Codex",
        activeSite: "chatgpt.com/codex",
        activeTool: "Codex",
        activeSurface: "Codex web",
        activeUseCase: "Coding",
        sessionsToday: 7,
        sessionsSevenDays: 24,
        timeTodaySeconds: 7_820,
        timeSevenDaysSeconds: 42_600,
        averageSessionSeconds: 1_775,
        contextConfidence: "High",
        topTools: [
            AIUsageCounter(label: "Codex", count: 12),
            AIUsageCounter(label: "ChatGPT", count: 8),
            AIUsageCounter(label: "Claude", count: 4)
        ],
        topBeforeApps: [
            AIUsageCounter(label: "Terminal", count: 6),
            AIUsageCounter(label: "GitHub", count: 4),
            AIUsageCounter(label: "Gmail", count: 3)
        ],
        topAfterApps: [
            AIUsageCounter(label: "Xcode", count: 5),
            AIUsageCounter(label: "Markdown Viewer", count: 4),
            AIUsageCounter(label: "Google Chrome", count: 3)
        ],
        workflowPaths: [
            AIWorkflowPath(before: "Terminal", surface: "Codex web", after: "Xcode", useCase: "Coding", count: 5),
            AIWorkflowPath(before: "Gmail", surface: "ChatGPT web", after: "Google Docs", useCase: "Email / comms", count: 3)
        ],
        copyEventsToday: 9,
        pasteEventsToday: 7,
        topCopiedFrom: [
            AIUsageCounter(label: "Codex client", count: 5),
            AIUsageCounter(label: "ChatGPT web", count: 2)
        ],
        topPastedInto: [
            AIUsageCounter(label: "Xcode", count: 4),
            AIUsageCounter(label: "Google Docs", count: 2)
        ],
        transferFlows: [
            AITransferFlow(source: "Codex client", destination: "Xcode", useCase: "Coding", count: 4, confidence: "High"),
            AITransferFlow(source: "ChatGPT web", destination: "Google Docs", useCase: "Docs / writing", count: 2, confidence: "High")
        ],
        momentsToday: 2,
        lastMomentAt: Date().addingTimeInterval(-1_800),
        recentMoments: [
            MaxxMomentSummary(
                ts: Date().addingTimeInterval(-1_800),
                sentiment: "Frustration",
                app: "Codex",
                surface: "Codex web",
                note: "Missed local app context",
                screenshotPath: nil
            ),
            MaxxMomentSummary(
                ts: Date().addingTimeInterval(-7_200),
                sentiment: "Delight",
                app: "ChatGPT",
                surface: "ChatGPT web",
                note: "Found the right framing quickly",
                screenshotPath: nil
            )
        ],
        lastError: nil
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

    static let demo = SensorSnapshot(
        cpuTemperature: 67,
        gpuTemperature: 52,
        batteryTemperature: 30,
        fanPercent: 0,
        fanRPM: nil,
        fanReadings: [],
        temperatureReadings: [
            TemperatureReading(label: "Airflow", celsius: 46.7),
            TemperatureReading(label: "Battery", celsius: 30),
            TemperatureReading(label: "CPU Efficiency Cores", celsius: 66.8),
            TemperatureReading(label: "CPU Performance Cores", celsius: 67.2),
            TemperatureReading(label: "Graphics", celsius: 51.7),
            TemperatureReading(label: "Palm Rest", celsius: 27.8),
            TemperatureReading(label: "SSD", celsius: 32.2),
            TemperatureReading(label: "Wi-Fi", celsius: 47.2)
        ],
        amperage: 1.0,
        power: 28,
        voltage: 19.6,
        frequencyGHz: 3.08,
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

enum AIUsageReader {
    private struct ActiveContext {
        let app: String
        let bundleID: String
        let url: String?
        let title: String?
        let site: String?
        let tool: String?
        let surface: String?
        let useCase: String
    }

    private struct AIActivityRecord: Codable {
        var ts: Date
        var app: String
        var bundleID: String
        var url: String?
        var title: String?
        var site: String?
        var tool: String?
        var surface: String?
        var useCase: String
        var memoryPressurePercent: Int
        var memoryUsedPercent: Int
        var cpuUserPercent: Int
        var cpuSystemPercent: Int
        var codexFiveHourRemainingPercent: Int?
        var codexWeeklyRemainingPercent: Int?
    }

    private struct MaxxMomentRecord: Codable {
        var ts: Date
        var app: String
        var bundleID: String
        var site: String?
        var tool: String?
        var surface: String?
        var useCase: String
        var sentiment: String?
        var screenshotPath: String?
        var memoryPressurePercent: Int
        var memoryUsedPercent: Int
        var cpuUserPercent: Int
        var cpuSystemPercent: Int
        var codexFiveHourRemainingPercent: Int?
        var codexWeeklyRemainingPercent: Int?
        var note: String
    }

    private struct AITransferRecord: Codable {
        var eventType: String
        var ts: Date
        var app: String
        var bundleID: String
        var site: String?
        var url: String?
        var title: String?
        var tool: String?
        var surface: String?
        var useCase: String
        var sourceApp: String?
        var sourceBundleID: String?
        var sourceSite: String?
        var sourceURL: String?
        var sourceTitle: String?
        var sourceTool: String?
        var sourceSurface: String?
        var sourceTS: Date?
        var privacy: String
    }

    nonisolated(unsafe) private static var lastCopyRecord: AITransferRecord?
    nonisolated(unsafe) private static var lastTransferSignature: String?
    nonisolated(unsafe) private static var lastTransferAt: Date?
    private static let transferLock = NSLock()

    static func recordAndRead(memory: MemorySnapshot, cpuGPU: CPUGPUSnapshot, llmUsage: LLMUsageSnapshot) -> AIUsageSnapshot {
        let context = activeContext()
        let record = record(from: context, memory: memory, cpuGPU: cpuGPU, llmUsage: llmUsage)
        append(record, to: activityLogURL)
        return snapshot(current: record, error: nil)
    }

    static func recordClipboardEvent(_ eventType: String) -> AIUsageSnapshot {
        let context = activeContext()
        let now = Date()
        let signature = "\(eventType)|\(context.bundleID)|\(context.url ?? "")"

        transferLock.lock()
        defer { transferLock.unlock() }

        if lastTransferSignature == signature,
           let lastTransferAt,
           now.timeIntervalSince(lastTransferAt) < 0.75 {
            return snapshot(current: recentActivityRecords(days: 7).max { $0.ts < $1.ts }, error: nil)
        }

        let source = eventType == "paste" ? lastCopyRecord : nil
        let hasFreshSource = source.map { now.timeIntervalSince($0.ts) <= 86_400 } ?? false
        let record = AITransferRecord(
            eventType: eventType,
            ts: now,
            app: context.app,
            bundleID: context.bundleID,
            site: context.site,
            url: context.url,
            title: context.title,
            tool: context.tool,
            surface: context.surface,
            useCase: AITaxonomy.useCase(
                before: hasFreshSource ? (source?.sourceSurface ?? source?.surface ?? source?.sourceApp ?? source?.app) : nil,
                surface: hasFreshSource ? (source?.sourceSurface ?? source?.surface) : context.surface,
                after: context.site ?? context.app
            ),
            sourceApp: hasFreshSource ? source?.app : nil,
            sourceBundleID: hasFreshSource ? source?.bundleID : nil,
            sourceSite: hasFreshSource ? source?.site : nil,
            sourceURL: hasFreshSource ? source?.url : nil,
            sourceTitle: hasFreshSource ? source?.title : nil,
            sourceTool: hasFreshSource ? source?.tool : nil,
            sourceSurface: hasFreshSource ? source?.surface : nil,
            sourceTS: hasFreshSource ? source?.ts : nil,
            privacy: "no_clipboard_content"
        )
        append(record, to: transfersLogURL)
        if eventType == "copy" { lastCopyRecord = record }
        lastTransferSignature = signature
        lastTransferAt = now
        return snapshot(current: recentActivityRecords(days: 7).max { $0.ts < $1.ts }, error: nil)
    }

    static func captureMoment(
        memory: MemorySnapshot,
        cpuGPU: CPUGPUSnapshot,
        llmUsage: LLMUsageSnapshot,
        sentiment: String,
        note: String,
        includeScreenshot: Bool
    ) -> AIUsageSnapshot {
        let context = activeContext()
        let record = record(from: context, memory: memory, cpuGPU: cpuGPU, llmUsage: llmUsage)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let screenshotPath = includeScreenshot ? captureScreenshot(at: record.ts) : nil
        append(record, to: activityLogURL)
        append(
            MaxxMomentRecord(
                ts: record.ts,
                app: record.app,
                bundleID: record.bundleID,
                site: record.site,
                tool: record.tool,
                surface: record.surface,
                useCase: record.useCase,
                sentiment: sentiment,
                screenshotPath: screenshotPath,
                memoryPressurePercent: record.memoryPressurePercent,
                memoryUsedPercent: record.memoryUsedPercent,
                cpuUserPercent: record.cpuUserPercent,
                cpuSystemPercent: record.cpuSystemPercent,
                codexFiveHourRemainingPercent: record.codexFiveHourRemainingPercent,
                codexWeeklyRemainingPercent: record.codexWeeklyRemainingPercent,
                note: cleanNote.isEmpty ? sentiment : cleanNote
            ),
            to: momentsLogURL
        )
        return snapshot(current: record, error: nil)
    }

    static func writeReport() -> URL? {
        guard let url = reportURL else { return nil }
        let records = recentActivityRecords(days: 7)
        let moments = recentMomentRecords(days: 7)
        let transfers = recentTransferRecords(days: 7)
        let llmUsage = LLMUsageReader.read()
        let quotaHistory = recentQuotaHistory()
        let html = reportHTML(records: records, moments: moments, transfers: transfers, llmUsage: llmUsage, quotaHistory: quotaHistory)

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            writeHubIcon(to: url.deletingLastPathComponent())
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func record(
        from context: ActiveContext,
        memory: MemorySnapshot,
        cpuGPU: CPUGPUSnapshot,
        llmUsage: LLMUsageSnapshot
    ) -> AIActivityRecord {
        let codexLimit = llmUsage.limits.first(where: { $0.name == "Codex" }) ?? llmUsage.limits.first
        return AIActivityRecord(
            ts: Date(),
            app: context.app,
            bundleID: context.bundleID,
            url: context.url,
            title: context.title,
            site: context.site,
            tool: context.tool,
            surface: context.surface,
            useCase: context.useCase,
            memoryPressurePercent: memory.pressurePercent,
            memoryUsedPercent: memory.usedPercent,
            cpuUserPercent: cpuGPU.cpuUserPercent,
            cpuSystemPercent: cpuGPU.cpuSystemPercent,
            codexFiveHourRemainingPercent: codexLimit?.primary?.remainingPercent,
            codexWeeklyRemainingPercent: codexLimit?.secondary?.remainingPercent
        )
    }

    private static func snapshot(current: AIActivityRecord?, error: String?) -> AIUsageSnapshot {
        let records = recentActivityRecords(days: 7)
        let moments = recentMomentRecords(days: 7)
        let transfers = recentTransferRecords(days: 7)
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let todayRecords = records.filter { $0.ts >= startOfDay }
        let aiRecords = records.filter { $0.tool != nil }
        let todayAIRecords = todayRecords.filter { $0.tool != nil }
        let sevenDaySessions = sessions(from: records)
        let todaySessions = sessions(from: todayRecords)
        let workflows = workflowCounters(from: records)
        let confidence = contextConfidence(workflows: workflows, aiRecords: aiRecords)
        let todayTransfers = transfers.filter { $0.ts >= startOfDay }
        let transferFlows = topTransferFlows(transfers)

        return AIUsageSnapshot(
            sampledAt: current?.ts,
            activeApp: current?.app ?? "Unknown",
            activeSite: current?.site,
            activeTool: current?.tool,
            activeSurface: current?.surface,
            activeUseCase: current?.useCase ?? "Unknown",
            sessionsToday: todaySessions.count,
            sessionsSevenDays: sevenDaySessions.count,
            timeTodaySeconds: inferredAISeconds(todayAIRecords),
            timeSevenDaysSeconds: inferredAISeconds(aiRecords),
            averageSessionSeconds: sevenDaySessions.isEmpty ? 0 : inferredAISeconds(aiRecords) / Double(sevenDaySessions.count),
            contextConfidence: confidence,
            topTools: counters(aiRecords.compactMap(\.tool), limit: 4),
            topBeforeApps: counters(workflows.map(\.before), limit: 4),
            topAfterApps: counters(workflows.map(\.after), limit: 4),
            workflowPaths: topWorkflowPaths(workflows),
            copyEventsToday: todayTransfers.filter { $0.eventType == "copy" }.count,
            pasteEventsToday: todayTransfers.filter { $0.eventType == "paste" }.count,
            topCopiedFrom: counters(transfers.filter { $0.eventType == "copy" }.map(transferSourceLabel), limit: 4),
            topPastedInto: counters(transfers.filter { $0.eventType == "paste" && $0.sourceTool != nil }.map(transferDestinationLabel), limit: 4),
            transferFlows: transferFlows,
            momentsToday: moments.filter { $0.ts >= startOfDay }.count,
            lastMomentAt: moments.map(\.ts).max(),
            recentMoments: moments
                .sorted { $0.ts > $1.ts }
                .prefix(3)
                .map {
                    MaxxMomentSummary(
                        ts: $0.ts,
                        sentiment: $0.sentiment ?? "Frustration",
                        app: $0.app,
                        surface: $0.surface ?? $0.tool ?? $0.site,
                        note: $0.note,
                        screenshotPath: $0.screenshotPath
                    )
                },
            lastError: error
        )
    }

    private static func activeContext() -> ActiveContext {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        let bundleID = app?.bundleIdentifier ?? ""
        let browser = browserContext(appName: appName, bundleID: bundleID)
        let site = browser.url.flatMap(AITaxonomy.siteLabel)
        let toolInfo = AITaxonomy.tool(appName: appName, url: browser.url)
        let useCase = AITaxonomy.useCase(before: appName, surface: toolInfo.surface, after: site)
        return ActiveContext(
            app: site ?? appName,
            bundleID: bundleID,
            url: browser.url,
            title: browser.title,
            site: site,
            tool: toolInfo.tool,
            surface: toolInfo.surface,
            useCase: useCase
        )
    }

    private static func browserContext(appName: String, bundleID: String) -> (url: String?, title: String?) {
        guard bundleID == "com.google.Chrome" || bundleID == "com.google.Chrome.canary" || bundleID == "company.thebrowser.Browser" else {
            return (nil, nil)
        }

        let target = bundleID == "company.thebrowser.Browser" || appName.localizedCaseInsensitiveContains("Arc")
            ? "Arc"
            : "Google Chrome"
        let script = """
        tell application "\(target)"
          if (count of windows) is 0 then return ""
          set activeUrl to URL of active tab of front window
          set activeTitle to title of active tab of front window
          return activeUrl & "\n" & activeTitle
        end tell
        """
        let output = runProcess("/usr/bin/osascript", arguments: ["-e", script])
        let parts = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let url = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (url?.isEmpty == true ? nil : url, title?.isEmpty == true ? nil : title)
    }

    private static func aiTool(appName: String, url: String?) -> (tool: String?, surface: String?) {
        AITaxonomy.tool(appName: appName, url: url)
    }

    private static func siteLabel(_ url: String) -> String? {
        AITaxonomy.siteLabel(url)
    }

    private static func useCase(before: String?, surface: String?, after: String?) -> String {
        AITaxonomy.useCase(before: before, surface: surface, after: after)
    }

    private static func sessions(from records: [AIActivityRecord]) -> [[AIActivityRecord]] {
        let aiRecords = records.filter { $0.tool != nil }.sorted { $0.ts < $1.ts }
        var sessions: [[AIActivityRecord]] = []
        for record in aiRecords {
            if let last = sessions.last?.last, record.ts.timeIntervalSince(last.ts) <= 300 {
                sessions[sessions.count - 1].append(record)
            } else {
                sessions.append([record])
            }
        }
        return sessions
    }

    private static func inferredAISeconds(_ records: [AIActivityRecord]) -> TimeInterval {
        let sorted = records.sorted { $0.ts < $1.ts }
        guard !sorted.isEmpty else { return 0 }
        var total: TimeInterval = 0
        for index in sorted.indices {
            if index < sorted.index(before: sorted.endIndex) {
                total += min(max(sorted[sorted.index(after: index)].ts.timeIntervalSince(sorted[index].ts), 15), 120)
            } else {
                total += 15
            }
        }
        return total
    }

    private static func workflowCounters(from records: [AIActivityRecord]) -> [AIWorkflowPath] {
        let sorted = records.sorted { $0.ts < $1.ts }
        var counts: [String: (before: String, surface: String, after: String, useCase: String, count: Int)] = [:]

        for run in aiRuns(in: sorted) {
            let before = nearestNonAI(in: sorted, from: run.start, step: -1, within: 600) ?? "Start"
            let after = nearestNonAI(in: sorted, from: run.end, step: 1, within: 600) ?? "End"
            let surface = sorted[run.start].surface ?? sorted[run.start].tool ?? "AI"
            let useCase = useCase(before: before, surface: surface, after: after)
            let key = "\(before)|\(surface)|\(after)|\(useCase)"
            var current = counts[key] ?? (before, surface, after, useCase, 0)
            current.count += 1
            counts[key] = current
        }

        return counts.values.map {
            AIWorkflowPath(before: $0.before, surface: $0.surface, after: $0.after, useCase: $0.useCase, count: $0.count)
        }
    }

    private static func aiRuns(in records: [AIActivityRecord]) -> [(start: Int, end: Int)] {
        var runs: [(start: Int, end: Int)] = []
        for index in records.indices where records[index].tool != nil {
            if let last = runs.last,
               records[index].ts.timeIntervalSince(records[last.end].ts) <= 300 {
                runs[runs.count - 1] = (last.start, index)
            } else {
                runs.append((index, index))
            }
        }
        return runs
    }

    private static func nearestNonAI(in records: [AIActivityRecord], from index: Int, step: Int, within seconds: TimeInterval) -> String? {
        var cursor = index + step
        let anchor = records[index].ts
        while records.indices.contains(cursor) {
            if records[cursor].tool == nil {
                guard abs(records[cursor].ts.timeIntervalSince(anchor)) <= seconds else { return nil }
                return records[cursor].site ?? records[cursor].app
            }
            cursor += step
        }
        return nil
    }

    private static func counters(_ values: [String], limit: Int) -> [AIUsageCounter] {
        let counts = Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(limit)
            .map { AIUsageCounter(label: $0.key, count: $0.value) }
    }

    private static func topWorkflowPaths(_ workflows: [AIWorkflowPath]) -> [AIWorkflowPath] {
        workflows
            .sorted { lhs, rhs in lhs.count == rhs.count ? lhs.id < rhs.id : lhs.count > rhs.count }
            .prefix(6)
            .map { $0 }
    }

    private static func topTransferFlows(_ transfers: [AITransferRecord]) -> [AITransferFlow] {
        let pasteEvents = transfers.filter { $0.eventType == "paste" && $0.sourceTool != nil }
        var counts: [String: (source: String, destination: String, useCase: String, count: Int)] = [:]
        for event in pasteEvents {
            let source = event.sourceSurface ?? event.sourceTool ?? event.sourceSite ?? event.sourceApp ?? "Unknown"
            let destination = transferDestinationLabel(event)
            let key = "\(source)|\(destination)|\(event.useCase)"
            var value = counts[key] ?? (source, destination, event.useCase, 0)
            value.count += 1
            counts[key] = value
        }
        return counts.values
            .sorted { lhs, rhs in lhs.count == rhs.count ? lhs.destination < rhs.destination : lhs.count > rhs.count }
            .prefix(8)
            .map { AITransferFlow(source: $0.source, destination: $0.destination, useCase: $0.useCase, count: $0.count, confidence: "High") }
    }

    private static func transferSourceLabel(_ record: AITransferRecord) -> String {
        record.surface ?? record.tool ?? record.site ?? record.app
    }

    private static func transferDestinationLabel(_ record: AITransferRecord) -> String {
        record.surface ?? record.tool ?? record.site ?? record.app
    }

    private static func contextConfidence(workflows: [AIWorkflowPath], aiRecords: [AIActivityRecord]) -> String {
        guard !aiRecords.isEmpty else { return "None" }
        if workflows.contains(where: { $0.before != "Start" && $0.after != "End" }) { return "High" }
        if workflows.contains(where: { $0.before != "Start" || $0.after != "End" }) { return "Medium" }
        return "Low"
    }

    private static func recentActivityRecords(days: Int) -> [AIActivityRecord] {
        readJSONLines(AIActivityRecord.self, from: activityLogURL, days: days)
    }

    private static func recentMomentRecords(days: Int) -> [MaxxMomentRecord] {
        readJSONLines(MaxxMomentRecord.self, from: momentsLogURL, days: days)
    }

    private static func recentTransferRecords(days: Int) -> [AITransferRecord] {
        readJSONLines(AITransferRecord.self, from: transfersLogURL, days: days)
    }

    private static func recentQuotaHistory() -> [LLMQuotaHistorySample] {
        guard let directory = supportDirectoryURL,
              let data = try? Data(contentsOf: directory.appendingPathComponent("llm-quota-history.json")),
              let samples = try? JSONDecoder().decode([LLMQuotaHistorySample].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return samples.filter { $0.sampledAt >= cutoff }.sorted { $0.sampledAt < $1.sampledAt }
    }

    private static func captureScreenshot(at date: Date) -> String? {
        guard let directory = supportDirectoryURL?.appendingPathComponent("maxx-moment-screenshots") else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filename = "maxx-moment-\(Int(date.timeIntervalSince1970)).png"
            let url = directory.appendingPathComponent(filename)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", url.path]
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path) ? url.path : nil
        } catch {
            return nil
        }
    }

    private static func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL?, days: Int) -> [T] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let record = try? decoder.decode(T.self, from: data) else {
                    return nil
                }
                if let activity = record as? AIActivityRecord { return activity.ts >= cutoff ? record : nil }
                if let moment = record as? MaxxMomentRecord { return moment.ts >= cutoff ? record : nil }
                if let transfer = record as? AITransferRecord { return transfer.ts >= cutoff ? record : nil }
                return record
            }
    }

    private static func append<T: Encodable>(_ value: T, to url: URL?) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        } catch {
            return
        }
    }

    private static func runProcess(_ path: String, arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static var supportDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MaxxBar", isDirectory: true)
    }

    private static var activityLogURL: URL? {
        supportDirectoryURL?.appendingPathComponent("ai-activity.jsonl")
    }

    private static var momentsLogURL: URL? {
        supportDirectoryURL?.appendingPathComponent("maxx-moments.jsonl")
    }

    private static var transfersLogURL: URL? {
        supportDirectoryURL?.appendingPathComponent("ai-transfers.jsonl")
    }

    private static var reportURL: URL? {
        supportDirectoryURL?.appendingPathComponent("maxxbar-hub.html")
    }

    private static func writeHubIcon(to directory: URL) {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            sourceRoot.appendingPathComponent("Assets/AppIcon.iconset/icon_128x128.png"),
            FileManager.default.currentDirectoryPath.isEmpty ? nil : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/AppIcon.iconset/icon_128x128.png")
        ].compactMap { $0 }

        guard let source = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: source) else { return }

        let size = NSSize(width: 96, height: 96)
        let rendered = NSImage(size: size)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        rendered.unlockFocus()

        guard let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("maxxbar-hub-icon.png"), options: .atomic)
    }

    private static func reportHTML(records: [AIActivityRecord], moments: [MaxxMomentRecord], transfers: [AITransferRecord], llmUsage: LLMUsageSnapshot, quotaHistory: [LLMQuotaHistorySample]) -> String {
        let aiRecords = records.filter { $0.tool != nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayAIRecords = aiRecords.filter { $0.ts >= startOfDay }
        let workflows = topWorkflowPaths(workflowCounters(from: records))
        let transferFlows = topTransferFlows(transfers)
        let topTools = counters(aiRecords.compactMap(\.tool), limit: 8)
        let todayTools = counters(todayAIRecords.compactMap(\.tool), limit: 8)
        let before = counters(workflows.map(\.before), limit: 8)
        let after = counters(workflows.map(\.after), limit: 8)
        let useCases = counters(aiRecords.map(\.useCase), limit: 8)
        let outputDestinations = counters(transfers.filter { $0.eventType == "paste" && $0.sourceTool != nil }.map(transferDestinationLabel), limit: 8)
        let totalAISeconds = inferredAISeconds(aiRecords)
        let sessionCount = sessions(from: records).count
        let todaySessionCount = sessions(from: todayAIRecords).count
        let todayMomentCount = moments.filter { $0.ts >= startOfDay }.count
        let todayTransferEventCount = transfers.filter { $0.ts >= startOfDay }.count
        let insightEventCount = todaySessionCount + todayMomentCount + todayTransferEventCount
        let latest = records.sorted { $0.ts < $1.ts }.last
        let codexLimit = llmUsage.limits.first(where: { $0.name == "Codex" }) ?? llmUsage.limits.first
        let remaining = codexLimit?.primary?.remainingPercent
        let runwayLabel = remaining.map { $0 <= 10 ? "Critical" : ($0 <= 25 ? "Watch" : "Healthy") } ?? "Unavailable"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>MaxxBar Hub</title>
          <link rel="icon" type="image/png" href="maxxbar-hub-icon.png">
          <style>
            :root{color-scheme:dark;--bg:#111315;--panel:#181b1e;--panel2:#21252a;--text:#f0f2f5;--muted:#b8bec7;--line:#2d3135;--line2:#3a3f46;--accent:#c8f060;--top:rgba(17,19,21,.92)}
            :root[data-theme=light]{color-scheme:light;--bg:#faf8f3;--panel:#fff;--panel2:#f3f0e9;--text:#20231f;--muted:#646a61;--line:#ddd9cf;--line2:#cbc6ba;--accent:#6c850d;--top:rgba(250,248,243,.92)}
            *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;line-height:1.45}
            .topline{position:sticky;top:0;z-index:10;min-height:64px;display:flex;align-items:center;gap:18px;padding:0 30px;background:var(--top);border-bottom:1px solid var(--line);backdrop-filter:blur(14px)}.brand{display:flex;align-items:center;gap:10px;font-weight:750}.brand-logo{width:38px;height:38px;display:block;border-radius:10px;object-fit:cover}.tabs{display:flex;gap:4px}.tabs a{color:var(--muted);text-decoration:none;padding:7px 10px;border-radius:7px;font-size:12px;font-weight:700}.tabs a:hover{background:var(--panel2);color:var(--text)}.spacer{flex:1}.theme{border:1px solid var(--line2);background:var(--panel2);color:var(--text);border-radius:8px;padding:7px 10px;cursor:pointer}.content{max-width:1280px;margin:auto;padding:28px 30px 48px}
            h1{margin:0 0 4px;font-size:30px}h2{font-size:15px;text-transform:uppercase;letter-spacing:.08em;margin:0 0 12px;color:var(--accent)}
            .sub{color:var(--muted);margin:0 0 22px}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:18px}.card,.panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px}.card span{display:block;color:var(--muted);font-size:12px}.card strong{display:block;font-size:24px;margin-top:4px}.two{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:18px}.list div{display:flex;justify-content:space-between;gap:16px;padding:8px 0;border-bottom:1px solid var(--line)}.list div:last-child{border-bottom:0}.list span{color:var(--muted);font-variant-numeric:tabular-nums}.paths div,.ai-path-top div{display:flex;align-items:center;gap:7px;flex-wrap:wrap;padding:8px 0;border-bottom:1px solid var(--line);color:var(--muted);font-size:12px}.paths em,.ai-path-top em{font:700 10px/1 ui-monospace,SFMono-Regular,Menlo,monospace;font-style:normal;color:var(--muted)}.paths span,.ai-path-top span{color:var(--accent);font-weight:900}.ai-path-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:12px}.ai-path-head h2{margin:0 0 6px}.ai-path-head p{margin:0;color:var(--muted)}.ai-path-head strong{font:800 12px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--accent);background:rgba(200,240,96,.10);border-radius:999px;padding:7px 10px;white-space:nowrap}.ai-sankey-wrap{overflow-x:auto;border:1px solid var(--line);border-radius:8px;background:var(--panel2);padding:10px}.ai-sankey{display:block;min-width:860px;width:100%;height:auto}.ai-sankey-stage{fill:var(--muted);font:800 11px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.12em;text-transform:uppercase}.ai-sankey-link{fill:none;stroke:var(--accent);stroke-linecap:round;opacity:.18}.ai-sankey-link:hover{opacity:.38}.ai-sankey-node{fill:var(--accent);opacity:.58}.ai-sankey-icon text{font:800 7px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:0}.ai-sankey-label{fill:var(--text);font:600 12px/1 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}.ai-sankey-count{fill:var(--muted);font:650 10px/1 ui-monospace,SFMono-Regular,Menlo,monospace}.ai-path-top{display:grid;gap:2px;margin-top:12px}.footer{margin-top:20px;color:var(--muted);font-size:12px}.flows{display:grid;gap:8px}.flow{display:grid;grid-template-columns:minmax(0,1fr) 24px minmax(0,1fr) auto;gap:8px;align-items:center;padding:10px;background:var(--panel2);border-radius:7px}.arrow{color:var(--accent);font-weight:900}.badge{font:750 10px ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--accent)}@media(max-width:760px){.topline{padding:12px 18px;flex-wrap:wrap}.tabs{order:3;width:100%;overflow:auto}.content{padding:22px 18px}.grid,.two{grid-template-columns:1fr 1fr}.flow{grid-template-columns:1fr 20px 1fr}.flow .badge{grid-column:1/-1}}
            .tabs button{border:0;background:transparent;color:var(--muted);padding:8px 11px;border-radius:7px;font:700 12px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;cursor:pointer;white-space:nowrap}.tabs button:hover{background:var(--panel2);color:var(--text)}.tabs button.active{background:var(--accent);color:#15170f}.hub-page{display:none}.hub-page.active{display:block}.page-head{margin:0 0 22px;padding-bottom:18px;border-bottom:1px solid var(--line)}.page-head h1{font-size:32px;margin:0 0 6px}.page-head p{margin:0;color:var(--muted);max-width:760px}.page-kicker{display:block;color:var(--accent);font:800 11px ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.12em;text-transform:uppercase;margin-bottom:7px}.panel{margin-bottom:18px}.meter{height:8px;background:var(--panel2);border-radius:99px;overflow:hidden;margin:7px 0 4px}.meter span{display:block;height:100%;background:var(--accent);border-radius:99px}.metric-row{display:grid;grid-template-columns:minmax(140px,1fr) minmax(160px,2fr) auto;gap:14px;align-items:center;padding:10px 0;border-bottom:1px solid var(--line)}.metric-row:last-child{border-bottom:0}.metric-row small,.detail-grid dt{color:var(--muted)}.metric-row strong,.num{font-variant-numeric:tabular-nums}.timeline{display:grid;gap:8px}.timeline-row{display:grid;grid-template-columns:minmax(150px,240px) 1fr auto;gap:12px;align-items:center}.timeline-label strong,.timeline-label small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.timeline-label small{color:var(--muted)}.timeline-track{position:relative;height:18px;background:var(--panel2);border-radius:5px;overflow:hidden}.timeline-bar{position:absolute;top:3px;height:12px;min-width:3px;background:var(--accent);border-radius:4px}.session-list{display:grid;gap:9px}.session{background:var(--panel);border:1px solid var(--line);border-radius:8px;overflow:hidden}.session summary{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:18px;padding:14px;cursor:pointer;list-style:none}.session summary::-webkit-details-marker{display:none}.session summary strong,.session summary small{display:block}.session summary small{color:var(--muted);margin-top:3px}.session[open] summary{border-bottom:1px solid var(--line)}.session-body{padding:14px}.detail-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px 18px;margin:0}.detail-grid div{padding:7px 0;border-bottom:1px solid var(--line)}.detail-grid dt{font-size:11px}.detail-grid dd{margin:3px 0 0;font-weight:650;word-break:break-word}.preview{margin:14px 0 0;padding:12px;background:var(--panel2);border-radius:7px;color:var(--muted);white-space:pre-wrap}.data-table{width:100%;border-collapse:collapse}.data-table th,.data-table td{text-align:left;padding:9px 8px;border-bottom:1px solid var(--line)}.data-table th{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.06em}.data-table td.num,.data-table th.num{text-align:right}.quota-chart{width:100%;height:auto;display:block;background:var(--panel2);border-radius:8px}.quota-primary{fill:none;stroke:var(--accent);stroke-width:3}.quota-weekly{fill:none;stroke:#8bb4ff;stroke-width:2}.chart-grid{stroke:var(--line);stroke-width:1}.legend{display:flex;gap:16px;color:var(--muted);font-size:12px;margin-top:8px}.dot{width:8px;height:8px;border-radius:50%;display:inline-block;margin-right:5px}.moments{display:grid;gap:8px}.moment{display:grid;grid-template-columns:auto 1fr auto;gap:10px;padding:10px;background:var(--panel2);border-radius:7px}.moment span{color:var(--muted)}
            @media(max-width:760px){.detail-grid{grid-template-columns:1fr 1fr}.timeline-row{grid-template-columns:110px 1fr}.timeline-row>.num{display:none}.metric-row{grid-template-columns:1fr auto}.metric-row>.meter-wrap{grid-column:1/-1;grid-row:2}.tabs button{padding:7px 9px}}
          </style>
        </head>
        <body>
          <header class="topline"><div class="brand"><img class="brand-logo" src="maxxbar-hub-icon.png" alt="">MaxxBar</div><nav class="tabs"><button data-page="overview" onclick="showPage('overview')">Overview</button><button data-page="insights" onclick="showPage('insights')">AI Insights</button><button data-page="runway" onclick="showPage('runway')">Runway</button><button data-page="sessions" onclick="showPage('sessions')">Sessions</button><button data-page="advanced" onclick="showPage('advanced')">Advanced</button></nav><span class="spacer"></span><button class="theme" onclick="toggleTheme()">Light / Dark</button></header>
          <main class="content">
          <section id="page-overview" class="hub-page">
            \(pageHeading("Overview", "The complete daily picture: current AI work, runway, patterns, transfers, and recent moments."))
            <div class="grid">
              \(card("AI sessions today", "\(todaySessionCount)", "\(sessionCount) in 7 days"))
              \(card("AI time", duration(totalAISeconds), "sample-inferred · 7 days"))
              \(card("AI transfers", "\(transfers.filter { $0.eventType == "paste" && $0.sourceTool != nil }.count)", "confirmed destinations"))
              \(card("Insight events today", "\(insightEventCount)", "sessions · copy/paste · moments"))
              \(card("Active", html(latest?.tool ?? latest?.app ?? "Unknown"), html(latest?.surface ?? latest?.site ?? "latest sample")))
              \(card("Codex runway", remaining.map { "\($0)%" } ?? "—", runwayLabel))
            </div>
            \(panel("Pattern Summary", patternSummary(todayTools: todayTools, weeklyTools: topTools, useCases: useCases, destinations: outputDestinations)))
            <div class="two">\(panel("Today’s AI Tools", list(todayTools)))\(panel("7-day AI Tools", list(topTools)))</div>
            \(panel("Recent Maxx Moments", momentRows(moments)))
          </section>

          <section id="page-insights" class="hub-page">
            \(pageHeading("AI Insights", "How AI enters your work, which tools you use, and where generated output goes afterward."))
            \(panel("AI Output Destinations", transferRows(transferFlows)))
            <div class="two">\(panel("Likely Use Cases · 7 days", list(useCases)))\(panel("Where AI Output Went", list(outputDestinations)))</div>
            <div class="two">\(panel("Before AI", list(before)))\(panel("After AI", list(after)))</div>
            \(pathVisual(workflows))
            \(panel("Workflow Paths", pathRows(workflows)))
          </section>

          <section id="page-runway" class="hub-page">
            \(pageHeading("Runway", "Live Codex limits, historical drawdown, local usage windows, and the same session timeline available in the menu bar."))
            \(limitPanels(llmUsage))
            \(panel("Limit Drawdown · 7 days", quotaChart(quotaHistory, fallback: llmUsage)))
            \(panel("Session Timeline · 24 hours", sessionTimeline(llmUsage)))
          </section>

          <section id="page-sessions" class="hub-page">
            \(pageHeading("Sessions", "All locally discovered Codex sessions. Expand any row for the complete token, cache, cost, timing, model, project, and preview detail."))
            \(sessionAccordions(llmUsage))
          </section>

          <section id="page-advanced" class="hub-page">
            \(pageHeading("Advanced", "The full diagnostic layer from the dropdown, expanded with complete local windows, cost estimates, limit groups, and data availability."))
            \(advancedSummary(llmUsage))
            \(panel("Local Usage Windows", localWindowTable(llmUsage.localWindows)))
            \(panel("Token and Cost Estimates", costEstimateTable(llmUsage.costEstimates)))
            \(panel("Available Detail", availableDetail(llmUsage)))
          </section>

          <div class="footer">Activity: \(html(activityLogURL?.path ?? "-"))<br>Transfers: \(html(transfersLogURL?.path ?? "-"))<br>Moments: \(html(momentsLogURL?.path ?? "-"))</div>
          </main>
          <script>
          function toggleTheme(){var r=document.documentElement;r.dataset.theme=r.dataset.theme==='light'?'dark':'light';localStorage.setItem('maxxbar:hub:theme',r.dataset.theme)}
          function showPage(name){var page=document.getElementById('page-'+name);if(!page)name='overview';document.querySelectorAll('.hub-page').forEach(function(el){el.classList.toggle('active',el.id==='page-'+name)});document.querySelectorAll('[data-page]').forEach(function(el){el.classList.toggle('active',el.dataset.page===name)});history.replaceState(null,'','#'+name);window.scrollTo(0,0)}
          document.documentElement.dataset.theme=localStorage.getItem('maxxbar:hub:theme')||'dark';showPage((location.hash||'#overview').slice(1));
          </script>
        </body>
        </html>
        """
    }

    private static func card(_ title: String, _ value: String, _ subtitle: String) -> String {
        "<div class=\"card\"><span>\(html(title))</span><strong>\(value)</strong><span>\(html(subtitle))</span></div>"
    }

    private static func panel(_ title: String, _ body: String) -> String {
        "<div class=\"panel\"><h2>\(html(title))</h2>\(body)</div>"
    }

    private static func list(_ rows: [AIUsageCounter]) -> String {
        guard !rows.isEmpty else { return "<p class=\"sub\">No local signals yet.</p>" }
        return "<div class=\"list\">" + rows.map { "<div><strong>\(html($0.label))</strong><span>\($0.count)</span></div>" }.joined() + "</div>"
    }

    private static func pathRows(_ paths: [AIWorkflowPath]) -> String {
        guard !paths.isEmpty else { return "<p class=\"sub\">No before -> AI -> after paths yet.</p>" }
        return "<div class=\"paths\">" + paths.map {
            "<div><strong>\(html($0.before)) -> \(html($0.surface)) -> \(html($0.after))</strong><em>\(html($0.useCase))</em><span>\($0.count)x</span></div>"
        }.joined() + "</div>"
    }

    private static func transferRows(_ flows: [AITransferFlow]) -> String {
        guard !flows.isEmpty else { return "<p class=\"sub\">No AI copy/paste destinations yet. Grant Input Monitoring, then copy from an AI surface and paste into a work app.</p>" }
        return "<div class=\"flows\">" + flows.map {
            "<div class=\"flow\"><strong>\(html($0.source))</strong><span class=\"arrow\">→</span><strong>\(html($0.destination))</strong><span class=\"badge\">\(html($0.useCase)) · \($0.count)x · \(html($0.confidence))</span></div>"
        }.joined() + "</div>"
    }

    private static func patternSummary(todayTools: [AIUsageCounter], weeklyTools: [AIUsageCounter], useCases: [AIUsageCounter], destinations: [AIUsageCounter]) -> String {
        let today = todayTools.first?.label ?? "no detected AI tool"
        let week = weeklyTools.first?.label ?? "no detected AI tool"
        let useCase = useCases.first?.label ?? "no inferred workflow"
        let destination = destinations.first?.label ?? "no confirmed output destination"
        return "<p class=\"sub\">Today’s leading surface is <strong>\(html(today))</strong>. Across seven days, <strong>\(html(week))</strong> leads, the most common inferred work is <strong>\(html(useCase))</strong>, and the top confirmed output destination is <strong>\(html(destination))</strong>.</p>"
    }

    private static func sessionRows(_ sessions: [LLMUsageSession]) -> String {
        guard !sessions.isEmpty else { return "<p class=\"sub\">No recent local Codex sessions found.</p>" }
        return "<div class=\"list\">" + sessions.prefix(8).map {
            let title = $0.title.isEmpty ? ($0.projectName.isEmpty ? "Untitled session" : $0.projectName) : $0.title
            return "<div><strong>\(html(short(title)))</strong><span>\(html($0.projectName)) · \(compactTokenCount($0.tokens)) tokens</span></div>"
        }.joined() + "</div>"
    }

    private static func compactTokenCount(_ tokens: UInt64) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    private static func pageHeading(_ title: String, _ description: String) -> String {
        "<header class=\"page-head\"><span class=\"page-kicker\">MaxxBar Hub</span><h1>\(html(title))</h1><p>\(html(description))</p></header>"
    }

    private static func momentRows(_ moments: [MaxxMomentRecord]) -> String {
        let recent = moments.sorted { $0.ts > $1.ts }.prefix(8)
        guard !recent.isEmpty else { return "<p class=\"sub\">No Maxx Moments captured in the last seven days.</p>" }
        return "<div class=\"moments\">" + recent.map { moment in
            let context = moment.surface ?? moment.tool ?? moment.site ?? moment.app
            return "<div class=\"moment\"><strong>\(html(moment.sentiment ?? "Moment"))</strong><div><strong>\(html(moment.note))</strong><span>\(html(context))</span></div><span>\(html(hubDate(moment.ts)))</span></div>"
        }.joined() + "</div>"
    }

    private static func limitPanels(_ snapshot: LLMUsageSnapshot) -> String {
        guard !snapshot.limits.isEmpty else { return panel("Live Limits", "<p class=\"sub\">\(html(snapshot.error ?? "Codex usage unavailable"))</p>") }
        let limits = snapshot.limits.map { limit in
            let rows = [limit.primary, limit.secondary].compactMap { $0 }.map(usageWindowRow).joined()
            return panel(limit.name + " Limits", rows)
        }.joined()
        let credits = snapshot.resetCreditCount.map { count in
            let expirations = snapshot.resetCreditExpirations.map { "\($0.count) · \(hubDate($0.expiresAt))" }.joined(separator: " · ")
            return card("Reset credits", "\(count)", expirations.isEmpty ? "expiration detail unavailable" : expirations)
        } ?? ""
        return "<div class=\"grid\">\(card("Plan", html(snapshot.planType ?? "Unknown"), html(snapshot.email ?? "local account")))\(card("Last updated", html(snapshot.lastUpdated.map(hubDate) ?? "—"), "live usage API"))\(credits)</div>\(limits)"
    }

    private static func usageWindowRow(_ window: LLMUsageWindow) -> String {
        let remaining = min(max(window.remainingPercent, 0), 100)
        let reset = window.resetAt.map { "Resets \(hubDate($0))" } ?? "Reset unavailable"
        return "<div class=\"metric-row\"><div><strong>\(html(window.label))</strong><small>\(html(reset))</small></div><div class=\"meter-wrap\"><div class=\"meter\"><span style=\"width:\(remaining)%\"></span></div><small>\(window.usedPercent)% used</small></div><strong class=\"num\">\(remaining)% left</strong></div>"
    }

    private static func quotaChart(_ history: [LLMQuotaHistorySample], fallback snapshot: LLMUsageSnapshot) -> String {
        var samples = Array(history.suffix(200))
        if samples.isEmpty, let limit = snapshot.limits.first(where: { $0.name == "Codex" }) ?? snapshot.limits.first {
            samples = [LLMQuotaHistorySample(sampledAt: snapshot.lastUpdated ?? Date(), primaryRemainingPercent: limit.primary?.remainingPercent, weeklyRemainingPercent: limit.secondary?.remainingPercent, planType: snapshot.planType)]
        }
        guard let first = samples.first, let last = samples.last else { return "<p class=\"sub\">No quota history captured yet.</p>" }
        let span = max(last.sampledAt.timeIntervalSince(first.sampledAt), 1)
        func points(_ keyPath: KeyPath<LLMQuotaHistorySample, Int?>) -> String {
            samples.compactMap { sample -> String? in
                guard let value = sample[keyPath: keyPath] else { return nil }
                let x = 20 + 860 * sample.sampledAt.timeIntervalSince(first.sampledAt) / span
                let y = 10 + 100 * (1 - Double(min(max(value, 0), 100)) / 100)
                return "\(String(format: "%.1f", x)),\(String(format: "%.1f", y))"
            }.joined(separator: " ")
        }
        let primary = points(\.primaryRemainingPercent)
        let weekly = points(\.weeklyRemainingPercent)
        return "<svg class=\"quota-chart\" viewBox=\"0 0 900 130\" role=\"img\" aria-label=\"Codex remaining quota history\"><path class=\"chart-grid\" d=\"M20 10H880 M20 60H880 M20 110H880\"></path><polyline class=\"quota-primary\" points=\"\(primary)\"></polyline><polyline class=\"quota-weekly\" points=\"\(weekly)\"></polyline></svg><div class=\"legend\"><span><i class=\"dot\" style=\"background:var(--accent)\"></i>5h remaining</span><span><i class=\"dot\" style=\"background:#8bb4ff\"></i>Weekly remaining</span><span>\(html(hubDate(first.sampledAt))) → \(html(hubDate(last.sampledAt)))</span></div>"
    }

    private static func sessionTimeline(_ snapshot: LLMUsageSnapshot) -> String {
        let sessions = allSessions(snapshot)
        let end = Date()
        let start = end.addingTimeInterval(-86_400)
        let rows = sessions.compactMap { session -> (LLMUsageSession, Date, Date)? in
            let sessionEnd = session.updatedAt ?? session.createdAt ?? end
            let sessionStart = session.createdAt ?? sessionEnd.addingTimeInterval(-900)
            guard sessionStart <= end && sessionEnd >= start else { return nil }
            return (session, max(sessionStart, start), min(sessionEnd, end))
        }.sorted { $0.2 > $1.2 }.prefix(20)
        guard !rows.isEmpty else { return "<p class=\"sub\">No local sessions in the last 24 hours.</p>" }
        return "<div class=\"timeline\">" + rows.map { session, clippedStart, clippedEnd in
            let left = max(0, clippedStart.timeIntervalSince(start) / 86_400 * 100)
            let width = max(0.35, clippedEnd.timeIntervalSince(clippedStart) / 86_400 * 100)
            let tokens = session.tokenUsage?.totalTokens ?? session.tokens
            return "<div class=\"timeline-row\"><div class=\"timeline-label\"><strong>\(html(short(cleanSessionTitle(session.title))))</strong><small>\(html(session.projectName)) · \(compactTokenCount(tokens))</small></div><div class=\"timeline-track\"><span class=\"timeline-bar\" style=\"left:\(String(format: "%.2f", left))%;width:\(String(format: "%.2f", width))%\"></span></div><span class=\"num\">\(html(hubDate(clippedEnd)))</span></div>"
        }.joined() + "</div>"
    }

    private static func sessionAccordions(_ snapshot: LLMUsageSnapshot) -> String {
        let sessions = allSessions(snapshot)
        guard !sessions.isEmpty else { return "<p class=\"sub\">No local Codex sessions found.</p>" }
        return "<div class=\"session-list\">" + sessions.map { session in
            let usage = session.tokenUsage
            let tokens = usage?.totalTokens ?? session.tokens
            let preview = sanitizedSessionPreview(session.preview)
            let contextLink = session.rolloutPath.isEmpty ? "" : "<div><dt>Context</dt><dd><a href=\"\(html(URL(fileURLWithPath: session.rolloutPath).absoluteString))\">Open local file</a></dd></div>"
            return """
            <details class="session">
              <summary><div><strong>\(html(cleanSessionTitle(session.title)))</strong><small>\(html(session.projectName)) · \(html(session.modelName)) · \(html(session.updatedAt.map(hubDate) ?? "time unavailable"))</small></div><strong class="num">\(compactTokenCount(tokens))</strong></summary>
              <div class="session-body"><dl class="detail-grid">
                <div><dt>Project</dt><dd>\(html(session.projectName))</dd></div><div><dt>Model</dt><dd>\(html(session.modelName))</dd></div><div><dt>Session ID</dt><dd>\(html(session.id))</dd></div>
                <div><dt>Total tokens</dt><dd>\(compactTokenCount(tokens))</dd></div><div><dt>Input</dt><dd>\(compactTokenCount(usage?.inputTokens ?? 0))</dd></div><div><dt>Cached input</dt><dd>\(compactTokenCount(usage?.cachedInputTokens ?? 0))</dd></div>
                <div><dt>Fresh input</dt><dd>\(compactTokenCount(usage?.nonCachedInputTokens ?? 0))</dd></div><div><dt>Output</dt><dd>\(compactTokenCount(usage?.outputTokens ?? 0))</dd></div><div><dt>Reasoning</dt><dd>\(compactTokenCount(usage?.reasoningOutputTokens ?? 0))</dd></div>
                <div><dt>Cache hit</dt><dd>\(usage.map { "\($0.cacheHitPercent)%" } ?? "—")</dd></div><div><dt>Turns</dt><dd>\(usage.map { "\($0.turnCount)" } ?? "—")</dd></div><div><dt>API estimate</dt><dd>\(usage.map { hubDollars($0.estimatedCost(for: session.modelName)) } ?? "—")</dd></div>
                <div><dt>Estimated rate</dt><dd>\(html(usage?.pricingLabel(for: session.modelName) ?? "—"))</dd></div><div><dt>Started</dt><dd>\(html(session.createdAt.map(hubDate) ?? "—"))</dd></div><div><dt>Updated</dt><dd>\(html(session.updatedAt.map(hubDate) ?? "—"))</dd></div>\(contextLink)
              </dl>\(preview.map { "<p class=\"preview\">\(html($0))</p>" } ?? "")</div>
            </details>
            """
        }.joined() + "</div>"
    }

    private static func advancedSummary(_ snapshot: LLMUsageSnapshot) -> String {
        "<div class=\"grid\">\(card("Plan", html(snapshot.planType ?? "Unknown"), html(snapshot.email ?? "account unavailable")))\(card("Limit groups", "\(snapshot.limits.count)", "live API"))\(card("Local windows", "\(snapshot.localWindows.count)", "token summaries"))\(card("Recent sessions", "\(snapshot.recentSessions.count)", "\(snapshot.topWeeklySessions.count) highest"))\(card("Reset credits", snapshot.resetCreditCount.map(String.init) ?? "—", html(snapshot.creditsBalance ?? "balance unavailable")))</div>"
    }

    private static func localWindowTable(_ windows: [LLMLocalUsageWindow]) -> String {
        guard !windows.isEmpty else { return "<p class=\"sub\">No local usage windows available.</p>" }
        return "<table class=\"data-table\"><thead><tr><th>Window</th><th class=\"num\">Tokens</th><th class=\"num\">Threads</th></tr></thead><tbody>" + windows.map { "<tr><td>\(html($0.label))</td><td class=\"num\">\(compactTokenCount($0.tokens))</td><td class=\"num\">\($0.threads)</td></tr>" }.joined() + "</tbody></table>"
    }

    private static func costEstimateTable(_ estimates: [LLMTokenCostEstimate]) -> String {
        guard !estimates.isEmpty else { return "<p class=\"sub\">No local token cost estimates available.</p>" }
        return "<table class=\"data-table\"><thead><tr><th>Window</th><th class=\"num\">Sessions</th><th class=\"num\">Fresh input</th><th class=\"num\">Cached input</th><th class=\"num\">Output</th><th class=\"num\">Cache</th><th class=\"num\">API est.</th></tr></thead><tbody>" + estimates.map { "<tr><td>\(html($0.label))</td><td class=\"num\">\($0.sessionCount)</td><td class=\"num\">\(compactTokenCount($0.freshInputTokens))</td><td class=\"num\">\(compactTokenCount($0.cachedInputTokens))</td><td class=\"num\">\(compactTokenCount($0.outputTokens))</td><td class=\"num\">\($0.cacheHitPercent)%</td><td class=\"num\">\(hubDollars($0.estimatedCost))</td></tr>" }.joined() + "</tbody></table>"
    }

    private static func availableDetail(_ snapshot: LLMUsageSnapshot) -> String {
        let windows = snapshot.localWindows.map(\.label).joined(separator: ", ")
        let rows = [
            ("Live limits", "\(snapshot.limits.count) limit groups"),
            ("Local windows", windows.isEmpty ? "None" : windows),
            ("Session totals", "Title, model, project, tokens, cache, cost, timing, and IDs"),
            ("Prompt detail", "Stored preview only"),
            ("Per-prompt tokens", "Not stored locally"),
            ("Last update", snapshot.lastUpdated.map(hubDate) ?? "Unavailable"),
            ("Error", snapshot.error ?? "None")
        ]
        return "<div class=\"list\">" + rows.map { "<div><strong>\(html($0.0))</strong><span>\(html($0.1))</span></div>" }.joined() + "</div>"
    }

    private static func allSessions(_ snapshot: LLMUsageSnapshot) -> [LLMUsageSession] {
        var seen = Set<String>()
        return (snapshot.recentSessions + snapshot.topWeeklySessions)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
    }

    private static func cleanSessionTitle(_ title: String) -> String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.localizedCaseInsensitiveContains("Codex agent history") || cleaned.localizedCaseInsensitiveContains("approval request") { return "Approval review" }
        return cleaned.isEmpty ? "Untitled session" : cleaned
    }

    private static func sanitizedSessionPreview(_ preview: String) -> String? {
        let cleaned = preview.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "No prompt preview stored" else { return nil }
        let lower = cleaned.lowercased()
        if lower.contains("codex agent history") || lower.contains("approval request") || lower.contains("transcript start") || lower.contains("planned action json") { return nil }
        return cleaned.count <= 500 ? cleaned : String(cleaned.prefix(497)) + "..."
    }

    private static func hubDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func hubDollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func pathVisual(_ paths: [AIWorkflowPath]) -> String {
        guard !paths.isEmpty else { return panel("AI Paths", "<p class=\"sub\">No ChatGPT/Codex/Claude paths found yet.</p>") }

        let total = max(paths.reduce(0) { $0 + $1.count }, 1)
        var beforeCounts: [String: Int] = [:]
        var surfaceCounts: [String: Int] = [:]
        var afterCounts: [String: Int] = [:]
        var leftLinks: [String: (source: String, target: String, count: Int)] = [:]
        var rightLinks: [String: (source: String, target: String, count: Int)] = [:]

        for path in paths {
            beforeCounts[path.before, default: 0] += path.count
            surfaceCounts[path.surface, default: 0] += path.count
            afterCounts[path.after, default: 0] += path.count

            let leftKey = "\(path.before)|\(path.surface)"
            let rightKey = "\(path.surface)|\(path.after)"
            var left = leftLinks[leftKey] ?? (path.before, path.surface, 0)
            left.count += path.count
            leftLinks[leftKey] = left
            var right = rightLinks[rightKey] ?? (path.surface, path.after, 0)
            right.count += path.count
            rightLinks[rightKey] = right
        }

        struct NodePosition {
            let x: Double
            let y: Double
            let height: Double
        }

        struct Stage {
            let title: String
            let counts: [String: Int]
            let x: Double
        }

        func topLabels(_ counts: [String: Int]) -> [String] {
            Array(counts.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }.prefix(6).map(\.key))
        }

        func percent(_ count: Int) -> String {
            "\(Int((Double(count) / Double(total) * 100).rounded()))%"
        }

        func icon(for label: String) -> (String, String) {
            let lower = label.lowercased()
            let color: String
            if lower.contains("gmail") { color = "#ea4335" }
            else if lower.contains("github") { color = "#f5f7fb" }
            else if lower.contains("safari") { color = "#38bdf8" }
            else if lower.contains("codex") || lower.contains("chatgpt") { color = "#34d399" }
            else if lower.contains("maxx") { color = "#38bdf8" }
            else { color = "#a78bfa" }
            let initials = label
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first }
                .map { String($0).uppercased() }
                .joined()
            return (initials.isEmpty ? "AI" : initials, color)
        }

        let stages = [
            Stage(title: "Before", counts: beforeCounts, x: 24),
            Stage(title: "AI surface", counts: surfaceCounts, x: 382),
            Stage(title: "After", counts: afterCounts, x: 740)
        ]

        let nodeWidth = 132.0
        let top = 58.0
        let availableHeight = 252.0
        var positions: [String: NodePosition] = [:]
        var stageMarkup = ""

        for stage in stages {
            let labels = topLabels(stage.counts)
            let rawHeights = labels.map { max(24.0, Double(stage.counts[$0] ?? 0) / Double(total) * 190.0) }
            let gap = 14.0
            let needed = rawHeights.reduce(0, +) + max(0.0, Double(labels.count - 1)) * gap
            let scale = needed > 0 ? min(1.0, availableHeight / needed) : 1.0
            var y = top

            stageMarkup += #"<text class="ai-sankey-stage" x="\#(stage.x)" y="24">\#(html(stage.title))</text>"#
            for (index, label) in labels.enumerated() {
                let count = stage.counts[label] ?? 0
                let height = max(20.0, rawHeights[index] * scale)
                positions["\(stage.title)|\(label)"] = NodePosition(x: stage.x, y: y, height: height)
                let (iconText, iconColor) = icon(for: label)
                let iconX = stage.x + nodeWidth + 8
                let iconY = y + 4
                let labelX = iconX + 26
                stageMarkup += """
                <rect class="ai-sankey-node" x="\(format(stage.x))" y="\(format(y))" width="\(format(nodeWidth))" height="\(format(height))" rx="4"><title>\(html(label)) · \(count)x · \(percent(count))</title></rect>
                <g class="ai-sankey-icon" transform="translate(\(format(iconX)),\(format(iconY)))"><rect width="18" height="18" rx="5" fill="\(iconColor)" opacity=".2"></rect><text x="9" y="12.5" text-anchor="middle" fill="\(iconColor)">\(html(iconText))</text></g>
                <text class="ai-sankey-label" x="\(format(labelX))" y="\(format(y + 12))">\(html(short(label)))</text>
                <text class="ai-sankey-count" x="\(format(labelX))" y="\(format(y + 28))">\(count) (\(percent(count)))</text>
                """
                y += height + gap
            }
        }

        func linkMarkup(_ links: [String: (source: String, target: String, count: Int)], fromStage: String, toStage: String) -> String {
            links.values.sorted { lhs, rhs in
                lhs.count == rhs.count ? "\(lhs.source)|\(lhs.target)" < "\(rhs.source)|\(rhs.target)" : lhs.count > rhs.count
            }.prefix(18).compactMap { link in
                guard let start = positions["\(fromStage)|\(link.source)"],
                      let end = positions["\(toStage)|\(link.target)"] else {
                    return nil
                }
                let sx = start.x + nodeWidth
                let sy = start.y + start.height / 2
                let ex = end.x
                let ey = end.y + end.height / 2
                let width = max(3.0, min(30.0, Double(link.count) / Double(total) * 36.0))
                return #"<path class="ai-sankey-link" d="M \#(format(sx)) \#(format(sy)) C \#(format(sx + 95)) \#(format(sy)), \#(format(ex - 95)) \#(format(ey)), \#(format(ex)) \#(format(ey))" stroke-width="\#(format(width))"><title>\#(html(link.source)) → \#(html(link.target)) · \#(link.count)x · \#(percent(link.count))</title></path>"#
            }.joined()
        }

        let links = linkMarkup(leftLinks, fromStage: "Before", toStage: "AI surface")
            + linkMarkup(rightLinks, fromStage: "AI surface", toStage: "After")

        let topRows = paths.prefix(6).map { path -> String in
            return """
            <div><strong>\(html(path.before))</strong><span>→</span><strong>\(html(path.surface))</strong><span>→</span><strong>\(html(path.after))</strong><em>\(percent(path.count)) · \(path.count)x · \(html(path.useCase))</em></div>
            """
        }.joined()

        return """
        <section class="panel">
          <div class="ai-path-head">
            <div>
              <h2>AI Paths</h2>
              <p>Most common before → AI surface → after workflows.</p>
            </div>
            <strong>\(total) moments</strong>
          </div>
          <div class="ai-sankey-wrap">
            <svg class="ai-sankey" viewBox="0 0 980 340" role="img" aria-label="Before AI after path flow">
              \(links)
              \(stageMarkup)
            </svg>
          </div>
          <div class="ai-path-top">\(topRows)</div>
        </section>
        """
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func short(_ value: String) -> String {
        value.count <= 24 ? value : String(value.prefix(21)) + "..."
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private static func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum LLMUsageReader {
    private struct LocalCodexUsage {
        let fiveHourTokens: UInt64
        let weeklyTokens: UInt64
        let weeklyThreads: Int
        let windows: [LLMLocalUsageWindow]
        let costEstimates: [LLMTokenCostEstimate]
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
        let rate_limit_reset_credits: RateLimitResetCredits?
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

    private struct RateLimitResetCredits: Decodable {
        let available_count: Int?
        let expirations: [LLMResetCreditExpiration]

        init(from decoder: Decoder) throws {
            let value = try FlexibleUsageValue(from: decoder)
            available_count = value.object?["available_count"]?.intValue
            expirations = RateLimitResetCredits.expirations(in: value)
        }

        private static func expirations(in value: FlexibleUsageValue) -> [LLMResetCreditExpiration] {
            var results: [LLMResetCreditExpiration] = []
            collectExpirations(in: value, into: &results)

            return results
                .reduce(into: [Date: Int]()) { grouped, expiration in
                    grouped[expiration.expiresAt, default: 0] += expiration.count
                }
                .map { LLMResetCreditExpiration(count: $0.value, expiresAt: $0.key) }
                .sorted { $0.expiresAt < $1.expiresAt }
        }

        private static func collectExpirations(in value: FlexibleUsageValue, into results: inout [LLMResetCreditExpiration]) {
            if let object = value.object {
                if let expiresAt = expirationDate(in: object) {
                    results.append(LLMResetCreditExpiration(count: creditCount(in: object), expiresAt: expiresAt))
                }

                for child in object.values {
                    collectExpirations(in: child, into: &results)
                }
            }

            if let array = value.array {
                for child in array {
                    collectExpirations(in: child, into: &results)
                }
            }
        }

        private static func expirationDate(in object: [String: FlexibleUsageValue]) -> Date? {
            let expirationKeys = ["expires_at", "expiresAt", "expire_at", "expires", "expiration", "expiration_at", "expirationAt", "expiration_date"]

            for key in expirationKeys {
                guard let value = object[key] else { continue }
                if let date = value.dateValue {
                    return date
                }
            }

            return nil
        }

        private static func creditCount(in object: [String: FlexibleUsageValue]) -> Int {
            let countKeys = ["count", "available_count", "availableCount", "credits", "amount", "quantity", "remaining_count", "remainingCount"]

            for key in countKeys {
                guard let count = object[key]?.intValue else { continue }
                return max(count, 1)
            }

            return 1
        }
    }

    private struct FlexibleUsageValue: Decodable {
        let object: [String: FlexibleUsageValue]?
        let array: [FlexibleUsageValue]?
        let string: String?
        let number: Double?

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: DynamicUsageKey.self) {
                var object: [String: FlexibleUsageValue] = [:]
                for key in container.allKeys {
                    object[key.stringValue] = try? container.decode(FlexibleUsageValue.self, forKey: key)
                }
                self.object = object
                array = nil
                string = nil
                number = nil
                return
            }

            if var container = try? decoder.unkeyedContainer() {
                var array: [FlexibleUsageValue] = []
                while !container.isAtEnd {
                    if let value = try? container.decode(FlexibleUsageValue.self) {
                        array.append(value)
                    } else {
                        _ = try? container.decode(EmptyUsageValue.self)
                    }
                }
                object = nil
                self.array = array
                string = nil
                number = nil
                return
            }

            let container = try decoder.singleValueContainer()
            object = nil
            array = nil
            if let string = try? container.decode(String.self) {
                self.string = string
                number = nil
            } else if let number = try? container.decode(Double.self) {
                string = nil
                self.number = number
            } else {
                string = nil
                number = nil
            }
        }

        var intValue: Int? {
            if let number {
                return Int(number)
            }

            if let string {
                return Int(string)
            }

            return nil
        }

        var dateValue: Date? {
            if let number {
                return Date(timeIntervalSince1970: number)
            }

            guard let string else { return nil }
            if let timestamp = TimeInterval(string) {
                return Date(timeIntervalSince1970: timestamp)
            }

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: string) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }
    }

    private struct DynamicUsageKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    private struct EmptyUsageValue: Decodable {}

    private struct SessionIndexEntry: Decodable {
        let id: String
        let thread_name: String?
    }

    static func read() -> LLMUsageSnapshot {
        let local = readLocalCodexUsage()
        guard let token = readAccessToken() else {
            return LLMUsageSnapshot(
                email: nil,
                planType: nil,
                limits: [],
                creditsBalance: nil,
                resetCreditCount: nil,
                resetCreditExpirations: [],
                lastUpdated: Date(),
                localFiveHourTokens: local.fiveHourTokens,
                localWeeklyTokens: local.weeklyTokens,
                localWeeklyThreads: local.weeklyThreads,
                localWindows: local.windows,
                costEstimates: local.costEstimates,
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
                resetCreditCount: response.rate_limit_reset_credits?.available_count,
                resetCreditExpirations: response.rate_limit_reset_credits?.expirations ?? [],
                lastUpdated: Date(),
                localFiveHourTokens: local.fiveHourTokens,
                localWeeklyTokens: local.weeklyTokens,
                localWeeklyThreads: local.weeklyThreads,
                localWindows: local.windows,
                costEstimates: local.costEstimates,
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
            return LocalCodexUsage(fiveHourTokens: 0, weeklyTokens: 0, weeklyThreads: 0, windows: [], costEstimates: [], recentSessions: [], topWeeklySessions: [])
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
            costEstimates: costEstimates(databasePath: databasePath),
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

    private static func costEstimates(databasePath: String) -> [LLMTokenCostEstimate] {
        let endedAt = Date()
        return [
            costEstimate(databasePath: databasePath, label: "5h", seconds: 18_000, endedAt: endedAt),
            costEstimate(databasePath: databasePath, label: "Weekly", seconds: 604_800, endedAt: endedAt)
        ].compactMap { $0 }
    }

    private static func costEstimate(databasePath: String, label: String, seconds: Int, endedAt: Date) -> LLMTokenCostEstimate? {
        let query = """
        select rollout_path
        from threads
        where tokens_used > 0
          and coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-\(seconds))*1000
          and rollout_path is not null
          and rollout_path != '';
        """

        var sessionCount = 0
        var inputTokens: UInt64 = 0
        var cachedInputTokens: UInt64 = 0
        var outputTokens: UInt64 = 0
        var totalTokens: UInt64 = 0

        for row in sqliteRows(databasePath: databasePath, query: query) {
            guard let rolloutPath = row.first,
                  let usage = tokenUsageSummary(from: rolloutPath) else {
                continue
            }
            sessionCount += 1
            inputTokens += usage.inputTokens
            cachedInputTokens += usage.cachedInputTokens
            outputTokens += usage.outputTokens
            totalTokens += max(usage.totalTokens, usage.inputTokens + usage.outputTokens)
        }

        guard sessionCount > 0 else { return nil }

        return LLMTokenCostEstimate(
            label: label,
            sessionCount: sessionCount,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            windowStartedAt: endedAt.addingTimeInterval(-TimeInterval(seconds)),
            windowEndedAt: endedAt
        )
    }

    private enum SessionQueryMode {
        case recent
        case highestWeekly
    }

    private static func sessions(databasePath: String, mode: SessionQueryMode) -> [LLMUsageSession] {
        let indexTitles = sessionIndexTitles()
        let whereClause = mode == .highestWeekly
            ? "where tokens_used > 0 and coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-7*24*3600)*1000"
            : "where coalesce(updated_at_ms, updated_at * 1000) > 0"
        let orderClause = mode == .highestWeekly
            ? "order by tokens_used desc, coalesce(updated_at_ms, updated_at * 1000) desc"
            : "order by coalesce(updated_at_ms, updated_at * 1000) desc"
        let query = """
        select
            id,
            replace(replace(coalesce(nullif(title,''),'Untitled'), char(10), ' '), char(9), ' '),
            coalesce(tokens_used,0),
            coalesce(created_at_ms, created_at * 1000),
            coalesce(updated_at_ms, updated_at * 1000),
            replace(replace(coalesce(nullif(model,''), nullif(model_provider,''), ''), char(10), ' '), char(9), ' '),
            replace(replace(coalesce(nullif(cwd,''), ''), char(10), ' '), char(9), ' '),
            replace(replace(coalesce(nullif(preview,''), nullif(first_user_message,''), ''), char(10), ' '), char(9), ' '),
            rollout_path
        from threads
        \(whereClause)
        \(orderClause)
        limit 30;
        """

        return sqliteRows(databasePath: databasePath, query: query).compactMap { row in
            guard row.count >= 9 else { return nil }
            let title = sessionTitle(id: row[0], sqliteTitle: row[1], indexTitles: indexTitles)
            let tokens = UInt64(row[2]) ?? 0
            let createdAt = TimeInterval(row[3]).map { Date(timeIntervalSince1970: $0 / 1000) }
            let updatedAt = TimeInterval(row[4]).map { Date(timeIntervalSince1970: $0 / 1000) }
            let model = compactText(row[5], fallback: "Model unavailable")
            let project = projectName(from: row[6])
            let preview = compactText(row[7], fallback: "No prompt preview stored")
            let rolloutPath = compactText(row[8], fallback: "")
            return LLMUsageSession(
                id: row[0],
                title: title,
                projectName: project,
                modelName: model,
                preview: preview,
                rolloutPath: rolloutPath,
                tokens: tokens,
                tokenUsage: tokenUsageSummary(from: rolloutPath),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private static func sessionTitle(id: String, sqliteTitle: String, indexTitles: [String: String]) -> String {
        if let indexTitle = indexTitles[id],
           !indexTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return indexTitle
        }
        return compactText(sqliteTitle, fallback: "Untitled")
    }

    private static func sessionIndexTitles() -> [String: String] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/session_index.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let decoder = JSONDecoder()
        var titles: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(SessionIndexEntry.self, from: data),
                  let title = entry.thread_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                continue
            }
            titles[entry.id] = title
        }
        return titles
    }

    private static func tokenUsageSummary(from rolloutPath: String) -> LLMTokenUsageSummary? {
        let path = rolloutPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        var latestInputTokens: UInt64 = 0
        var latestCachedInputTokens: UInt64 = 0
        var latestOutputTokens: UInt64 = 0
        var latestReasoningOutputTokens: UInt64 = 0
        var latestTotalTokens: UInt64 = 0
        var turnCount = 0
        var foundUsage = false

        for line in tokenUsageLines(from: path) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any] else {
                continue
            }

            if info["last_token_usage"] is [String: Any] {
                turnCount += 1
            }

            let totalUsage = (info["total_token_usage"] as? [String: Any]) ?? info
            latestInputTokens = tokenValue(totalUsage, "input_tokens")
            latestCachedInputTokens = tokenValue(totalUsage, "cached_input_tokens")
            latestOutputTokens = tokenValue(totalUsage, "output_tokens")
            latestReasoningOutputTokens = tokenValue(totalUsage, "reasoning_output_tokens")
            latestTotalTokens = tokenValue(totalUsage, "total_tokens")
            foundUsage = true
        }

        guard foundUsage else { return nil }

        if latestTotalTokens == 0 {
            latestTotalTokens = latestInputTokens + latestOutputTokens + latestReasoningOutputTokens
        }

        return LLMTokenUsageSummary(
            inputTokens: latestInputTokens,
            cachedInputTokens: latestCachedInputTokens,
            outputTokens: latestOutputTokens,
            reasoningOutputTokens: latestReasoningOutputTokens,
            totalTokens: latestTotalTokens,
            turnCount: turnCount
        )
    }

    private static func tokenUsageLines(from path: String) -> [Substring] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer {
            try? handle.close()
        }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 512 * 1024
        let offset = fileSize > maxBytes ? fileSize - maxBytes : 0
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return Array(text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("\"token_count\"") }
            .suffix(60))
    }

    private static func tokenValue(_ dictionary: [String: Any], _ key: String) -> UInt64 {
        if let value = dictionary[key] as? UInt64 {
            return value
        }
        if let value = dictionary[key] as? Int {
            return UInt64(max(value, 0))
        }
        if let value = dictionary[key] as? Double {
            return UInt64(max(value, 0))
        }
        if let value = dictionary[key] as? String {
            return UInt64(value) ?? 0
        }
        return 0
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
            resetCreditCount: nil,
            resetCreditExpirations: [],
            lastUpdated: Date(),
            localFiveHourTokens: local.fiveHourTokens,
            localWeeklyTokens: local.weeklyTokens,
            localWeeklyThreads: local.weeklyThreads,
            localWindows: local.windows,
            costEstimates: local.costEstimates,
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
