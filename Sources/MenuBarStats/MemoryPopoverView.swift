import AppKit
import SwiftUI

struct MemoryPopoverView: View {
    @ObservedObject var model: MemoryModel
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    var fixedSize: Bool
    @State private var selectedPanel = StatsPanel.memory

    init(
        model: MemoryModel,
        onPopOut: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        selectedPanel: StatsPanel = .memory,
        fixedSize: Bool = true
    ) {
        self.model = model
        self.onPopOut = onPopOut
        self.onQuit = onQuit
        self.fixedSize = fixedSize
        _selectedPanel = State(initialValue: selectedPanel)
    }

    var body: some View {
        VStack(spacing: 5) {
            PanelSwitch(selectedPanel: $selectedPanel)

            switch selectedPanel {
            case .memory:
                MemoryPanelView(model: model, onPopOut: onPopOut, onQuit: onQuit)
            case .sensors:
                SensorsPanelView(snapshot: model.sensors, onPopOut: onPopOut, onQuit: onQuit)
            case .cpuGPU:
                CPUGPUPanelView(snapshot: model.cpuGPU, onPopOut: onPopOut, onQuit: onQuit)
            case .network:
                NetworkPanelView(snapshot: model.network, onPopOut: onPopOut, onQuit: onQuit)
            case .llmUsage:
                LLMUsagePanelView(snapshot: model.llmUsage, quotaHistory: model.llmQuotaHistory, onPopOut: onPopOut, onQuit: onQuit)
            }
        }
        .padding(8)
        .frame(
            minWidth: fixedSize ? 306 : 306,
            idealWidth: 306,
            maxWidth: fixedSize ? 306 : .infinity,
            minHeight: fixedSize ? 662 : 662,
            idealHeight: 662,
            maxHeight: fixedSize ? 662 : .infinity,
            alignment: .top
        )
        .background(Color.background)
        .foregroundStyle(.white)
    }
}

enum StatsPanel: String, CaseIterable, Identifiable {
    case memory = "Memory"
    case sensors = "Sensors"
    case cpuGPU = "CPU/GPU"
    case network = "Network"
    case llmUsage = "LLM"

    var id: String { rawValue }
}

struct PanelSwitch: View {
    @Binding var selectedPanel: StatsPanel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsPanel.allCases) { panel in
                Button {
                    selectedPanel = panel
                } label: {
                    Text(panel.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(selectedPanel == panel ? .white : .white.opacity(0.68))
                        .background(selectedPanel == panel ? Color.panelLift : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MemoryPanelView: View {
    @ObservedObject var model: MemoryModel
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 18) {
                RingView(
                    title: "PRESSURE",
                    percent: model.snapshot.pressurePercent,
                    segments: [.init(value: Double(model.snapshot.pressurePercent), color: .accentBlue)]
                )

                RingView(
                    title: "MEMORY",
                    percent: model.snapshot.usedPercent,
                    segments: memorySegments
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            BreakdownView(snapshot: model.snapshot)

            ProcessesView(groupedProcesses: model.snapshot.processes, processRows: model.snapshot.processRows)

            PagingView(snapshot: model.snapshot)

            SwapView(snapshot: model.snapshot)

            HistoryView(history: model.history)

            ActionBarView(onPopOut: onPopOut, onQuit: onQuit)
        }
    }

    private var memorySegments: [RingSegment] {
        let breakdown = model.snapshot.breakdown
        let total = max(Double(breakdown.total), 1)
        return [
            RingSegment(value: Double(breakdown.app) / total * 100, color: .accentBlue),
            RingSegment(value: Double(breakdown.wired) / total * 100, color: .wiredPink),
            RingSegment(value: Double(breakdown.compressed) / total * 100, color: .compressedYellow),
            RingSegment(value: Double(breakdown.free) / total * 100, color: .freeGray)
        ]
    }
}

struct SensorsPanelView: View {
    let snapshot: SensorSnapshot
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 16) {
                ValueRingView(title: "CPU", value: temperature(snapshot.cpuTemperature), percent: temperaturePercent(snapshot.cpuTemperature))
                ValueRingView(title: "GPU", value: temperature(snapshot.gpuTemperature), percent: temperaturePercent(snapshot.gpuTemperature))
                ValueRingView(title: "FANS", value: fanStatus(snapshot), percent: fanPercent(snapshot))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            MetricCard(title: "TEMPERATURE", rows: temperatureRows)

            ActionBarView(onPopOut: onPopOut, onQuit: onQuit)
        }
    }

    private var temperatureRows: [MetricRow] {
        let readings = snapshot.temperatureReadings
        guard !readings.isEmpty else {
            return [MetricRow(label: "CPU / GPU / Fans", value: "Requires helper")]
        }

        return readings.map { MetricRow(label: $0.label, value: temperature($0.celsius)) }
    }
}

struct CPUGPUPanelView: View {
    let snapshot: CPUGPUSnapshot
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var processScale = CPUProcessScale.istatShare

    var body: some View {
        VStack(spacing: 7) {
            CPUHistoryCard(snapshot: snapshot)
            CoreRingsView(snapshot: snapshot)
            CPUProcessesView(processes: snapshot.processes, scale: $processScale)
            GPUCard(snapshot: snapshot)
            MetricCard(title: "LOAD", rows: [MetricRow(label: "", value: snapshot.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: " "))])
            MetricCard(title: "UPTIME", rows: [MetricRow(label: "", value: snapshot.uptime)])
            ActionBarView(onPopOut: onPopOut, onQuit: onQuit)
        }
    }
}

