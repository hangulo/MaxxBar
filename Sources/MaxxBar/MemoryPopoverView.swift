import AppKit
import SwiftUI

struct MemoryPopoverView: View {
    @ObservedObject var model: MemoryModel
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    var onStartDeepTrace: (() -> Void)?
    var fixedSize: Bool
    @State private var selectedPanel = StatsPanel.runway

    init(
        model: MemoryModel,
        onPopOut: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        onStartDeepTrace: (() -> Void)? = nil,
        selectedPanel: StatsPanel = .runway,
        fixedSize: Bool = true
    ) {
        self.model = model
        self.onPopOut = onPopOut
        self.onQuit = onQuit
        self.onStartDeepTrace = onStartDeepTrace
        self.fixedSize = fixedSize
        _selectedPanel = State(initialValue: selectedPanel)
    }

    var body: some View {
        VStack(spacing: 5) {
            PanelSwitch(selectedPanel: $selectedPanel)

            switch selectedPanel {
            case .memory:
                MemoryPanelView(model: model, onPopOut: onPopOut, onQuit: onQuit)
            case .cpuGPU:
                CPUGPUPanelView(snapshot: model.cpuGPU, sensors: model.sensors, onPopOut: onPopOut, onQuit: onQuit)
            case .llmUsage:
                AIUsagePanelView(
                    aiUsage: model.aiUsage,
                    snapshot: model.llmUsage,
                    quotaHistory: model.llmQuotaHistory,
                    onOpenAIReport: { model.openAIUsageReport() },
                    onStartDeepTrace: onStartDeepTrace,
                    onPopOut: onPopOut,
                    onQuit: onQuit
                )
            case .moments:
                MaxxMomentsPanelView(
                    aiUsage: model.aiUsage,
                    onCaptureMaxxMoment: { sentiment, note, includeScreenshot in
                        model.captureMaxxMoment(sentiment: sentiment, note: note, includeScreenshot: includeScreenshot)
                    },
                    onOpenAIReport: { model.openAIUsageReport() },
                    onPopOut: onPopOut,
                    onQuit: onQuit
                )
            case .runway:
                LLMRunwayPanelView(
                    snapshot: model.llmUsage,
                    quotaHistory: model.llmQuotaHistory,
                    onSampleQuota: { model.captureLLMQuotaSample() },
                    onPopOut: onPopOut,
                    onQuit: onQuit
                )
            }

            ActionBarView(
                onOpenHub: { model.openAIUsageReport() },
                onStartDeepTrace: onStartDeepTrace,
                onPopOut: onPopOut,
                onQuit: onQuit
            )
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
    case runway = "Runway"
    case llmUsage = "Insights"
    case moments = "Moments"
    case memory = "Memory"
    case cpuGPU = "CPU/GPU"

    var id: String { rawValue }

    static var visibleCases: [StatsPanel] {
        [.runway, .llmUsage, .moments, .memory]
    }
}

struct PanelSwitch: View {
    @Binding var selectedPanel: StatsPanel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsPanel.visibleCases) { panel in
                Button {
                    selectedPanel = panel
                } label: {
                    Text(panel.rawValue)
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(selectedPanel == panel ? .white : .white.opacity(0.68))
                        .background(selectedPanel == panel ? Color.panelLift : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
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
            MemoryRunwayHeroView(snapshot: model.snapshot)

            BreakdownView(snapshot: model.snapshot)

            ProcessesView(groupedProcesses: model.snapshot.processes, processRows: model.snapshot.processRows)

            SwapView(snapshot: model.snapshot)

        }
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
    let sensors: SensorSnapshot
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var processScale = CPUProcessScale.istatShare

    var body: some View {
        VStack(spacing: 7) {
            CPUHistoryCard(snapshot: snapshot)
            CoreRingsView(snapshot: snapshot)
            CPUProcessesView(processes: snapshot.processes, scale: $processScale)
            SensorSummaryRingsView(snapshot: sensors)
            MetricCard(title: "TEMPERATURE", rows: temperatureRows)
            MetricCard(title: "UPTIME", rows: [MetricRow(label: "", value: snapshot.uptime)])
        }
    }

    private var temperatureRows: [MetricRow] {
        guard !sensors.temperatureReadings.isEmpty else {
            return [MetricRow(label: "CPU / GPU / Fans", value: "Requires helper")]
        }

        return sensors.temperatureReadings.map { reading in
            MetricRow(label: reading.label, value: temperature(reading.celsius))
        }
    }
}

struct SensorSummaryRingsView: View {
    let snapshot: SensorSnapshot

    var body: some View {
        HStack(spacing: 16) {
            ValueRingView(title: "CPU", value: temperature(snapshot.cpuTemperature), percent: temperaturePercent(snapshot.cpuTemperature))
            ValueRingView(title: "GPU", value: temperature(snapshot.gpuTemperature), percent: temperaturePercent(snapshot.gpuTemperature))
            ValueRingView(title: "FANS", value: fanStatus(snapshot), percent: fanPercent(snapshot))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        }
    }
}

struct AIUsagePanelView: View {
    let aiUsage: AIUsageSnapshot
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    var onOpenAIReport: (() -> Void)?
    var onStartDeepTrace: (() -> Void)?
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    AIUsageOverviewCard(snapshot: aiUsage)
                    AITransferCard(snapshot: aiUsage)
                    AIWorkflowMiniCard(snapshot: aiUsage)
                    LLMSessionTimelineCard(snapshot: snapshot)
                }
            }

        }
    }
}

struct MaxxMomentsPanelView: View {
    let aiUsage: AIUsageSnapshot
    var onCaptureMaxxMoment: ((String, String, Bool) -> Void)?
    var onOpenAIReport: (() -> Void)?
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    MaxxMomentCard(
                        snapshot: aiUsage,
                        onCaptureMaxxMoment: onCaptureMaxxMoment,
                        onOpenAIReport: onOpenAIReport
                    )
                }
            }

        }
    }
}

struct LLMRunwayPanelView: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    var onSampleQuota: (() -> Void)?
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var advancedExpanded = false

    var body: some View {
        VStack(spacing: 7) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    if let codexLimit {
                        LLMUsageLimitCard(
                            limit: codexLimit,
                            title: "CODEX RUNWAY (\(planName(snapshot.planType)))",
                            resetCreditCount: snapshot.resetCreditCount,
                            resetCreditExpirations: snapshot.resetCreditExpirations
                        )
                    } else {
                        LLMUsageUnavailableCard(message: snapshot.error ?? "Codex usage unavailable")
                    }

                    LLMLocalUsageCard(snapshot: snapshot, quotaHistory: quotaHistory, onSampleQuota: onSampleQuota)
                    DrawdownInsightCard(snapshot: snapshot, quotaHistory: quotaHistory)
                    LLMAdvancedUsageCard(snapshot: snapshot, isExpanded: $advancedExpanded)
                }
            }

        }
    }

    private var codexLimit: LLMUsageLimit? {
        snapshot.limits.first(where: { $0.name == "Codex" }) ?? snapshot.limits.first
    }

}

