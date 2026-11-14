import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

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
    @Published private(set) var llmUsage = LLMUsageSnapshot.empty
    @Published private(set) var llmQuotaHistory: [LLMQuotaHistorySample] = []
    @Published private(set) var aiUsage = AIUsageSnapshot.empty
    private var previousCumulativePageIns: UInt64?
    private var previousCumulativePageOuts: UInt64?
    private var previousCPUInfo: CPUReader.CPULoadInfo?
    private var previousLLMUsageRefresh: Date?
    private var previousLLMQuotaSample: Date?
    private var previousLLMQuotaActivitySignature: LLMQuotaActivitySignature?
    private var isRefreshing = false
    private var isRefreshingStatus = false
    /// The activity log samples the frontmost app (and asks Chrome/Arc for the tab); once a minute is enough.
    private var lastActivityRecordAt: Date?
    private static let activityRecordInterval: TimeInterval = 60
    private var isRefreshingLLMUsage = false
    private var claudeCheckID: UUID?
    private let claudeCheckQueue = DispatchQueue(label: "com.hector.MaxxBar.claude-check", qos: .userInitiated)
    @Published private(set) var isCheckingClaude = false
    /// A short result shown after "Check now" when no request was made (e.g. "Checked 12s ago").
    @Published private(set) var claudeCheckNote: String?
    private var isGeneratingAIReport = false
    private let clipboardProcessingQueue = DispatchQueue(
        label: "com.hector.MaxxBar.clipboard-processing",
        qos: .utility
    )
    private static let llmQuotaHistoryLimit = 4_320

    init() {
        llmQuotaHistory = Self.loadLLMQuotaHistory()
        previousLLMQuotaSample = llmQuotaHistory.last?.sampledAt
    }

    init(
        snapshot: MemorySnapshot,
        history: [MemoryBreakdown],
        llmUsage: LLMUsageSnapshot = .demo,
        aiUsage: AIUsageSnapshot = .demo,
        llmQuotaHistory: [LLMQuotaHistorySample] = .demo
    ) {
        self.snapshot = snapshot
        self.history = history
        self.llmUsage = llmUsage
        self.aiUsage = aiUsage
        self.llmQuotaHistory = llmQuotaHistory
    }

    func applyDemoSnapshots() {
        sensors = .demo
        cpuGPU = CPUReader.read(previous: nil, sensors: .demo).snapshot
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
        let currentLLMUsage = llmUsage

        DispatchQueue.global(qos: .utility).async {
            let result = Self.collectRefresh(
                previousPageIns: previousPageIns,
                previousPageOuts: previousPageOuts,
                previousCPUInfo: previousCPUInfo,
                llmUsage: currentLLMUsage
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
        let currentCPUGPU = cpuGPU
        let currentLLMUsage = llmUsage
        let now = Date()
        let shouldRecordActivity = lastActivityRecordAt.map { now.timeIntervalSince($0) >= Self.activityRecordInterval } ?? true
        if shouldRecordActivity { lastActivityRecordAt = now }

        DispatchQueue.global(qos: .utility).async {
            let stats = MemoryReader.read(includeProcesses: false, precisePressure: false)
            var displayStats = stats
            displayStats.pageIns = Self.deltaValue(from: previousPageIns, to: stats.cumulativePageIns)
            displayStats.pageOuts = Self.deltaValue(from: previousPageOuts, to: stats.cumulativePageOuts)
            let aiUsage: AIUsageSnapshot? = shouldRecordActivity
                ? AIUsageReader.recordAndRead(
                    memory: displayStats,
                    cpuGPU: currentCPUGPU,
                    llmUsage: currentLLMUsage
                )
                : nil

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.previousCumulativePageIns = stats.cumulativePageIns
                self.previousCumulativePageOuts = stats.cumulativePageOuts
                self.snapshot = displayStats
                if let aiUsage {
                    self.aiUsage = aiUsage
                }
                self.history.append(stats.breakdown)
                if self.history.count > 60 {
                    self.history.removeFirst(self.history.count - 60)
                }
                self.isRefreshingStatus = false
                completion?()
            }
        }
    }

    /// "Check now" on the Claude card: an immediate usage read (the reader still honors 429 cooldowns).
    /// Reads only the Claude usage endpoint, independent of the full (slow) usage refresh, and always ends the
    /// "Checking…" state: with fresh numbers, a reason no request was made, or after a 20-second limit.
    func checkClaudeUsageNow() {
        guard !isCheckingClaude else { return }
        let id = UUID()
        claudeCheckID = id
        isCheckingClaude = true
        claudeCheckNote = nil
        let started = Date()
        let base = llmUsage
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.claudeCheckID == id else { return }
            self.finishClaudeCheck(note: "Still waiting for Claude; the card will update when it answers.")
        }
        claudeCheckQueue.async {
            let result = LLMUsageReader.checkClaudeNow(in: base)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.claudeCheckID == id else { return }
                // Merge only the Claude parts: a full refresh may have landed in the meantime.
                var merged = self.llmUsage
                merged.limits.removeAll { $0.name == "Claude" }
                merged.limits.append(contentsOf: result.snapshot.limits.filter { $0.name == "Claude" })
                merged.providerErrors["Claude"] = result.snapshot.providerErrors["Claude"]
                merged.error = merged.providerErrors.isEmpty
                    ? nil
                    : merged.providerErrors.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " ")
                self.llmUsage = merged
                // Keep "Checking…" visible briefly so an instant answer still reads as a response.
                let remaining = max(0, 0.6 - Date().timeIntervalSince(started))
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    guard let self, self.claudeCheckID == id else { return }
                    self.finishClaudeCheck(note: result.skipped)
                }
            }
        }
    }

    private func finishClaudeCheck(note: String?) {
        claudeCheckID = nil
        isCheckingClaude = false
        claudeCheckNote = note
        guard note != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.claudeCheckID == nil, self.claudeCheckNote == note else { return }
            self.claudeCheckNote = nil
        }
    }

    func refreshLLMUsageInBackground(
        force: Bool = false, checkClaudeNow: Bool = false, refreshLocal: Bool = true,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard !isRefreshingLLMUsage else { return }
        // 30s keeps the reader's 2-minute Claude schedule on time with the 15s app timer.
        if !force,
           let previousLLMUsageRefresh,
           Date().timeIntervalSince(previousLLMUsageRefresh) < 30 {
            completion?()
            return
        }

        isRefreshingLLMUsage = true
        DispatchQueue.global(qos: .utility).async {
            let usage = LLMUsageReader.read(checkClaudeNow: checkClaudeNow, refreshLocal: refreshLocal)
            Self.logFiveHourUsageWindow(from: usage)
            let refreshedAt = Date()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.llmUsage = usage
                self.previousLLMUsageRefresh = refreshedAt
                self.sampleLLMQuotaIfNeeded()
                self.isRefreshingLLMUsage = false
                completion?()
            }
        }
    }

    func openAIUsageReport() {
        guard let url = AIUsageReader.prepareReportForOpening() else { return }
        NSWorkspace.shared.open(url)
        guard !isGeneratingAIReport else { return }
        isGeneratingAIReport = true
        Task.detached(priority: .utility) {
            let refreshedURL = AIUsageReader.writeReport()
            _ = await MainActor.run {
                self.isGeneratingAIReport = false
                if let refreshedURL {
                    NSWorkspace.shared.open(refreshedURL)
                }
            }
        }
    }

    func recordClipboardEvent(_ eventType: String) {
        guard eventType == "paste" || eventType == "copy" else { return }
        clipboardProcessingQueue.async { [weak self] in
            // Copies and pastes both come from the ⌘C/⌘V listener; they feed the ai-transfers.jsonl flow records.
            let aiUsage = AIUsageReader.recordClipboardEvent(eventType)
            DispatchQueue.main.async { [weak self] in
                self?.aiUsage = aiUsage
            }
        }
    }

    func startDeepTrace() {
        TraceworkLauncher.openHub()
    }

    private struct RefreshResult {
        let stats: MemorySnapshot
        let displayStats: MemorySnapshot
        let sensors: SensorSnapshot
        let cpuResult: (snapshot: CPUGPUSnapshot, current: CPUReader.CPULoadInfo?)
        let aiUsage: AIUsageSnapshot
    }

    nonisolated private static func collectRefresh(
        previousPageIns: UInt64?,
        previousPageOuts: UInt64?,
        previousCPUInfo: CPUReader.CPULoadInfo?,
        llmUsage: LLMUsageSnapshot
    ) -> RefreshResult {
        let stats = MemoryReader.read()
        var displayStats = stats
        displayStats.pageIns = deltaValue(from: previousPageIns, to: stats.cumulativePageIns)
        displayStats.pageOuts = deltaValue(from: previousPageOuts, to: stats.cumulativePageOuts)
        let sensors = SensorReader.read()
        let cpuResult = CPUReader.read(previous: previousCPUInfo, sensors: sensors)
        let aiUsage = AIUsageReader.recordAndRead(
            memory: displayStats,
            cpuGPU: cpuResult.snapshot,
            llmUsage: llmUsage
        )

        return RefreshResult(
            stats: stats,
            displayStats: displayStats,
            sensors: sensors,
            cpuResult: cpuResult,
            aiUsage: aiUsage
        )
    }

    private func apply(_ result: RefreshResult) {
        previousCumulativePageIns = result.stats.cumulativePageIns
        previousCumulativePageOuts = result.stats.cumulativePageOuts
        snapshot = result.displayStats
        sensors = result.sensors
        previousCPUInfo = result.cpuResult.current
        cpuGPU = result.cpuResult.snapshot
        aiUsage = result.aiUsage
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
        let codex = llmUsage.limits.first { $0.name == "Codex" }
        let claude = llmUsage.limits.first { $0.name == "Claude" }
        guard codex != nil || claude != nil else { return }
        let now = Date()
        let activitySignature = LLMQuotaActivitySignature(usage: llmUsage)
        if !force,
           let previousLLMQuotaSample,
           now.timeIntervalSince(previousLLMQuotaSample) < llmQuotaSampleInterval(for: activitySignature) {
            return
        }

        llmQuotaHistory.append(
            LLMQuotaHistorySample(
                sampledAt: now,
                primaryRemainingPercent: codex?.shortWindow?.remainingPercent,
                weeklyRemainingPercent: codex?.weeklyWindow?.remainingPercent,
                planType: codex == nil ? nil : llmUsage.planType,
                claudeWeeklyRemainingPercent: claude?.weeklyWindow?.remainingPercent,
                claudeFiveHourRemainingPercent: claude?.shortWindow?.remainingPercent,
                claudePlanType: claude == nil ? nil : llmUsage.claudePlanType,
                claudeSource: claude?.source,
                codexFiveHourResetAt: codex?.shortWindow?.resetAt,
                codexWeeklyResetAt: codex?.weeklyWindow?.resetAt,
                claudeFiveHourResetAt: claude?.shortWindow?.resetAt,
                claudeWeeklyResetAt: claude?.weeklyWindow?.resetAt
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

    nonisolated static var fiveHourUsageLogURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("MaxxBar", isDirectory: true)
            .appendingPathComponent("llm-5h-usage-windows.jsonl")
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
}