struct NetworkPanelView: View {
    let snapshot: NetworkSnapshot
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            CompactMetricCard(title: "LOCATION", value: snapshot.location)
            NetworkGraphCard(snapshot: snapshot)
            NetworkInterfaceCard(snapshot: snapshot)
            CompactMetricCard(title: "PUBLIC IP ADDRESSES", value: snapshot.publicIP ?? "-")
            CompactMetricCard(title: "IP ADDRESSES", value: snapshot.ipAddresses.first ?? "-")
            CompactMetricCard(title: snapshot.ethernetConnected ? "CONNECTED" : "NOT CONNECTED", value: "Ethernet")
            MetricCard(
                title: "PING",
                rows: [MetricRow(label: snapshot.pingTarget, value: snapshot.pingMilliseconds.map { "\($0)ms" } ?? "-")]
            )
            NetworkTotalsView(snapshot: snapshot)
            ActionBarView(onPopOut: onPopOut, onQuit: onQuit)
        }
    }
}

struct LLMUsagePanelView: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var limitsExpanded = false
    @State private var advancedExpanded = true

    var body: some View {
        VStack(spacing: 7) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    if let codexLimit {
                        LLMUsageLimitCard(
                            limit: codexLimit,
                            title: "CODEX USAGE (\(planName(snapshot.planType)))"
                        )
                    } else {
                        LLMUsageUnavailableCard(message: snapshot.error ?? "Codex usage unavailable")
                    }

                    if !additionalLimits.isEmpty {
                        LLMUsageLimitsDisclosureCard(limits: additionalLimits, isExpanded: $limitsExpanded)
                    }

                    LLMLocalUsageCard(snapshot: snapshot, quotaHistory: quotaHistory)
                    LLMAdvancedUsageCard(snapshot: snapshot, isExpanded: $advancedExpanded)
                }
            }

            ActionBarView(onPopOut: onPopOut, onQuit: onQuit)
        }
    }

    private var codexLimit: LLMUsageLimit? {
        snapshot.limits.first(where: { $0.name == "Codex" }) ?? snapshot.limits.first
    }

    private var additionalLimits: [LLMUsageLimit] {
        guard let codexLimit else { return snapshot.limits }
        return snapshot.limits.filter { $0.id != codexLimit.id }
    }
}

struct LLMUsageLimitsDisclosureCard: View {
    let limits: [LLMUsageLimit]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 7) {
                if limits.isEmpty {
                    Text("No live limit detail available")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(limits) { limit in
                        LLMUsageLimitCard(limit: limit)
                    }
                }
            }
            .padding(.top, 5)
        } label: {
            HStack {
                Text("CHATGPT LIMITS")
                    .sectionTitle()
                Spacer()
                Text("\(limits.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .monospacedDigit()
            }
        }
        .accentColor(.accentBlue)
        .sectionStyle()
    }
}

struct LLMUsageSummaryCard: View {
    let snapshot: LLMUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                Text("USAGE REMAINING")
                    .sectionTitle()
                Spacer()
                Text(planName(snapshot.planType))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            if let limit = snapshot.limits.first {
                LLMUsageWindowRow(window: limit.primary)
                LLMUsageWindowRow(window: limit.secondary)
            } else {
                Text(snapshot.error ?? "Codex usage unavailable")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .sectionStyle()
    }
}

struct LLMUsageLimitCard: View {
    let limit: LLMUsageLimit
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title ?? limit.name.uppercased())
                .sectionTitle()
            LLMUsageProgress(window: limit.primary)
            LLMUsageProgress(window: limit.secondary)
        }
        .sectionStyle()
    }
}

struct LLMUsageUnavailableCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("CODEX USAGE")
                .sectionTitle()
            Text(message)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
        }
        .sectionStyle()
    }
}