struct AIUsageOverviewCard: View {
    let snapshot: AIUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle("MAXX INSIGHTS", help: maxxInsightsHelp)
                Spacer()
                Text(snapshot.activeTool ?? "Watching")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle((snapshot.activeTool == nil ? Color.white.opacity(0.52) : Color.accentBlue))
            }

            HStack(spacing: 7) {
                aiMetric("Today", "\(snapshot.sessionsToday)", "sessions")
                aiMetric("AI time", aiDuration(snapshot.timeTodaySeconds), "today")
                aiMetric("Avg", aiDuration(snapshot.averageSessionSeconds), "session")
            }

        }
        .sectionStyle()
    }

    private func aiMetric(_ label: String, _ value: String, _ sublabel: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(sublabel)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.background.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct AITransferCard: View {
    let snapshot: AIUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InstantHelpTitle("AI OUTPUT DESTINATIONS", help: "Tracks Cmd+C and Cmd+V as context metadata only. MaxxBar never reads or stores clipboard contents.")
                Spacer()
                Text("\(snapshot.pasteEventsToday) today")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .monospacedDigit()
            }

            if snapshot.transferFlows.isEmpty {
                Text("Copy from an AI surface and paste into a work app to reveal output flows.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(snapshot.transferFlows.prefix(3)) { flow in
                    HStack(spacing: 5) {
                        Text(trimmedText(flow.source, maxLength: 13))
                        Image(systemName: "arrow.right")
                            .foregroundStyle(Color.accentBlue)
                        Text(trimmedText(flow.destination, maxLength: 13))
                        Spacer(minLength: 3)
                        Text("\(flow.count)x")
                            .foregroundStyle(Color.accentBlue)
                            .monospacedDigit()
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .help("\(flow.useCase) · \(flow.confidence) confidence")
                }
            }

            HStack(spacing: 6) {
                transferMetric("Copy", "\(snapshot.copyEventsToday)")
                transferMetric("Paste", "\(snapshot.pasteEventsToday)")
                transferMetric("Insights", "\(snapshot.insightEventsToday)")
            }

            if let copiedFrom = snapshot.topCopiedFrom.first?.label {
                contextRow("From", copiedFrom)
            }
            if let pastedInto = snapshot.topPastedInto.first?.label {
                contextRow("To", pastedInto)
            }
        }
        .sectionStyle()
    }

    private func transferMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.background.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func contextRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct AIWorkflowMiniCard: View {
    let snapshot: AIUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InstantHelpTitle("AI FLOW", help: aiFlowHelp)
                Spacer()
                Text("\(snapshot.sessionsSevenDays) 7d")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .monospacedDigit()
            }

            if snapshot.workflowPaths.isEmpty {
                Text("No before/after paths yet")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                MiniSankeyView(paths: Array(snapshot.workflowPaths.prefix(5)))
            }
        }
        .sectionStyle()
    }
}

struct MiniSankeyNode: Identifiable {
    var id: String { "\(column)-\(label)" }
    let column: String
    let label: String
    let count: Int
    let index: Int
}

struct MiniSankeyView: View {
    let paths: [AIWorkflowPath]

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                sankeyStageLabel("Before")
                Spacer()
                sankeyStageLabel("AI")
                Spacer()
                sankeyStageLabel("After")
            }

            GeometryReader { proxy in
                let size = proxy.size
                let beforeNodes = nodes(for: .before)
                let surfaceNodes = nodes(for: .surface)
                let afterNodes = nodes(for: .after)
                let nodeWidth = min(max(size.width * 0.23, 58), 76)
                let beforeX: CGFloat = nodeWidth / 2
                let surfaceX: CGFloat = size.width / 2
                let afterX: CGFloat = size.width - nodeWidth / 2

                ZStack {
                    Canvas { context, canvasSize in
                        for path in paths {
                            let width = linkWidth(for: path.count)
                            let beforeY = yPosition(for: path.before, in: beforeNodes, height: canvasSize.height)
                            let surfaceY = yPosition(for: path.surface, in: surfaceNodes, height: canvasSize.height)
                            let afterY = yPosition(for: path.after, in: afterNodes, height: canvasSize.height)

                            var left = Path()
                            left.move(to: CGPoint(x: beforeX + nodeWidth / 2, y: beforeY))
                            left.addCurve(
                                to: CGPoint(x: surfaceX - nodeWidth / 2, y: surfaceY),
                                control1: CGPoint(x: beforeX + nodeWidth, y: beforeY),
                                control2: CGPoint(x: surfaceX - nodeWidth, y: surfaceY)
                            )
                            context.stroke(
                                left,
                                with: .color(Color.accentBlue.opacity(0.22)),
                                style: StrokeStyle(lineWidth: width, lineCap: .round)
                            )

                            var right = Path()
                            right.move(to: CGPoint(x: surfaceX + nodeWidth / 2, y: surfaceY))
                            right.addCurve(
                                to: CGPoint(x: afterX - nodeWidth / 2, y: afterY),
                                control1: CGPoint(x: surfaceX + nodeWidth, y: surfaceY),
                                control2: CGPoint(x: afterX - nodeWidth, y: afterY)
                            )
                            context.stroke(
                                right,
                                with: .color(Color.accentBlue.opacity(0.22)),
                                style: StrokeStyle(lineWidth: width, lineCap: .round)
                            )
                        }
                    }

                    ForEach(beforeNodes) { node in
                        nodeView(node)
                            .frame(width: nodeWidth, height: nodeHeight(for: node.count))
                            .position(x: beforeX, y: yPosition(for: node.label, in: beforeNodes, height: size.height))
                    }

                    ForEach(surfaceNodes) { node in
                        nodeView(node)
                            .frame(width: nodeWidth, height: nodeHeight(for: node.count))
                            .position(x: surfaceX, y: yPosition(for: node.label, in: surfaceNodes, height: size.height))
                    }

                    ForEach(afterNodes) { node in
                        nodeView(node)
                            .frame(width: nodeWidth, height: nodeHeight(for: node.count))
                            .position(x: afterX, y: yPosition(for: node.label, in: afterNodes, height: size.height))
                    }
                }
            }
            .frame(height: 124)
        }
    }

    private enum SankeyColumn {
        case before
        case surface
        case after
    }

    private func sankeyStageLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
    }

    private func nodeView(_ node: MiniSankeyNode) -> some View {
        VStack(spacing: 0) {
            Text(trimmedText(node.label, maxLength: 12))
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(node.count)x")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .background(Color.accentBlue.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func nodes(for column: SankeyColumn) -> [MiniSankeyNode] {
        var counts: [String: Int] = [:]
        for path in paths {
            let label: String
            switch column {
            case .before:
                label = path.before
            case .surface:
                label = path.surface
            case .after:
                label = path.after
            }
            counts[label, default: 0] += path.count
        }

        return counts
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(column == .surface ? 1 : 4)
            .enumerated()
            .map { offset, entry in
                MiniSankeyNode(column: columnName(column), label: entry.key, count: entry.value, index: offset)
            }
    }

    private func columnName(_ column: SankeyColumn) -> String {
        switch column {
        case .before: return "before"
        case .surface: return "surface"
        case .after: return "after"
        }
    }

    private func yPosition(for label: String, in nodes: [MiniSankeyNode], height: CGFloat) -> CGFloat {
        guard let node = nodes.first(where: { $0.label == label }) ?? nodes.first else {
            return height / 2
        }
        let count = max(nodes.count, 1)
        return height * CGFloat(node.index + 1) / CGFloat(count + 1)
    }

    private func nodeHeight(for count: Int) -> CGFloat {
        min(max(18 + CGFloat(count) * 1.8, 20), 38)
    }

    private func linkWidth(for count: Int) -> CGFloat {
        let maxCount = max(paths.map(\.count).max() ?? 1, 1)
        return min(max(0.8 + 1.2 * CGFloat(count) / CGFloat(maxCount), 1), 2)
    }
}

struct MaxxMomentCard: View {
    let snapshot: AIUsageSnapshot
    var onCaptureMaxxMoment: ((String, String, Bool) -> Void)?
    var onOpenAIReport: (() -> Void)?
    @State private var isExpanded = false
    @State private var selectedSentiment = "Frustration"
    @State private var includeScreenshot = true
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label("Capture Maxx Moment", systemImage: "exclamationmark.bubble")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.accentBlue.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(onCaptureMaxxMoment == nil)
                .help("Capture a local note about this AI moment, with an optional screenshot")

