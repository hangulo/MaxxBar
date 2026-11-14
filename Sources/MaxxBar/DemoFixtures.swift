import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

extension Array where Element == LLMQuotaHistorySample {
    static let demo: [LLMQuotaHistorySample] = [
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-6_000 * 80), primaryRemainingPercent: 99, weeklyRemainingPercent: 84, planType: "plus", claudeWeeklyRemainingPercent: 90),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-5_340 * 80), primaryRemainingPercent: 92, weeklyRemainingPercent: 83, planType: "plus", claudeWeeklyRemainingPercent: 86),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-4_680 * 80), primaryRemainingPercent: 56, weeklyRemainingPercent: 77, planType: "plus", claudeWeeklyRemainingPercent: 81),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-4_080 * 80), primaryRemainingPercent: 34, weeklyRemainingPercent: 74, planType: "plus", claudeWeeklyRemainingPercent: 74),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-3_420 * 80), primaryRemainingPercent: 11, weeklyRemainingPercent: 70, planType: "plus", claudeWeeklyRemainingPercent: 66),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-2_760 * 80), primaryRemainingPercent: 0, weeklyRemainingPercent: 68, planType: "plus", claudeWeeklyRemainingPercent: 59),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-2_100 * 80), primaryRemainingPercent: 0, weeklyRemainingPercent: 68, planType: "plus", claudeWeeklyRemainingPercent: 52),
        LLMQuotaHistorySample(sampledAt: Date().addingTimeInterval(-1_440 * 80), primaryRemainingPercent: 99, weeklyRemainingPercent: 100, planType: "prolite", claudeWeeklyRemainingPercent: 52)
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
            ),
            LLMUsageLimit(
                name: "Claude",
                primary: LLMUsageWindow(label: "5h", usedPercent: 34, remainingPercent: 66, resetAt: Date().addingTimeInterval(7_200), windowSeconds: 18_000),
                secondary: LLMUsageWindow(label: "Weekly", usedPercent: 48, remainingPercent: 52, resetAt: Date().addingTimeInterval(345_600), windowSeconds: 604_800),
                cachedAt: Date().addingTimeInterval(-300)
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
                provider: "Codex",
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
                provider: "Codex",
                title: "Sensor helper",
                projectName: "MaxxBar",
                modelName: "GPT-5.3 Codex",
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
                provider: "Codex",
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
                provider: "Claude",
                title: "CPU/GPU panel",
                projectName: "MaxxBar",
                modelName: "Claude Sonnet 4.5",
                preview: "Compared CPU and GPU data with system monitoring panels.",
                rolloutPath: "",
                tokens: 58_700_000,
                tokenUsage: LLMTokenUsageSummary(inputTokens: 47_000_000, cachedInputTokens: 30_000_000, outputTokens: 7_400_000, reasoningOutputTokens: 4_300_000, totalTokens: 58_700_000, turnCount: 19),
                createdAt: Date().addingTimeInterval(-90_000),
                updatedAt: Date().addingTimeInterval(-86_400)
            )
        ],
        error: nil,
        providerAccounts: [
            LLMProviderAccount(
                provider: "Codex",
                email: "you@example.com",
                displayName: nil,
                organizationName: nil,
                planName: "prolite"
            ),
            LLMProviderAccount(
                provider: "Claude",
                email: "you@client.example",
                displayName: "Hector",
                organizationName: "Client workspace",
                planName: "Team"
            )
        ]
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
        fanPercent: 100,
        fanRPM: 1450,
        fanReadings: [FanReading(label: "Fan 1", rpm: 1355), FanReading(label: "Fan 2", rpm: 1450)],
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