struct LLMLocalUsageCard: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    @State private var localWindowsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("LOCAL DRAWDOWN")
                .sectionTitle()

            LLMQuotaHistoryGraph(samples: quotaHistory)

            if !snapshot.localWindows.isEmpty {
                DisclosureGroup(isExpanded: $localWindowsExpanded) {
                    VStack(spacing: 7) {
                        ForEach(snapshot.localWindows) { window in
                            LLMLocalUsageWindowRow(window: window, maxTokens: maxTokens)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text("LOCAL TOKENS")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Spacer()
                        Text("\(tokenCount(snapshot.localWeeklyTokens)) • \(snapshot.localWeeklyThreads) sessions")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .monospacedDigit()
                    }
                }
                .accentColor(.accentBlue)
            }
        }
        .sectionStyle()
    }

    private var maxTokens: UInt64 {
        max(snapshot.localWindows.map(\.tokens).max() ?? 0, 1)
    }
}

struct LLMQuotaHistoryGraph: View {
    let samples: [LLMQuotaHistorySample]

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let chartRect = CGRect(
                    x: 27,
                    y: 6,
                    width: max(proxy.size.width - 67, 1),
                    height: max(proxy.size.height - 14, 1)
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.background.opacity(0.46))

                    ForEach([0, 50, 100], id: \.self) { marker in
                        let y = yPosition(for: marker, in: chartRect)
                        Path { path in
                            path.move(to: CGPoint(x: chartRect.minX, y: y))
                            path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                        }
                        .stroke(marker == 50 ? Color.freeGray.opacity(0.34) : Color.freeGray.opacity(0.18), lineWidth: marker == 50 ? 1.2 : 1)

                        Text("\(marker)")
                            .font(.system(size: 9, weight: marker == 50 ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(marker == 50 ? 0.58 : 0.4))
                            .monospacedDigit()
                            .position(x: 12, y: y)
                    }

                    linePath(for: \.primaryRemainingPercent, in: chartRect)
                        .stroke(Color.accentBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    linePath(for: \.weeklyRemainingPercent, in: chartRect)
                        .stroke(Color.compressedYellow, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    latestBadge(for: \.primaryRemainingPercent, color: .accentBlue, in: chartRect)
                    latestBadge(for: \.weeklyRemainingPercent, color: .compressedYellow, in: chartRect)
                }
            }
            .frame(height: 88)

            HStack(spacing: 10) {
                LegendInline(color: .accentBlue, label: "5H used", value: latestValue(\.primaryRemainingPercent))
                LegendInline(color: .compressedYellow, label: "Week used", value: latestValue(\.weeklyRemainingPercent))
            }
        }
    }

    private func latestValue(_ keyPath: KeyPath<LLMQuotaHistorySample, Int?>) -> String {
        guard let remaining = samples.last?[keyPath: keyPath] else { return "-" }
        let value = 100 - remaining
        return "\(value)%"
    }

    private func latestBadge(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, color: Color, in rect: CGRect) -> some View {
        Group {
            if let remaining = samples.last?[keyPath: keyPath] {
                let value = 100 - remaining
                Text("\(value)%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .position(x: rect.maxX + 19, y: yPosition(for: value, in: rect))
            }
        }
    }

    private func linePath(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, in rect: CGRect) -> Path {
        let values = samples.compactMap { sample -> (Date, Int)? in
            guard let remaining = sample[keyPath: keyPath] else { return nil }
            let value = 100 - remaining
            return (sample.sampledAt, value)
        }
        guard !values.isEmpty else { return Path() }

        let start = values.first?.0 ?? Date()
        let end = values.last?.0 ?? start
        let duration = max(end.timeIntervalSince(start), 1)

        return Path { path in
            if values.count == 1, let value = values.first?.1 {
                let y = yPosition(for: value, in: rect)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                return
            }

            for (index, value) in values.enumerated() {
                let x = rect.minX + CGFloat(value.0.timeIntervalSince(start) / duration) * rect.width
                let y = yPosition(for: value.1, in: rect)
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func yPosition(for percent: Int, in rect: CGRect) -> CGFloat {
        rect.minY + rect.height * CGFloat(1 - Double(min(max(percent, 0), 100)) / 100)
    }
}

struct LLMLocalUsageWindowRow: View {
    let window: LLMLocalUsageWindow
    let maxTokens: UInt64

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(window.label)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(tokenCount(window.tokens)) • \(window.threads) sessions")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.freeGray.opacity(0.24))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.accentBlue.opacity(0.88))
                        .frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 5)
        }
    }

    private var ratio: CGFloat {
        CGFloat(Double(window.tokens) / Double(maxTokens))
    }
}

struct LLMAdvancedUsageCard: View {
    let snapshot: LLMUsageSnapshot
    @Binding var isExpanded: Bool
    @State private var sessionMode = LLMTokenUserMode.recent

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                LLMAvailableDetailView(snapshot: snapshot)