                Text(momentText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .monospacedDigit()
                    .frame(width: 62, alignment: .trailing)

                IconActionButton(systemName: "chart.bar.xaxis", help: "Open AI usage insights", action: { onOpenAIReport?() })
                    .disabled(onOpenAIReport == nil)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        MaxxMomentSentimentButton(
                            title: "Frustration",
                            systemImage: "exclamationmark.triangle",
                            isSelected: selectedSentiment == "Frustration"
                        ) {
                            selectedSentiment = "Frustration"
                        }
                        MaxxMomentSentimentButton(
                            title: "Delight",
                            systemImage: "sparkles",
                            isSelected: selectedSentiment == "Delight"
                        ) {
                            selectedSentiment = "Delight"
                        }
                    }

                    Toggle(isOn: $includeScreenshot) {
                        Text("Include screenshot")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.74))
                    }
                    .toggleStyle(.checkbox)
                    .help("When enabled, MaxxBar saves one local screenshot for this Maxx Moment. Nothing is uploaded.")

                    TextField("Add context...", text: $note)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, weight: .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.background.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Button {
                        onCaptureMaxxMoment?(selectedSentiment, note, includeScreenshot)
                        note = ""
                        isExpanded = false
                    } label: {
                        Text("Save Maxx Moment")
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.accentBlue.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(.top, 1)
            }

            if !snapshot.recentMoments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshot.recentMoments.prefix(3)) { moment in
                        recentMomentRow(moment)
                    }
                }
                .padding(.top, 1)
            }
        }
        .sectionStyle()
    }

    private func recentMomentRow(_ moment: MaxxMomentSummary) -> some View {
        HStack(spacing: 5) {
            Text(moment.sentiment)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(moment.sentiment == "Delight" ? Color.green.opacity(0.88) : Color.accentBlue)
                .frame(width: 58, alignment: .leading)
            Text(moment.note)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
            Spacer(minLength: 4)
            if moment.screenshotPath != nil {
                Image(systemName: "camera")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            Text(relativeTime(moment.ts))
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.42))
                .monospacedDigit()
        }
        .help(maxxMomentTooltip(moment))
    }

    private func maxxMomentTooltip(_ moment: MaxxMomentSummary) -> String {
        var lines = [
            "\(moment.sentiment) Maxx Moment",
            "Captured: \(absoluteTime(moment.ts))",
            "App: \(moment.app)"
        ]
        if let surface = moment.surface {
            lines.append("Surface: \(surface)")
        }
        if !moment.note.isEmpty {
            lines.append("Note: \(moment.note)")
        }
        if let screenshotPath = moment.screenshotPath {
            lines.append("Screenshot: \(screenshotPath)")
        }
        return lines.joined(separator: "\n")
    }

    private var momentText: String {
        if let lastMomentAt = snapshot.lastMomentAt {
            return relativeTime(lastMomentAt)
        }
        return "\(snapshot.momentsToday) today"
    }
}

struct MaxxMomentSentimentButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
        .background(isSelected ? Color.panelLift : Color.background.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
    var resetCreditCount: Int? = nil
    var resetCreditExpirations: [LLMResetCreditExpiration] = []
    @State private var resetDetailsPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle(title ?? limit.name.uppercased(), help: codexRunwayHelp)
                Spacer()
                if let resetCreditCount {
                    Text("\(resetCreditCount) resets")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.panelLift.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resetDetailsPresented.toggle()
                        }
                        .popover(isPresented: $resetDetailsPresented, arrowEdge: .top) {
                            ResetCreditDetailsPopover(count: resetCreditCount, expirations: resetCreditExpirations)
                        }
                }
            }
            LLMUsageProgress(window: limit.primary)
            LLMUsageProgress(window: limit.secondary)
        }
        .sectionStyle()
    }
}

struct ResetCreditDetailsPopover: View {
    let count: Int
    let expirations: [LLMResetCreditExpiration]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(count) reset \(count == 1 ? "credit" : "credits")")
                .font(.system(size: 14, weight: .semibold))

            if expirations.isEmpty {
                Text("Codex reports the available count, but not per-credit expiration dates.")
                    .font(.system(size: 12.5, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)

                Text("The 5h and weekly reset times are already shown on the runway bars.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(expirations) { expiration in
                        Text(resetCreditExpirationLine(expiration))
                            .font(.system(size: 12.5, weight: .regular))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .foregroundStyle(Color.black.opacity(0.86))
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(Color.white)
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

struct DrawdownInsightCard: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    @State private var mode = LLMQuotaDrawdownMode.last

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle("DRAWDOWN INSIGHT", help: drawdownInsightHelp)
                Spacer()
                if insight != nil {
                    LLMQuotaDrawdownModeToggle(selection: $mode)
                }
            }

            if let insight {
                LLMQuotaDrawdownInsightView(insight: insight)
            } else {
                Text("No local drawdown pattern yet")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .sectionStyle()
    }

    private var insight: LLMQuotaDrawdownInsight? {
        quotaDrawdownInsight(from: rangedQuotaHistory, mode: mode)
    }

    private var rangedQuotaHistory: [LLMQuotaHistorySample] {
        let cutoff = Date().addingTimeInterval(-LLMQuotaHistoryRange.sixHours.interval)
        let samples = effectiveQuotaHistory.filter { $0.sampledAt >= cutoff }
        return samples.isEmpty ? Array(effectiveQuotaHistory.suffix(1)) : samples
    }

    private var effectiveQuotaHistory: [LLMQuotaHistorySample] {
        if !quotaHistory.isEmpty {
            return quotaHistory
        }

        guard let limit = snapshot.limits.first(where: { $0.name == "Codex" }) ?? snapshot.limits.first else {
            return []
        }

        return [
            LLMQuotaHistorySample(
                sampledAt: snapshot.lastUpdated ?? Date(),
                primaryRemainingPercent: limit.primary?.remainingPercent,
                weeklyRemainingPercent: limit.secondary?.remainingPercent,
                planType: snapshot.planType
            )
        ]
    }
}

struct LLMLocalUsageCard: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    var onSampleQuota: (() -> Void)?
    @State private var drawdownRange = LLMQuotaHistoryRange.sixHours

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    InstantHelpTitle("LIMIT DRAWDOWN", help: limitDrawdownHelp)
                    Spacer()
                    Button {
                        onSampleQuota?()
                    } label: {
                        Text("Updated \(localDrawdownUpdatedAt(effectiveQuotaHistory.last?.sampledAt))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.52))
                            .monospacedDigit()
                    }
                    .buttonStyle(.plain)
                    .disabled(onSampleQuota == nil)
                    .help("Capture the current 5H and Week values now")
                }

                HStack {
                    Spacer()
                    LLMQuotaHistoryRangeToggle(selection: $drawdownRange)
                }
            }

            LLMQuotaHistoryGraph(samples: rangedQuotaHistory, range: drawdownRange)
        }
        .sectionStyle()
    }

    private var effectiveQuotaHistory: [LLMQuotaHistorySample] {
        if !quotaHistory.isEmpty {
            return quotaHistory
        }

        guard let limit = snapshot.limits.first(where: { $0.name == "Codex" }) ?? snapshot.limits.first else {
            return []
        }

        return [
            LLMQuotaHistorySample(
                sampledAt: snapshot.lastUpdated ?? Date(),
                primaryRemainingPercent: limit.primary?.remainingPercent,
                weeklyRemainingPercent: limit.secondary?.remainingPercent,
                planType: snapshot.planType
            )
        ]
    }

    private var rangedQuotaHistory: [LLMQuotaHistorySample] {
        let cutoff = Date().addingTimeInterval(-drawdownRange.interval)
        let samples = effectiveQuotaHistory.filter { $0.sampledAt >= cutoff }
        return samples.isEmpty ? Array(effectiveQuotaHistory.suffix(1)) : samples
    }
}