                HStack {
                    Text("TOP TOKEN USERS")
                        .sectionTitle()
                    Spacer()
                    LLMSessionModeToggle(selection: $sessionMode)
                }
                .padding(.top, 2)

                if selectedSessions.isEmpty {
                    Text("No local session token detail found")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    ForEach(selectedSessions) { session in
                        LLMSessionRow(session: session)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("ADVANCED")
                    .sectionTitle()
                Spacer()
                Text("\(snapshot.recentSessions.count) sessions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .monospacedDigit()
            }
        }
        .accentColor(.accentBlue)
        .sectionStyle()
    }

    private var selectedSessions: [LLMUsageSession] {
        switch sessionMode {
        case .recent:
            return snapshot.recentSessions
        case .highest:
            return snapshot.topWeeklySessions
        }
    }
}

enum LLMTokenUserMode: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case highest = "Highest"

    var id: String { rawValue }
}

struct LLMSessionModeToggle: View {
    @Binding var selection: LLMTokenUserMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LLMTokenUserMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(selection == mode ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(selection == mode ? Color.panelLift : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.background.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct LLMAvailableDetailView: View {
    let snapshot: LLMUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("AVAILABLE DETAIL")
                .sectionTitle()
            availableRow("Live limits", "\(snapshot.limits.count) limit groups")
            availableRow("Local windows", snapshot.localWindows.map(\.label).joined(separator: ", "))
            availableRow("Session totals", "Title, model, project, tokens")
            availableRow("Prompt detail", "Stored preview only")
            availableRow("Per-prompt tokens", "Not stored locally")
        }
    }

    private func availableRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct LLMSessionRow: View {
    let session: LLMUsageSession
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(tokenCount(session.tokens))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            HStack {
                Text(session.detail)
                    .lineLimit(1)
                Spacer()
                Text(relativeTime(session.updatedAt))
                    .monospacedDigit()
            }
            .font(.system(size: 11.5, weight: .regular))
            .foregroundStyle(.white.opacity(0.56))

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    LLMSessionDetailRow(label: "Project", value: session.projectName)
                    LLMSessionDetailRow(label: "Model", value: session.modelName)
                    LLMSessionDetailRow(label: "Tokens", value: tokenCount(session.tokens))
                    LLMSessionDetailRow(label: "Updated", value: session.updatedAt.map { absoluteTime($0) } ?? "-")
                    LLMSessionDetailRow(label: "Session", value: session.id)
                    Button {
                        openSessionContext()
                    } label: {
                        Label("Open Context", systemImage: "folder")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    Text(session.preview)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(3)
                        .padding(.top, 2)
                }
                .padding(.top, 4)
            } else {
                Text(session.preview)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.14)) {
                isExpanded.toggle()
            }
        }
    }

    private func openSessionContext() {
        let path = session.rolloutPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        let fileURL = URL(fileURLWithPath: path)
        if fileHasContent(fileURL) {
            NSWorkspace.shared.open(fileURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private func fileHasContent(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else {
            return false
        }
        return (values.fileSize ?? 0) > 0
    }
}

struct LLMSessionDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.72))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LLMUsageWindowRow: View {
    let window: LLMUsageWindow?

    var body: some View {
        HStack {
            Text(window?.label ?? "-")
                .font(.system(size: 15, weight: .regular))
            Spacer()
            Text(window.map { "\($0.remainingPercent)%" } ?? "-")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .monospacedDigit()
            Text(resetTime(window?.resetAt))
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.56))
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
    }
}

struct LLMUsageProgress: View {
    let window: LLMUsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window?.label ?? "-")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text(window.map { "\($0.remainingPercent)% left" } ?? "-")
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.freeGray.opacity(0.28))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentBlue)
                        .frame(width: proxy.size.width * usedRatio)
                }
            }
            .frame(height: 8)
            HStack {
                Text(window.map { "Used \($0.usedPercent)%" } ?? "-")
                Spacer()
                Text(resetLabel(window?.resetAt))
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.white.opacity(0.54))
            .monospacedDigit()
        }
    }

    private var usedRatio: CGFloat {
        CGFloat(Double(window?.usedPercent ?? 0) / 100)
    }
}

struct RingSegment: Identifiable {
    let id = UUID()
    let value: Double
    let color: Color
}

struct RingView: View {
    let title: String
    let percent: Int
    let segments: [RingSegment]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.freeGray.opacity(0.72), lineWidth: 8)

            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                Circle()
                    .trim(from: start(for: index), to: end(for: index))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text("\(percent)%")
                    .font(.system(size: 27, weight: .regular, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(width: 91, height: 91)
    }

    private func start(for index: Int) -> CGFloat {
        let prior = segments.prefix(index).reduce(0) { $0 + $1.value }
        return CGFloat(prior / 100)
    }

    private func end(for index: Int) -> CGFloat {
        let end = segments.prefix(index + 1).reduce(0) { $0 + $1.value }
        return CGFloat(end / 100)
    }
}

struct ValueRingView: View {
    let title: String
    let value: String
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.freeGray.opacity(0.72), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100) / 100))
                .stroke(Color.accentBlue, style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(value)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 78, height: 78)
    }
}

struct MetricRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct MetricCard: View {
    let title: String
    let rows: [MetricRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .sectionTitle()

            ForEach(rows) { row in
                HStack {
                    if !row.label.isEmpty {
                        Text(row.label)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Spacer()
                    Text(row.value)
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .sectionStyle()
    }
}

struct CompactMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .sectionTitle()
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(value == "-" || title == "NOT CONNECTED" ? .white.opacity(0.54) : .white)
                .monospacedDigit()
        }
        .sectionStyle()
    }
}

struct CPUHistoryCard: View {
    let snapshot: CPUGPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("CPU")
                    .sectionTitle()
                Spacer()
                Text(cpuHeader)
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<48, id: \.self) { index in
                    VStack(spacing: 0) {
                        Color.wiredPink.frame(height: CGFloat(8 + (index % 5)))
                        Color.accentBlue.frame(height: CGFloat(14 + (index % 4)))
                    }
                    .frame(width: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: 9) {
                LegendInline(color: .accentBlue, label: "User", value: "\(snapshot.cpuUserPercent)%")
                LegendInline(color: .wiredPink, label: "System", value: "\(snapshot.cpuSystemPercent)%")
            }
        }
        .sectionStyle()
    }

    private var cpuHeader: String {
        if let cpuGHz = snapshot.cpuGHz, let cpuTemperature = snapshot.cpuTemperature {
            return String(format: "%.2f GHz, %@", cpuGHz, temperature(cpuTemperature))
        }
        if let cpuGHz = snapshot.cpuGHz {
            return String(format: "%.2f GHz", cpuGHz)
        }
        if let cpuTemperature = snapshot.cpuTemperature {
            return temperature(cpuTemperature)
        }
        return "Public CPU"
    }
}

struct CoreRingsView: View {
    let snapshot: CPUGPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(coreRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { core in
                            MiniRing(percent: Double(core.percent), color: core.color)
                                .help("\(core.label) \(core.displayIndex): \(core.percent)%")
                        }
                    }
                }
            }
            LegendRow(
                color: .wiredPink,
                label: "Efficiency Cores",
                value: "\(snapshot.efficiencyPercent)%",
                help: "Average active load across efficiency cores, from per-core host CPU ticks."
            )
            LegendRow(
                color: .accentBlue,
                label: "Performance Cores",
                value: "\(snapshot.performancePercent)%",
                help: "Average active load across performance cores, from per-core host CPU ticks."
            )
        }
        .sectionStyle()
    }

    private var coreRows: [[CPUCoreLoad]] {
        let loads = snapshot.coreLoads
        guard !loads.isEmpty else { return [] }
        return stride(from: 0, to: loads.count, by: 7).map { start in
            Array(loads[start..<min(start + 7, loads.count)])
        }
    }
}

struct MiniRing: View {
    let percent: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.freeGray.opacity(0.72), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100) / 100))
                .stroke(color, lineWidth: 4)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 19, height: 19)
    }
}

private extension CPUCoreLoad {
    var color: Color {
        switch kind {
        case .efficiency:
            return .wiredPink
        case .performance:
            return .accentBlue
        }
    }

    var label: String {
        switch kind {
        case .efficiency:
            return "Efficiency core"
        case .performance:
            return "Performance core"
        }
    }

    var displayIndex: Int { index + 1 }
}

enum CPUProcessScale: String, CaseIterable, Identifiable {
    case istatShare = "iStat"
    case activityMonitor = "Raw"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .istatShare:
            return "Share of the whole machine. Raw per-process CPU is divided by logical CPU count so it is closer to iStat's menu percentage scale."
        case .activityMonitor:
            return "Activity Monitor style. A process can exceed 100% because macOS reports CPU per core before grouping helper processes."
        }
    }
}

struct CPUProcessesView: View {
    let processes: [CPUProcess]
    @Binding var scale: CPUProcessScale

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("PROCESSES")
                    .sectionTitle()
                Spacer()
                CPUScaleSwitch(scale: $scale)
                    .help(scale.help)
            }
            ForEach(processes.prefix(3)) { process in
                HStack(spacing: 8) {
                    CPUProcessIcon(process: process)
                    Text(process.name)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", displayPercent(for: process)))
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .sectionStyle()
    }

    private func displayPercent(for process: CPUProcess) -> Double {
        switch scale {
        case .istatShare:
            return process.cpuPercent
        case .activityMonitor:
            return process.rawCPUPercent
        }
    }
}