struct LLMSessionTimelineCard: View {
    let snapshot: LLMUsageSnapshot
    @State private var range = LLMQuotaHistoryRange.sixHours

    private var sessionTimelineSessions: [LLMUsageSession] {
        var seen = Set<String>()
        let combined = (snapshot.recentSessions + snapshot.topWeeklySessions).filter { session in
            guard !seen.contains(session.id) else { return false }
            seen.insert(session.id)
            return true
        }

        let axisEnd = Date()
        let axisStart = axisEnd.addingTimeInterval(-range.interval)
        return combined
            .filter { session in
                let end = session.updatedAt ?? session.createdAt ?? axisEnd
                let start = session.createdAt ?? end.addingTimeInterval(-min(range.interval, 3_600))
                return start <= axisEnd && end >= axisStart
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
                let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.tokens > rhs.tokens
                }
                return lhsDate > rhsDate
            }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                InstantHelpTitle("SESSION TIMELINE", help: sessionTimelineHelp)
                Spacer()
                LLMQuotaHistoryRangeToggle(selection: $range)
            }

            if sessionTimelineSessions.isEmpty {
                Text("No local sessions in this window")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                LLMSessionTimelineView(sessions: sessionTimelineSessions, range: range, showsHeader: false)
            }
        }
        .sectionStyle()
    }
}

enum LLMQuotaHistoryRange: String, CaseIterable, Identifiable {
    case sixHours = "6H"
    case day = "24H"

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .sixHours:
            return 6 * 60 * 60
        case .day:
            return 24 * 60 * 60
        }
    }
}

struct LLMQuotaHistoryRangeToggle: View {
    @Binding var selection: LLMQuotaHistoryRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LLMQuotaHistoryRange.allCases) { range in
                Button {
                    selection = range
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(selection == range ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selection == range ? Color.panelLift : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.background.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help("Show local drawdown over \(selection.rawValue)")
    }
}

enum LLMQuotaDrawdownMode: String, CaseIterable, Identifiable {
    case last = "Last"
    case current = "Current"

    var id: String { rawValue }
}

struct LLMQuotaDrawdownModeToggle: View {
    @Binding var selection: LLMQuotaDrawdownMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LLMQuotaDrawdownMode.allCases) { mode in
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
        .help("Show \(selection.rawValue.lowercased()) drawdown milestones")
    }
}

struct LLMQuotaHistoryGraph: View {
    let samples: [LLMQuotaHistorySample]
    let range: LLMQuotaHistoryRange

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
                    latestBadge(for: \.primaryRemainingPercent, color: .accentBlue, in: chartRect)