struct CPUScaleSwitch: View {
    @Binding var scale: CPUProcessScale

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CPUProcessScale.allCases) { option in
                Button {
                    scale = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(scale == option ? .white : .white.opacity(0.62))
                        .background(scale == option ? Color.panelLift : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.background.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct GPUCard: View {
    let snapshot: CPUGPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GPU")
                    .sectionTitle()
                Spacer()
                Text(snapshot.fps.map { "\($0) FPS" } ?? "Requires helper")
                    .font(.system(size: 13.5, weight: .semibold))
            }
            HStack {
                ValueRingView(title: "GPU", value: percent(snapshot.gpuPercent), percent: Double(snapshot.gpuPercent ?? 0))
                ValueRingView(title: "MEM", value: percent(snapshot.gpuMemoryPercent), percent: Double(snapshot.gpuMemoryPercent ?? 0))
                ValueRingView(title: "TMP", value: temperature(snapshot.gpuTemperature), percent: temperaturePercent(snapshot.gpuTemperature))
            }
        }
        .sectionStyle()
    }
}

struct LegendInline: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .regular))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct NetworkGraphCard: View {
    let snapshot: NetworkSnapshot

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(spacing: 0) {
                    Text(ByteFormat.rate(snapshot.uploadBytesPerSecond))
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .monospacedDigit()
                    LegendInline(color: .wiredPink, label: "Upload", value: "")
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(ByteFormat.rate(snapshot.downloadBytesPerSecond))
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .monospacedDigit()
                    LegendInline(color: .accentBlue, label: "Download", value: "")
                }
            }

            NetworkBars(samples: snapshot.history)
                .frame(height: 95)

            HStack {
                Text("Upload \(ByteFormat.rate(snapshot.uploadBytesPerSecond))")
                Spacer()
                Text("Download \(ByteFormat.rate(snapshot.downloadBytesPerSecond))")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .monospacedDigit()
        }
        .sectionStyle()
    }
}

struct NetworkBars: View {
    let samples: [NetworkSample]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(samples.map { max($0.uploadBytesPerSecond, $0.downloadBytesPerSecond) }.max() ?? 1, 1)
            let halfHeight = proxy.size.height / 2
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Color.wiredPink
                            .frame(height: max(2, halfHeight * CGFloat(sample.uploadBytesPerSecond) / CGFloat(maxValue)))
                        Color.accentBlue
                            .frame(height: max(2, halfHeight * CGFloat(sample.downloadBytesPerSecond) / CGFloat(maxValue)))
                        Spacer(minLength: 0)
                    }
                    .frame(width: 3, height: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

struct NetworkInterfaceCard: View {
    let snapshot: NetworkSnapshot

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: snapshot.interfaceName == nil ? "wifi.slash" : "wifi")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
            Text(snapshot.interfaceName == nil ? "Not Connected" : "Wi-Fi")
                .font(.system(size: 13.5, weight: .regular))
            Spacer()
            Text(snapshot.interfaceDisplayName)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
        }
        .sectionStyle()
    }
}

struct NetworkTotalsView: View {
    let snapshot: NetworkSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("INTERFACE TOTAL")
                    .sectionTitle()
                Spacer()
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                Text(" ")
                    .frame(width: 42)
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))
            }

            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 17, height: 17)
                Text(snapshot.interfaceName ?? "No Interface")
                    .font(.system(size: 13.5, weight: .regular))
                    .lineLimit(1)
                Spacer()
                Text(ByteFormat.compactRate(snapshot.uploadBytesPerSecond))
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                Text(ByteFormat.compactRate(snapshot.downloadBytesPerSecond))
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .sectionStyle()
        .help("Interface throughput from macOS network counters. True per-process network attribution needs a separate nettop/NStat collector.")
    }
}

struct BreakdownView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(spacing: 7) {
            LegendRow(
                color: .accentBlue,
                label: "App",
                value: ByteFormat.memory(snapshot.breakdown.app),
                help: "App memory: memory used by apps and anonymous process pages. Calculated as physical memory minus available cache/free, wired memory, and compressed memory."
            )
            LegendRow(
                color: .wiredPink,
                label: "Wired",
                value: ByteFormat.memory(snapshot.breakdown.wired),
                help: "Wired memory: kernel and driver memory that must stay in RAM and cannot be compressed or paged out."
            )
            LegendRow(
                color: .compressedYellow,
                label: "Compressed",
                value: ByteFormat.memory(snapshot.breakdown.compressed),
                help: "Compressed memory: app memory macOS compressed in RAM instead of writing it to swap."
            )
            LegendRow(
                color: .freeGray,
                label: "Free",
                value: ByteFormat.memory(snapshot.breakdown.free),
                help: "Free/available memory: free, speculative, and file-backed cache pages that macOS can quickly reuse for apps."
            )
        }
        .sectionStyle()
    }
}