                    sampleDots(for: \.primaryRemainingPercent, color: .accentBlue, label: "5H", in: chartRect)
                }
            }
            .frame(height: 44)
        }
    }

    private func latestValue(_ keyPath: KeyPath<LLMQuotaHistorySample, Int?>) -> String {
        guard let remaining = samples.last?[keyPath: keyPath] else { return "-" }
        return "\(remaining)%"
    }

    private func latestBadge(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, color: Color, in rect: CGRect) -> some View {
        Group {
            if let remaining = samples.last?[keyPath: keyPath] {
                Text("\(remaining)%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .position(x: rect.maxX + 19, y: yPosition(for: remaining, in: rect))
            }
        }
    }

    private func sampleDots(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, color: Color, label: String, in rect: CGRect) -> some View {
        ForEach(thinnedPlotPoints(for: keyPath, label: label)) { point in
            LLMQuotaSampleDot(point: point, color: color)
                .position(pointPosition(for: point, in: rect))
        }
    }

    private func thinnedPlotPoints(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, label: String) -> [LLMQuotaPlotPoint] {
        let values = samples.compactMap { sample -> (Date, Int)? in
            guard let remaining = sample[keyPath: keyPath] else { return nil }
            return (sample.sampledAt, remaining)
        }
        guard values.count > 2 else {
            return values.map { LLMQuotaPlotPoint(series: label, sampledAt: $0.0, remainingPercent: $0.1) }
        }

        var points: [LLMQuotaPlotPoint] = []
        var previousKeptPointAt: Date?

        for index in values.indices {
            let value = values[index]
            let previous = index > 0 ? values[index - 1].1 : nil
            let next = index < values.count - 1 ? values[index + 1].1 : nil
            let isEndpoint = index == values.startIndex || index == values.index(before: values.endIndex)
            let isChangePoint = value.1 != previous || value.1 != next
            let shouldKeepFlatPoint = previousKeptPointAt.map { value.0.timeIntervalSince($0) >= 3_600 } ?? true

            guard isEndpoint || isChangePoint || shouldKeepFlatPoint else {
                continue
            }

            points.append(LLMQuotaPlotPoint(series: label, sampledAt: value.0, remainingPercent: value.1))
            previousKeptPointAt = value.0
        }

        return points
    }

    private func linePath(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, in rect: CGRect) -> Path {
        let values = samples.compactMap { sample -> (Date, Int)? in
            guard let remaining = sample[keyPath: keyPath] else { return nil }
            return (sample.sampledAt, remaining)
        }
        guard !values.isEmpty else { return Path() }

        let bounds = dateBounds()
        let duration = max(bounds.end.timeIntervalSince(bounds.start), 1)

        return Path { path in
            if values.count == 1, let value = values.first?.1 {
                let y = yPosition(for: value, in: rect)
                let x = xPosition(for: values[0].0, start: bounds.start, duration: duration, in: rect)
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y))
                return
            }

            for (index, value) in values.enumerated() {
                let x = xPosition(for: value.0, start: bounds.start, duration: duration, in: rect)
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

    private func pointPosition(for point: LLMQuotaPlotPoint, in rect: CGRect) -> CGPoint {
        let bounds = dateBounds()
        let duration = max(bounds.end.timeIntervalSince(bounds.start), 1)
        let x = xPosition(for: point.sampledAt, start: bounds.start, duration: duration, in: rect)
        let y = yPosition(for: point.remainingPercent, in: rect)
        return CGPoint(x: x, y: y)
    }

    private func dateBounds() -> (start: Date, end: Date) {
        let sampleDates = samples
            .compactMap { sample in
                sample.primaryRemainingPercent == nil ? nil : sample.sampledAt
            }
            .sorted()
        let end = Date()
        let fullStart = end.addingTimeInterval(-range.interval)
        guard let firstSample = sampleDates.first,
              let lastSample = sampleDates.last else {
            return (fullStart, end)
        }

        let sampleSpan = max(lastSample.timeIntervalSince(firstSample), 60)
        guard sampleSpan < range.interval * 0.5 else {
            return (fullStart, end)
        }

        let padding = max(sampleSpan * 0.18, min(15 * 60, range.interval * 0.08))
        let start = max(firstSample.addingTimeInterval(-padding), fullStart)
        let paddedEnd = min(lastSample.addingTimeInterval(padding), end)
        return (start, max(paddedEnd, start.addingTimeInterval(5 * 60)))
    }

    private func xPosition(for date: Date, start: Date, duration: TimeInterval, in rect: CGRect) -> CGFloat {
        let progress = min(max(date.timeIntervalSince(start) / duration, 0), 1)
        return rect.minX + CGFloat(progress) * rect.width
    }
}

struct LLMQuotaDrawdownInsight: Identifiable {
    var id: String { "\(startedAt.timeIntervalSince1970)-\(endedAt.timeIntervalSince1970)" }
    let startPercent: Int
    let endPercent: Int
    let durationText: String
    let subtitle: String
    let planLabel: String
    let startedAt: Date
    let endedAt: Date
    let milestones: [LLMQuotaMilestone]
}

struct LLMQuotaMilestone: Identifiable {
    var id: String { "\(label)-\(sampledAt.timeIntervalSince1970)-\(remainingPercent)" }
    let label: String
    let sampledAt: Date
    let remainingPercent: Int
}

struct LLMQuotaDrawdownInsightView: View {
    let insight: LLMQuotaDrawdownInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(insight.startPercent)% → \(insight.endPercent)% in")
                        .foregroundStyle(.white.opacity(0.86))
                    Text(insight.durationText)
                        .foregroundStyle(Color.accentBlue)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                Spacer(minLength: 6)
                Text(insight.planLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Text(insight.subtitle)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)

            VStack(spacing: 2) {
                ForEach(insight.milestones) { milestone in
                    HStack(spacing: 7) {
                        Text(milestone.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.accentBlue.opacity(0.9))
                            .frame(width: 42, alignment: .leading)
                        Text(quotaMilestoneTime(milestone.sampledAt))
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                            .monospacedDigit()
                        Spacer(minLength: 6)
                        Text("\(milestone.remainingPercent)%")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.top, 1)
    }
}

struct LLMQuotaPlotPoint: Identifiable {
    var id: String { "\(series)-\(sampledAt.timeIntervalSince1970)-\(remainingPercent)" }
    let series: String
    let sampledAt: Date
    let remainingPercent: Int
}

struct LLMQuotaSampleDot: View {
    let point: LLMQuotaPlotPoint
    let color: Color
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if isHovered {
                Text("\(point.remainingPercent)% • \(quotaPointTime(point.sampledAt))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.background.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(y: -17)
                    .zIndex(1)
            }

            Circle()
                .fill(color)
                .overlay(Circle().stroke(Color.background, lineWidth: 1))
                .frame(width: 6, height: 6)
        }
        .frame(width: 128, height: 28)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help("\(point.remainingPercent)% left at \(quotaPointTime(point.sampledAt))")
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

struct LLMSessionTimelineView: View {
    let sessions: [LLMUsageSession]
    let range: LLMQuotaHistoryRange
    var showsHeader = true
    @State private var hoveredSession: LLMUsageSession?
    @State private var pinnedSession: LLMUsageSession?

    private let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline) {
                    InstantHelpTitle(
                        "SESSION TIMELINE",
                        help: sessionTimelineHelp,
                        font: .system(size: 11.5, weight: .semibold)
                    )
                    Spacer()
                    Text("\(sessions.count) sessions")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                        .monospacedDigit()
                }
            }

            GeometryReader { proxy in
                let axis = axisBounds()
                let labelWidth = min(max(proxy.size.width * 0.38, 92), 168)
                let plotX = labelWidth + 8
                let plotWidth = max(proxy.size.width - plotX - 2, 1)
                let maxTokens = max(sessions.map(displayTokens).max() ?? 1, 1)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.background.opacity(0.38))
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    ForEach(tickFractions(for: proxy.size.width), id: \.self) { fraction in
                        let x = plotX + plotWidth * fraction
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height - 13))
                        }
                        .stroke(Color.white.opacity(fraction == 0 || fraction == 1 ? 0.12 : 0.07), lineWidth: 1)

                        Text(tickLabel(fraction: fraction, axis: axis))
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.42))
                            .monospacedDigit()
                            .position(x: x, y: proxy.size.height - 6)
                    }

                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        let y = CGFloat(index) * rowHeight + 17
                        let span = sessionSpan(session, axis: axis)
                        let startX = plotX + plotWidth * span.start
                        let endX = plotX + plotWidth * span.end
                        let width = max(endX - startX, 6)
                        let thickness = barThickness(for: displayTokens(session), maxTokens: maxTokens)

                        if index % 2 == 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.025))
                                .frame(width: proxy.size.width, height: rowHeight)
                                .position(x: proxy.size.width / 2, y: y)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(sessionDisplayTitle(session))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(1)
                            Text(sessionTimelineMeta(session))
                                .font(.system(size: 8.5, weight: .regular))
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                        .frame(width: labelWidth, alignment: .leading)
                        .contentShape(Rectangle())
                        .position(x: labelWidth / 2, y: y)
                        .onHover { isHovered in
                            hoveredSession = isHovered ? session : (hoveredSession?.id == session.id ? nil : hoveredSession)
                        }
                        .onTapGesture {
                            pinnedSession = session
                        }

                        Capsule()
                            .fill(timelineColor(for: session).opacity(isDetailSession(session) ? 1 : 0.9))
                            .frame(width: width, height: thickness)
                            .contentShape(Rectangle())
                            .position(x: startX + width / 2, y: y)
                            .onHover { isHovered in
                                hoveredSession = isHovered ? session : (hoveredSession?.id == session.id ? nil : hoveredSession)
                            }
                            .onTapGesture {
                                pinnedSession = session
                            }

                        if span.clippedStart {
                            Text("←")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(timelineColor(for: session))
                                .position(x: plotX - 5, y: y)
                        }

                        if span.clippedEnd {
                            Text("→")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(timelineColor(for: session))
                                .position(x: plotX + plotWidth + 5, y: y)
                            }
                    }

                }
            }
            .frame(height: CGFloat(sessions.count) * rowHeight + 18)

            HStack(spacing: 10) {
                timelineLegend(color: .accentBlue, label: "gpt-5.5")
                timelineLegend(color: timelineReviewColor, label: "review")
            }

            if let session = detailSession {
                LLMSessionCompactDetailCard(
                    session: session,
                    displayTitle: sessionDisplayTitle(session),
                    displayTokens: displayTokens(session),
                    promptPreview: sessionPromptPreview(session)
                )
                .id(session.id)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.background.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(.top, 2)
    }

    private func timelineLegend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
        }
    }

    private var timelineReviewColor: Color {
        Color(red: 191 / 255, green: 90 / 255, blue: 242 / 255)
    }

    private func axisBounds() -> (start: Date, end: Date) {
        let end = Date()
        return (end.addingTimeInterval(-range.interval), end)
    }

    private func tickFractions(for width: CGFloat) -> [CGFloat] {
        width > 380 ? [0, 0.25, 0.5, 0.75, 1] : [0, 0.5, 1]
    }

    private func tickLabel(fraction: CGFloat, axis: (start: Date, end: Date)) -> String {
        let interval = axis.end.timeIntervalSince(axis.start)
        return exactClockTime(axis.start.addingTimeInterval(interval * TimeInterval(fraction)))
    }

    private func sessionSpan(_ session: LLMUsageSession, axis: (start: Date, end: Date)) -> (start: CGFloat, end: CGFloat, clippedStart: Bool, clippedEnd: Bool) {
        let rawEnd = session.updatedAt ?? session.createdAt ?? axis.end
        let rawStart = session.createdAt ?? rawEnd.addingTimeInterval(-min(range.interval, 3_600))
        let duration = max(axis.end.timeIntervalSince(axis.start), 1)
        let clippedStart = rawStart < axis.start
        let clippedEnd = rawEnd > axis.end
        let start = min(max(rawStart.timeIntervalSince(axis.start) / duration, 0), 1)
        let end = min(max(rawEnd.timeIntervalSince(axis.start) / duration, 0), 1)
        return (CGFloat(start), CGFloat(max(end, start)), clippedStart, clippedEnd)
    }

    private func displayTokens(_ session: LLMUsageSession) -> UInt64 {
        guard let totalTokens = session.tokenUsage?.totalTokens, totalTokens > 0 else {
            return session.tokens
        }
        return totalTokens
    }

    private func barThickness(for tokens: UInt64, maxTokens: UInt64) -> CGFloat {
        4 + 12 * CGFloat(sqrt(Double(tokens) / Double(maxTokens)))
    }

    private func timelineColor(for session: LLMUsageSession) -> Color {
        session.modelName.lowercased().contains("auto")
            ? timelineReviewColor
            : .accentBlue
    }

    private func sessionTimelineMeta(_ session: LLMUsageSession) -> String {
        var parts = [tokenCount(displayTokens(session))]
        if let turns = session.tokenUsage?.turnCount, turns > 0 {
            parts.append("\(turns)t")
        }
        if let usage = session.tokenUsage, usage.inputTokens > 0 {
            parts.append("\(usage.cacheHitPercent)%")
        }
        return parts.joined(separator: " • ")
    }

    private var detailSession: LLMUsageSession? {
        if let hoveredSession,
           sessions.contains(where: { $0.id == hoveredSession.id }) {
            return hoveredSession
        }
        if let pinnedSession,
           sessions.contains(where: { $0.id == pinnedSession.id }) {
            return pinnedSession
        }
        return nil
    }

    private func isDetailSession(_ session: LLMUsageSession) -> Bool {
        detailSession?.id == session.id
    }

    private func sessionDisplayTitle(_ session: LLMUsageSession) -> String {
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.localizedCaseInsensitiveContains("Codex agent history")
            || title.localizedCaseInsensitiveContains("approval request") {
            return "Approval review"
        }
        return title.isEmpty ? "Untitled session" : title
    }

    private func sessionPromptPreview(_ session: LLMUsageSession) -> String? {
        let preview = session.preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty,
              preview != "No prompt preview stored" else {
            return nil
        }

        let lowercased = preview.lowercased()
        if lowercased.contains("codex agent history")
            || lowercased.contains("approval request")
            || lowercased.contains("transcript start")
            || lowercased.contains("planned action json") {
            return nil
        }

        return trimmedText(preview, maxLength: 180)
    }
}

struct LLMSessionHoverCard: View {
    let session: LLMUsageSession
    let displayTitle: String
    let displayTokens: UInt64
    let promptPreview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(session.projectName) • \(session.modelName)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                hoverMetric("Tokens", tokenCount(displayTokens))
                if let turns = session.tokenUsage?.turnCount, turns > 0 {
                    hoverMetric("Turns", "\(turns)")
                }
                if let usage = session.tokenUsage, usage.inputTokens > 0 {
                    hoverMetric("Cache", "\(usage.cacheHitPercent)%")
                }
            }

            if let usage = session.tokenUsage {
                VStack(alignment: .leading, spacing: 3) {
                    hoverLine("Input", tokenCount(usage.inputTokens))
                    hoverLine("Cached", tokenCount(usage.cachedInputTokens))
                    hoverLine("Output", tokenCount(usage.outputTokens))
                    if usage.reasoningOutputTokens > 0 {
                        hoverLine("Reasoning", tokenCount(usage.reasoningOutputTokens))
                    }
                    hoverLine("Cost est.", dollarEstimate(usage.estimatedCost(for: session.modelName)))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let createdAt = session.createdAt {
                    hoverLine("Started", absoluteTime(createdAt))
                }
                if let updatedAt = session.updatedAt {
                    hoverLine("Updated", absoluteTime(updatedAt))
                }
            }

            if let promptPreview {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prompt")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(promptPreview)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(3)
                }
            }

            if !session.rolloutPath.isEmpty {
                hoverLine("Trace", URL(fileURLWithPath: session.rolloutPath).lastPathComponent)
            }
        }
        .padding(10)
        .background(Color.background.opacity(0.98))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 5)
    }

    private func hoverMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func hoverLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.46))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

struct LLMSessionCompactDetailCard: View {
    let session: LLMUsageSession
    let displayTitle: String
    let displayTokens: UInt64
    let promptPreview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(session.modelName)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }

            HStack(spacing: 9) {
                compactMetric(tokenCount(displayTokens))
                if let turns = session.tokenUsage?.turnCount, turns > 0 {
                    compactMetric("\(turns)t")
                }
                if let usage = session.tokenUsage, usage.inputTokens > 0 {
                    compactMetric("\(usage.cacheHitPercent)% cache")
                }
                if let updatedAt = session.updatedAt {
                    compactMetric(relativeTime(updatedAt))
                }
            }

            if let promptPreview {
                Text(promptPreview)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private func compactMetric(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.52))
            .monospacedDigit()
            .lineLimit(1)
    }
}

struct LLMAdvancedUsageCard: View {
    let snapshot: LLMUsageSnapshot
    @Binding var isExpanded: Bool
    @State private var sessionMode = LLMTokenUserMode.recent
    @State private var detailExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    InstantHelpTitle("TOP TOKEN USERS", help: topTokenUsersHelp)
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

                DisclosureGroup(isExpanded: $detailExpanded) {
                    LLMAvailableDetailView(snapshot: snapshot)
                        .padding(.top, 4)
                } label: {
                    HStack {
                        InstantHelpTitle(
                            "AVAILABLE DETAIL",
                            help: availableDetailHelp,
                            font: .system(size: 11.5, weight: .semibold),
                            color: .white.opacity(0.62)
                        )
                        Spacer()
                        Text("\(snapshot.limits.count) limit groups")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .monospacedDigit()
                    }
                }
                .accentColor(.accentBlue)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                InstantHelpTitle("ADVANCED", help: advancedHelp)
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
        let sessions: [LLMUsageSession]
        switch sessionMode {
        case .recent:
            sessions = snapshot.recentSessions
        case .highest:
            sessions = snapshot.topWeeklySessions
        }
        return Array(sessions.prefix(5))
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
                Text(tokenCount(displayTokens))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            HStack {
                Text(session.detail)
                    .lineLimit(1)
                Spacer()
                if let cacheLabel {
                    Text(cacheLabel)
                        .foregroundStyle(Color.compressedYellow.opacity(0.78))
                        .monospacedDigit()
                }
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
                    if let tokenUsage = session.tokenUsage {
                        LLMSessionTokenUsageView(usage: tokenUsage, modelName: session.modelName)
                    }
                    LLMSessionDetailRow(label: "Updated", value: session.updatedAt.map { absoluteTime($0) } ?? "-")
                    LLMSessionDetailRow(label: "Session", value: session.id)
                    HStack(spacing: 12) {
                        Button {
                            openSessionContext()
                        } label: {
                            Label("Open Context", systemImage: "doc.text")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentBlue)
                        }
                        .buttonStyle(.plain)

                        Button {
                            openSessionFolder()
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentBlue)
                        }
                        .buttonStyle(.plain)
                    }
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

    private var displayTokens: UInt64 {
        guard let totalTokens = session.tokenUsage?.totalTokens, totalTokens > 0 else {
            return session.tokens
        }
        return totalTokens
    }

    private var cacheLabel: String? {
        guard let usage = session.tokenUsage, usage.inputTokens > 0 else { return nil }
        return "\(usage.cacheHitPercent)% cached"
    }

    private func openSessionContext() {
        let path = session.rolloutPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        let fileURL = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(fileURL)
    }

    private func openSessionFolder() {
        let path = session.rolloutPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        let fileURL = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
    }
}

struct LLMSessionTokenUsageView: View {
    let usage: LLMTokenUsageSummary
    let modelName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LLMSessionMetricRow(label: "API est.", value: dollarEstimate(usage.estimatedCost(for: modelName)))
            LLMSessionMetricRow(label: "Est. rate", value: usage.pricingLabel(for: modelName))
            LLMSessionMetricRow(label: "Cache hit", value: "\(usage.cacheHitPercent)% of input")
            LLMSessionMetricRow(label: "Cached input", value: tokenCount(usage.cachedInputTokens))
            LLMSessionMetricRow(label: "Fresh input", value: tokenCount(usage.nonCachedInputTokens))
            LLMSessionMetricRow(label: "Output", value: tokenCount(usage.outputTokens))
            if usage.reasoningOutputTokens > 0 {
                LLMSessionMetricRow(label: "Reasoning", value: tokenCount(usage.reasoningOutputTokens))
            }
            LLMSessionMetricRow(label: "Total", value: tokenCount(usage.totalTokens))
            if usage.turnCount > 0 {
                LLMSessionMetricRow(label: "Turns", value: "\(usage.turnCount)")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.background.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct LLMSessionMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .monospacedDigit()
        }
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

struct MemoryRunwayHeroView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(spacing: 10) {
            MemoryRunwayLane(
                title: "PRESSURE",
                value: "\(snapshot.pressurePercent)%",
                detail: pressureDetail,
                percent: snapshot.pressurePercent,
                color: .accentBlue,
                markers: [50, 80]
            )