struct ProcessesView: View {
    let groupedProcesses: [ProcessMemory]
    let processRows: [ProcessMemory]
    @State private var mode = ProcessListMode.apps

    private var processes: [ProcessMemory] {
        switch mode {
        case .apps:
            return groupedProcesses
        case .rows:
            return processRows
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("PROCESSES")
                    .sectionTitle()
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(ProcessListMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 94)
                .controlSize(.mini)
                .help(mode.help)
            }

            ForEach(processes) { process in
                HStack(spacing: 8) {
                    ProcessIcon(process: process)
                    Text(process.name)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineLimit(1)
                    Spacer()
                    Text(ByteFormat.memory(process.bytes))
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .sectionStyle()
    }
}

enum ProcessListMode: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case rows = "Rows"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .apps:
            return "Group helper processes by owning app bundle, similar to iStat."
        case .rows:
            return "Show individual process rows using the Activity Monitor-like MEM value."
        }
    }
}

struct PagingView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(spacing: 7) {
            LabelValueRow(label: "Page Ins", value: ByteFormat.memory(snapshot.pageIns))
            LabelValueRow(label: "Page Outs", value: ByteFormat.memory(snapshot.pageOuts))
        }
        .sectionStyle()
    }
}

struct SwapView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("SWAP")
                    .sectionTitle()
                Spacer()
                Text("\(ByteFormat.memory(snapshot.swapUsed)) of \(ByteFormat.memory(snapshot.swapTotal))")
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.freeGray.opacity(0.55), lineWidth: 1)
                        .background(Color.clear)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentBlue)
                        .frame(width: proxy.size.width * swapRatio)
                }
            }
            .frame(height: 10)
        }
        .sectionStyle()
    }

    private var swapRatio: CGFloat {
        guard snapshot.swapTotal > 0 else { return 0 }
        return min(CGFloat(Double(snapshot.swapUsed) / Double(snapshot.swapTotal)), 1)
    }
}

struct HistoryView: View {
    let history: [MemoryBreakdown]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MEMORY")
                    .sectionTitle()
                Spacer()
                Text("1 Hour")
                    .font(.system(size: 12, weight: .semibold))
            }

            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, sample in
                        HistoryBar(sample: sample)
                            .frame(width: max((proxy.size.width - 118) / 60, 3))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(height: 42)
        }
        .sectionStyle()
    }
}

struct ActionBarView: View {
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            Spacer()

            if let onPopOut {
                IconActionButton(systemName: "rectangle.on.rectangle", help: "Open as window", action: onPopOut)
            }

            if let onQuit {
                IconActionButton(systemName: "power", help: "Quit app", action: onQuit)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct IconActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 23, height: 20)
                .background(Color.panelLift.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct HistoryBar: View {
    let sample: MemoryBreakdown

    var body: some View {
        GeometryReader { proxy in
            let total = max(Double(sample.total), 1)
            VStack(spacing: 0) {
                Color.compressedYellow.frame(height: proxy.size.height * Double(sample.compressed) / total)
                Color.wiredPink.frame(height: proxy.size.height * Double(sample.wired) / total)
                Color.accentBlue.frame(height: proxy.size.height * Double(sample.app) / total)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct LegendRow: View {
    let color: Color
    let label: String
    let value: String
    let help: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
            Text(label)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .help(help)
    }
}

struct LabelValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
        }
    }
}

struct ProcessIcon: View {
    let process: ProcessMemory

    var body: some View {
        if let image = icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.panelLift)
                .overlay {
                    Text(String(process.name.prefix(1)))
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 17, height: 17)
        }
    }

    private var icon: NSImage? {
        if let appPath = process.appPath {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        if let appIcon = NSRunningApplication(processIdentifier: process.pid)?.icon {
            return appIcon
        }

        guard process.path.hasPrefix("/") else { return nil }
        return NSWorkspace.shared.icon(forFile: process.path)
    }
}

struct CPUProcessIcon: View {
    let process: CPUProcess

    var body: some View {
        if let image = icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.panelLift)
                .overlay {
                    Text(String(process.name.prefix(1)))
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 17, height: 17)
        }
    }

    private var icon: NSImage? {
        if let appPath = process.appPath {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        guard process.path.hasPrefix("/") else { return nil }
        return NSWorkspace.shared.icon(forFile: process.path)
    }
}

struct NetworkProcessIcon: View {
    let process: NetworkProcess