            MemoryRunwayLane(
                title: "MEMORY",
                value: "\(snapshot.usedPercent)%",
                detail: "\(ByteFormat.memory(snapshot.breakdown.app + snapshot.breakdown.wired + snapshot.breakdown.compressed)) used",
                percent: snapshot.usedPercent,
                color: .accentBlue,
                markers: [75, 90],
                segments: memorySegments
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var pressureDetail: String {
        switch snapshot.pressurePercent {
        case 0..<35:
            return "Low load"
        case 35..<70:
            return "Active load"
        default:
            return "High load"
        }
    }

    private var memorySegments: [MemoryRunwaySegment] {
        let breakdown = snapshot.breakdown
        let total = max(Double(breakdown.total), 1)
        return [
            MemoryRunwaySegment(label: "App", value: Double(breakdown.app) / total, color: .accentBlue),
            MemoryRunwaySegment(label: "Wired", value: Double(breakdown.wired) / total, color: .wiredPink),
            MemoryRunwaySegment(label: "Compressed", value: Double(breakdown.compressed) / total, color: .compressedYellow),
            MemoryRunwaySegment(label: "Free", value: Double(breakdown.free) / total, color: .freeGray)
        ]
    }
}

struct MemoryRunwaySegment: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

struct MemoryRunwayLane: View {
    let title: String
    let value: String
    let detail: String
    let percent: Int
    let color: Color
    var markers: [Int] = []
    var segments: [MemoryRunwaySegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(value)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .frame(width: 74, alignment: .leading)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 6)
                Text(detail)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(color.opacity(0.9))
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.freeGray.opacity(0.22))

                    if segments.isEmpty {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(color.opacity(0.9))
                            .frame(width: proxy.size.width * clampedRatio)
                    } else {
                        segmentedTrack(width: proxy.size.width)
                    }

                    ForEach(markers, id: \.self) { marker in
                        let x = proxy.size.width * CGFloat(marker) / 100
                        Rectangle()
                            .fill(Color.background.opacity(0.58))
                            .frame(width: 1, height: 12)
                            .position(x: x, y: 6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 12)

            if !segments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(segments.prefix(3)) { segment in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 5, height: 5)
                            Text(segment.label)
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                    }
                }
            }
        }
    }

    private var clampedRatio: CGFloat {
        CGFloat(min(max(Double(percent) / 100, 0), 1))
    }

    private func segmentedTrack(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                Rectangle()
                    .fill(segment.color.opacity(segment.label == "Free" ? 0.48 : 0.88))
                    .frame(width: max(width * CGFloat(max(segment.value, 0)), 0))
            }
        }
        .frame(width: width, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.86))
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
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.86))
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
                    .font(.system(size: 12, weight: .medium))
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
    var onOpenHub: (() -> Void)?
    var onStartDeepTrace: (() -> Void)?
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            VersionIndicatorView()

            Spacer()

            if let onOpenHub {
                IconActionButton(systemName: "rectangle.3.group", help: "Open MaxxBar Hub", action: onOpenHub)
            }

            if let onStartDeepTrace {
                IconActionButton(systemName: "record.circle", help: "Start Deep Trace", action: onStartDeepTrace)
            }

            if let onPopOut {
                IconActionButton(systemName: "rectangle.on.rectangle", help: "Open as window", action: onPopOut)
            }

            IconActionButton(systemName: "arrow.clockwise", help: "Relaunch app", action: relaunchCurrentApp)

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

struct VersionIndicatorView: View {
    private var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let components = version.split(separator: ".")
        let compact = components.prefix(2).joined(separator: ".")
        return "v\(compact.isEmpty ? version : compact)"
    }

    private var fullLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.flatMap { $0.isEmpty ? nil : "MaxxBar v\(version) · \($0)" } ?? "MaxxBar v\(version)"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.44))
            .monospacedDigit()
            .lineLimit(1)
            .help(fullLabel)
    }
}

@MainActor
private func relaunchCurrentApp() {
    let bundleURL = Bundle.main.bundleURL
    guard bundleURL.pathExtension == "app" else {
        NSApp.terminate(nil)
        return
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-n", bundleURL.path]
    try? task.run()
    NSApp.terminate(nil)
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
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.86))
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
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.86))
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

private func dollarEstimate(_ value: Double) -> String {
    if value >= 100 {
        return String(format: "$%.0f", value)
    }
    if value >= 10 {
        return String(format: "$%.1f", value)
    }
    return String(format: "$%.2f", value)
}

private func windowRange(_ start: Date, _ end: Date) -> String {
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

private struct LLMQuotaValue {
    let sampledAt: Date
    let remainingPercent: Int
    let planType: String?
}

private func quotaDrawdownInsight(from samples: [LLMQuotaHistorySample], mode: LLMQuotaDrawdownMode) -> LLMQuotaDrawdownInsight? {
    let values = samples
        .compactMap { sample -> LLMQuotaValue? in
            guard let remaining = sample.primaryRemainingPercent else { return nil }
            return LLMQuotaValue(
                sampledAt: sample.sampledAt,
                remainingPercent: remaining,
                planType: sample.planType
            )
        }
        .sorted { $0.sampledAt < $1.sampledAt }

    guard values.count >= 2 else { return nil }

    let resetIndices = values.indices.dropFirst().filter { index in
        values[index].remainingPercent - values[index - 1].remainingPercent >= 50
            && values[index].remainingPercent >= 80
    }

    var resetAfterIndex: Int?
    let segmentStart: Int
    let segmentEnd: Int
    let subtitle: String

    switch mode {
    case .last:
        if let lastReset = resetIndices.last,
           values.indices.contains(lastReset - 1),
           values[lastReset - 1].remainingPercent <= 20 {
            resetAfterIndex = lastReset
            segmentEnd = lastReset - 1
            segmentStart = resetIndices.last(where: { $0 < segmentEnd }) ?? 0
            subtitle = "Last exhausted run before the current reset; crossings may fall between samples."
        } else {
            segmentEnd = values.count - 1
            segmentStart = resetIndices.last(where: { $0 < segmentEnd }) ?? 0
            subtitle = "Latest sampled drawdown; crossings may fall between samples."
        }
    case .current:
        segmentEnd = values.count - 1
        segmentStart = resetIndices.last ?? 0
        subtitle = "Current sampled drawdown; crossings may fall between samples."
    }

    guard segmentEnd > 0 else { return nil }

    let dropIndex = firstDropIndex(in: values, start: segmentStart, end: segmentEnd)
    let fullIndex = dropIndex.map { max(segmentStart, $0 - 1) }
        ?? (segmentStart...segmentEnd).last(where: { values[$0].remainingPercent >= 95 })
        ?? segmentStart

    guard fullIndex <= segmentEnd else { return nil }

    let lowIndex: Int
    switch mode {
    case .last:
        lowIndex = firstThresholdCrossing(in: values, threshold: 5, start: fullIndex, end: segmentEnd)
            ?? (fullIndex...segmentEnd).min { values[$0].remainingPercent < values[$1].remainingPercent }
            ?? segmentEnd
    case .current:
        lowIndex = segmentEnd
    }

    var milestones: [LLMQuotaMilestone] = [
        LLMQuotaMilestone(
            label: "\(values[fullIndex].remainingPercent)%",
            sampledAt: values[fullIndex].sampledAt,
            remainingPercent: values[fullIndex].remainingPercent
        )
    ]

    for threshold in stride(from: 80, through: 0, by: -20) where threshold < values[fullIndex].remainingPercent {
        if let index = firstThresholdCrossing(in: values, threshold: threshold, start: fullIndex, end: segmentEnd) {
            appendDrawdownMilestone(
                LLMQuotaMilestone(
                    label: "≤\(threshold)",
                    sampledAt: values[index].sampledAt,
                    remainingPercent: values[index].remainingPercent
                ),
                to: &milestones
            )
        }
    }

    let latestValue = values[lowIndex]
    if !latestValue.remainingPercent.isMultiple(of: 20),
       !milestones.contains(where: { $0.sampledAt == latestValue.sampledAt && $0.remainingPercent == latestValue.remainingPercent }) {
        milestones.append(
            LLMQuotaMilestone(
                label: "\(latestValue.remainingPercent)%",
                sampledAt: latestValue.sampledAt,
                remainingPercent: latestValue.remainingPercent
            )
        )
    }

    if let resetAfterIndex {
        milestones.append(
            LLMQuotaMilestone(
                label: "Reset",
                sampledAt: values[resetAfterIndex].sampledAt,
                remainingPercent: values[resetAfterIndex].remainingPercent
            )
        )
    }

    let duration = values[lowIndex].sampledAt.timeIntervalSince(values[fullIndex].sampledAt)

    return LLMQuotaDrawdownInsight(
        startPercent: values[fullIndex].remainingPercent,
        endPercent: values[lowIndex].remainingPercent,
        durationText: durationLabel(duration),
        subtitle: subtitle,
        planLabel: planLabel(from: values, start: fullIndex, end: lowIndex),
        startedAt: values[fullIndex].sampledAt,
        endedAt: values[lowIndex].sampledAt,
        milestones: deduplicatedMilestones(milestones)
    )
}

private func appendDrawdownMilestone(_ milestone: LLMQuotaMilestone, to milestones: inout [LLMQuotaMilestone]) {
    if let last = milestones.last,
       last.sampledAt == milestone.sampledAt,
       last.remainingPercent == milestone.remainingPercent {
        milestones[milestones.count - 1] = milestone
        return
    }

    milestones.append(milestone)
}

private func firstDropIndex(in values: [LLMQuotaValue], start: Int, end: Int) -> Int? {
    guard start < end else { return nil }
    for index in (start + 1)...end where values[index].remainingPercent < values[index - 1].remainingPercent {
        return index
    }
    return nil
}

private func firstThresholdCrossing(in values: [LLMQuotaValue], threshold: Int, start: Int, end: Int) -> Int? {
    guard start < end else { return nil }
    for index in (start + 1)...end
        where values[index - 1].remainingPercent > threshold
            && values[index].remainingPercent <= threshold {
        return index
    }
    return nil
}

private func deduplicatedMilestones(_ milestones: [LLMQuotaMilestone]) -> [LLMQuotaMilestone] {
    var seen = Set<String>()
    return milestones.filter { milestone in
        let key = "\(milestone.label)-\(Int(milestone.sampledAt.timeIntervalSince1970))-\(milestone.remainingPercent)"
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }
}

private func planLabel(from values: [LLMQuotaValue], start: Int, end: Int) -> String {
    let plans = values[start...end].compactMap(\.planType)
    let uniquePlans = Array(Set(plans)).sorted()
    guard !uniquePlans.isEmpty else { return "Plan not logged" }
    return uniquePlans.map { planName($0) }.joined(separator: " / ")
}

private func durationLabel(_ interval: TimeInterval) -> String {
    let minutes = max(Int((interval / 60).rounded()), 0)
    if minutes < 60 {
        return "\(minutes)m"
    }

    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
}

private func aiDuration(_ interval: TimeInterval) -> String {
    let minutes = max(Int((interval / 60).rounded()), 0)
    if minutes >= 60 {
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    return "\(minutes)m"
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

private func resetCreditExpirationLine(_ expiration: LLMResetCreditExpiration) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short
    let relativeFormatter = RelativeDateTimeFormatter()
    relativeFormatter.unitsStyle = .full
    let date = dateFormatter.string(from: expiration.expiresAt)
    let relative = relativeFormatter.localizedString(for: expiration.expiresAt, relativeTo: Date())
    let creditLabel = expiration.count == 1 ? "credit" : "credits"
    return "\(expiration.count) \(creditLabel) expire \(date) (\(relative))"
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

private func quotaPointTime(_ value: Date) -> String {
    exactClockTime(value)
}

private func quotaMilestoneTime(_ value: Date) -> String {
    exactClockTime(value)
}

private func exactClockTime(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: value)
        .replacingOccurrences(of: "AM", with: "a.m.")
        .replacingOccurrences(of: "PM", with: "p.m.")
}

private func localDrawdownUpdatedAt(_ value: Date?) -> String {
    guard let value else { return "not sampled" }
    return exactClockTime(value)
}

private func trimmedText(_ text: String, maxLength: Int) -> String {
    guard text.count > maxLength else { return text }
    let end = text.index(text.startIndex, offsetBy: maxLength - 1)
    return String(text[..<end]) + "..."
}

private let codexRunwayHelp = """
Shows your live Codex quota windows from the usage API. The 5h bar is the short runway you feel during heavy work; the weekly bar shows the longer reset cycle, and reset credits appear when the API reports them.
"""

private let limitDrawdownHelp = """
Shows how your Codex 5H limit has been draining based on samples MaxxBar stores locally. If the selected window has only a small amount of history, MaxxBar zooms to the samples it has so the chart is not mostly empty space.
"""

private let sessionTimelineHelp = """
Shows recent local Codex sessions in the selected drawdown window, newest first. Bar position is the session time range, thickness roughly follows token volume, and the tooltip gives the full session detail.
"""

private let drawdownInsightHelp = """
Summarizes the latest sampled runway drop from the local quota history. It is useful for seeing how quickly the 5H window moved, but exact crossing times are bounded by how often MaxxBar sampled the API.
"""

private let maxxInsightsHelp = """
Summarizes local AI activity MaxxBar has observed today: session count, inferred AI time, average session length, the current detected AI surface, and confidence in the context signal.
"""

private let contextConfidenceHelp = """
Context confidence is how much before/after app context MaxxBar has around detected AI use. High means it saw both sides of the workflow often enough to trust the pattern; Medium or Low means the context is sparse or mostly inferred.
"""

private let aiFlowHelp = """
Shows lightweight before -> AI -> after patterns from local app and site metadata. It helps answer which tools you use, what usually leads into AI, and where work tends to go afterward.
"""

private let topTokenUsersHelp = """
Lists the local Codex sessions with the most token usage. Use this when runway drops faster than expected and you want to see which recent session likely drove the drawdown.
"""

private let availableDetailHelp = """
Shows raw limit groups returned by the Codex usage API. This is mostly diagnostic detail for checking additional model-specific limits beyond the main Codex runway.
"""

private let advancedHelp = """
Advanced keeps deeper local token/session diagnostics out of the main Runway view. Open it when you need session-level token users, cache estimates, or raw API limit detail.
"""

struct InstantHelpTitle: View {
    let title: String
    let help: String
    var font: Font = .system(size: 13.5, weight: .medium)
    var color: Color = .accentBlue
    @State private var isHovered = false

    init(
        _ title: String,
        help: String,
        font: Font = .system(size: 13.5, weight: .medium),
        color: Color = .accentBlue
    ) {
        self.title = title
        self.help = help
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(color)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .popover(isPresented: $isHovered, arrowEdge: .top) {
                Text(help)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 270, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.background)
            }
    }
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