    var body: some View {
        if let image = icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.panelLift)
                .overlay {
                    Text(String(process.name.prefix(1)))
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 17, height: 17)
        }
    }

    private var icon: NSImage? {
        if let appPath = process.appPath {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        guard process.path.hasPrefix("/") else { return nil }
        return NSWorkspace.shared.icon(forFile: process.path)
    }
}

private enum TemperatureDisplayUnit {
    case celsius
    case fahrenheit

    static var preferred: TemperatureDisplayUnit {
        let fahrenheitRegions = Set(["US", "LR", "MM"])
        if let regionCode = Locale.current.region?.identifier, fahrenheitRegions.contains(regionCode) {
            return .fahrenheit
        }
        return .celsius
    }

    func displayValue(celsius: Double) -> Double {
        switch self {
        case .celsius:
            return celsius
        case .fahrenheit:
            return celsius * 9 / 5 + 32
        }
    }

    var suffix: String {
        switch self {
        case .celsius:
            return "°C"
        case .fahrenheit:
            return "°F"
        }
    }
}

private func temperature(_ value: Double?) -> String {
    guard let value else {
        return "-\(TemperatureDisplayUnit.preferred.suffix)"
    }
    let unit = TemperatureDisplayUnit.preferred
    return "\(Int(unit.displayValue(celsius: value).rounded()))\(unit.suffix)"
}

private func temperaturePercent(_ value: Double?) -> Double {
    guard let value else { return 0 }
    return min(max(value / 120 * 100, 0), 100)
}

private func fanStatus(_ snapshot: SensorSnapshot) -> String {
    guard let rpm = snapshot.fanRPM else { return "-" }
    return rpm > 0 ? "ON" : "OFF"
}

private func fanPercent(_ snapshot: SensorSnapshot) -> Double {
    guard let rpm = snapshot.fanRPM else { return 0 }
    return rpm > 0 ? 100 : 0
}

private func percent(_ value: Int?) -> String {
    guard let value else { return "-%" }
    return "\(value)%"
}

private func rpm(_ value: Int?) -> String {
    guard let value else { return "-" }
    return "\(value.formatted()) rpm"
}

private func amps(_ value: Double?) -> String {
    guard let value else { return "-" }
    return String(format: "%.1f A", value)
}

private func watts(_ value: Double?) -> String {
    guard let value else { return "-" }
    return String(format: "%.1f W", value)
}

private func wattsCompact(_ value: Double?) -> String {
    guard let value else { return "-W" }
    return String(format: "%.0f W", value)
}

private func powerPercent(_ value: Double?) -> Double {
    guard let value else { return 0 }
    return min(max(value / 100 * 100, 0), 100)
}

private func volts(_ value: Double?) -> String {
    guard let value else { return "-" }
    return String(format: "%.1f V", value)
}

private func ghz(_ value: Double?) -> String {
    guard let value else { return "-" }
    return String(format: "%.2f GHz", value)
}

private func lux(_ value: Int?) -> String {
    guard let value else { return "-" }
    return "\(value.formatted()) Lux"
}

private func tokenCount(_ value: UInt64) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

private func planName(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "-" }
    if value.lowercased() == "prolite" {
        return "Pro Lite"
    }
    return value
        .split(separator: "_")
        .map { part in
            part.prefix(1).uppercased() + part.dropFirst()
        }
        .joined(separator: " ")
}

private func resetTime(_ value: Date?) -> String {
    guard let value else { return "-" }
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: value)
}

private func resetLabel(_ value: Date?) -> String {
    guard let value else { return "Reset unavailable" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return "Resets \(formatter.localizedString(for: value, relativeTo: Date()))"
}

private func relativeTime(_ value: Date?) -> String {
    guard let value else { return "-" }
    if abs(value.timeIntervalSinceNow) < 60 {
        return "Now"
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: value, relativeTo: Date())
}

private func absoluteTime(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: value)
}

extension View {
    func sectionStyle() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension Text {
    func sectionTitle() -> some View {
        self
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Color.accentBlue)
    }
}

extension Color {
    static let background = Color(red: 27 / 255, green: 30 / 255, blue: 39 / 255)
    static let panel = Color(red: 35 / 255, green: 38 / 255, blue: 52 / 255)
    static let panelLift = Color(red: 45 / 255, green: 49 / 255, blue: 65 / 255)
    static let accentBlue = Color(red: 0 / 255, green: 128 / 255, blue: 255 / 255)
    static let wiredPink = Color(red: 248 / 255, green: 65 / 255, blue: 151 / 255)
    static let compressedYellow = Color(red: 255 / 255, green: 202 / 255, blue: 18 / 255)
    static let freeGray = Color(red: 104 / 255, green: 111 / 255, blue: 132 / 255)
}
