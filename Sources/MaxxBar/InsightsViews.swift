import AppKit
import SwiftUI

struct AIUsagePanelView: View {
    let aiUsage: AIUsageSnapshot
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    var onOpenAIReport: (() -> Void)?
    var onStartDeepTrace: (() -> Void)?
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var providerFilter = AIInsightProviderFilter.all

    var body: some View {
        VStack(spacing: 7) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    AIUsageOverviewCard(snapshot: filteredAIUsage, providerFilter: $providerFilter)
                    AIProviderAccountsCard(
                        aiUsage: aiUsage,
                        accounts: snapshot.providerAccounts,
                        providerFilter: providerFilter
                    )
                    LLMModelUsageCard(snapshot: filteredLLMSnapshot)
                    AITransferCard(snapshot: filteredAIUsage)
                    AIWorkflowMiniCard(snapshot: filteredAIUsage)
                    LLMSessionTimelineCard(snapshot: filteredLLMSnapshot)
                }
            }

        }
    }

    private var filteredAIUsage: AIUsageSnapshot {
        guard providerFilter != .all,
              let summary = aiUsage.providerSummaries.first(where: { $0.provider == providerFilter.rawValue }) else {
            return aiUsage
        }
        var filtered = aiUsage
        filtered.activeTool = providerFilter.rawValue
        filtered.sessionsToday = summary.sessionsToday
        filtered.sessionsSevenDays = summary.sessionsSevenDays
        filtered.timeTodaySeconds = summary.timeTodaySeconds
        filtered.timeSevenDaysSeconds = summary.timeSevenDaysSeconds
        filtered.averageSessionSeconds = summary.averageSessionSeconds
        filtered.contextConfidence = summary.contextConfidence
        filtered.topTools = summary.topTools
        filtered.topBeforeApps = summary.topBeforeApps
        filtered.topAfterApps = summary.topAfterApps
        filtered.workflowPaths = summary.workflowPaths
        filtered.copyEventsToday = summary.copyEventsToday
        filtered.pasteEventsToday = summary.pasteEventsToday
        filtered.topCopiedFrom = summary.topCopiedFrom
        filtered.topPastedInto = summary.topPastedInto
        filtered.transferFlows = summary.transferFlows
        return filtered
    }

    private var filteredLLMSnapshot: LLMUsageSnapshot {
        guard providerFilter != .all else { return snapshot }
        var filtered = snapshot
        filtered.recentSessions = snapshot.recentSessions.filter(providerFilter.matches)
        filtered.topWeeklySessions = snapshot.topWeeklySessions.filter(providerFilter.matches)
        filtered.weeklyModelUsage = snapshot.weeklyModelUsage.filter {
            $0.provider.caseInsensitiveCompare(providerFilter.rawValue) == .orderedSame
        }
        filtered.dailyModelUsage = snapshot.dailyModelUsage.filter {
            $0.provider.caseInsensitiveCompare(providerFilter.rawValue) == .orderedSame
        }
        return filtered
    }
}

struct AIProviderAccountsCard: View {
    let aiUsage: AIUsageSnapshot
    let accounts: [LLMProviderAccount]
    let providerFilter: AIInsightProviderFilter

    private var visibleAccounts: [LLMProviderAccount] {
        accounts.filter {
            providerFilter == .all
                || $0.provider.caseInsensitiveCompare(providerFilter.rawValue) == .orderedSame
        }
    }

    private var totalProviderTime: TimeInterval {
        aiUsage.providerSummaries.reduce(0) { $0 + $1.timeTodaySeconds }
    }

    private var totalProviderSessions: Int {
        aiUsage.providerSummaries.reduce(0) { $0 + $1.sessionsToday }
    }

    var body: some View {
        if !visibleAccounts.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                InstantHelpTitle(
                    "ACTIVE ACCOUNTS · TODAY",
                    help: "Codex account and plan come from its live usage response. Claude account, organization, and seat tier come from the local Claude profile. Activity share is based on foreground windows attributed to each provider today; provider windows can overlap."
                )

                ForEach(visibleAccounts) { account in
                    let usage = aiUsage.providerSummaries.first {
                        $0.provider.caseInsensitiveCompare(account.provider) == .orderedSame
                    }
                    accountRow(account, usage: usage)
                }
            }
            .sectionStyle()
        }
    }

    private func accountRow(
        _ account: LLMProviderAccount,
        usage: AIProviderUsageSummary?
    ) -> some View {
        let accountName = account.organizationName ?? account.displayName ?? account.provider
        let time = usage?.timeTodaySeconds ?? 0
        let sessions = usage?.sessionsToday ?? 0
        let timeShare = totalProviderTime > 0 ? Int((time / totalProviderTime * 100).rounded()) : 0
        let sessionShare = totalProviderSessions > 0
            ? Int((Double(sessions) / Double(totalProviderSessions) * 100).rounded())
            : 0

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(account.provider == "Claude" ? Color.claudeCoral : Color.codexBlue)
                    .frame(width: 6, height: 6)
                Text(accountName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                if accountName.caseInsensitiveCompare(account.provider) != .orderedSame {
                    Text("· \(account.provider)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 4)
                Text("\(timeShare)% time")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
                    .monospacedDigit()
            }

            HStack(spacing: 5) {
                Text(account.email ?? "Account unavailable")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("· \(planName(account.planName))")
                Spacer(minLength: 4)
                Text("\(sessions) session\(sessions == 1 ? "" : "s") · \(sessionShare)%")
                    .monospacedDigit()
            }
            .font(.system(size: 9.5, weight: .regular))
            .foregroundStyle(.white.opacity(0.46))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.background.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

enum AIInsightProviderFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case codex = "Codex"
    case claude = "Claude"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .all: return .white.opacity(0.68)
        case .codex: return .codexBlue
        case .claude: return .claudeCoral
        }
    }

    func matches(_ session: LLMUsageSession) -> Bool {
        switch self {
        case .all:
            return true
        case .codex:
            return session.provider.caseInsensitiveCompare("Codex") == .orderedSame
        case .claude:
            return session.provider.caseInsensitiveCompare("Claude") == .orderedSame
        }
    }
}

struct AIInsightProviderToggle: View {
    @Binding var selection: AIInsightProviderFilter

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AIInsightProviderFilter.allCases) { provider in
                Button {
                    selection = provider
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(provider.color)
                            .frame(width: 5, height: 5)
                        Text(provider.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == provider ? .white : .white.opacity(0.52))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(selection == provider ? provider.color.opacity(0.2) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(selection == provider ? provider.color.opacity(0.7) : Color.clear, lineWidth: 0.75)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(2)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

struct AIUsageOverviewCard: View {
    let snapshot: AIUsageSnapshot
    @Binding var providerFilter: AIInsightProviderFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                InstantHelpTitle("MAXX INSIGHTS", help: maxxInsightsHelp)
                Spacer()
                AIInsightProviderToggle(selection: $providerFilter)
                    .frame(width: 154)
            }

            HStack(spacing: 7) {
                aiMetric("Today", "\(snapshot.sessionsToday)", "windows")
                aiMetric("Foreground", aiDuration(snapshot.timeTodaySeconds), "today")
                aiMetric("Avg", aiDuration(snapshot.averageSessionSeconds), "window")
            }

            Text(providerFilter == .all
                 ? "Foreground AI windows · provider counts may overlap"
                 : "Foreground \(providerFilter.rawValue) activity · transcript totals below")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(.vertical, 5)
        .background(Color.background.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct LLMModelUsageCard: View {
    let snapshot: LLMUsageSnapshot
    @State private var selectedWindow = ModelMixWindow.day

    private var summary: LLMModelUsageSummary {
        snapshot.modelUsageSummary(lastSeconds: selectedWindow.seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InstantHelpTitle(
                    "MODEL MIX",
                    help: "Shows which models appear in locally discovered Codex and Claude activity. Claude totals are attributed per assistant response so model switches inside a session are counted correctly."
                )
                Spacer()
                HStack(spacing: 2) {
                    ForEach(ModelMixWindow.allCases) { window in
                        Button(window.rawValue) { selectedWindow = window }
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(selectedWindow == window ? .white : .white.opacity(0.48))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(selectedWindow == window ? Color.white.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.background.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            if summary.models.isEmpty {
                Text("No local model context found in the last \(selectedWindow.description).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(Array(summary.models.prefix(5))) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(providerColor(model.provider))
                                .frame(width: 6, height: 6)
                            Text(model.modelName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                                .help(model.modelName)
                            Spacer(minLength: 4)
                            Text(model.sharePercent == 0 && model.tokens > 0 ? "<1%" : "\(model.sharePercent)%")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .monospacedDigit()
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.background.opacity(0.55))
                                Capsule()
                                    .fill(providerColor(model.provider).opacity(0.82))
                                    .frame(width: max(model.sharePercent > 0 ? 2 : 0, proxy.size.width * CGFloat(model.sharePercent) / 100))
                            }
                        }
                        .frame(height: 4)

                        Text("\(model.provider) · \(model.sessionCount) session\(model.sessionCount == 1 ? "" : "s") · \(tokenCount(model.tokens)) tokens")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }

                if summary.models.count > 5 {
                    Text("+\(summary.models.count - 5) more models")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Text("\(summary.sessionCount) sessions · \(tokenCount(summary.totalTokens)) tokens · share by \(summary.distributionBasis)")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sectionStyle()
    }

    private func providerColor(_ provider: String) -> Color {
        provider.caseInsensitiveCompare("Claude") == .orderedSame ? .claudeCoral : .codexBlue
    }
}

private enum ModelMixWindow: String, CaseIterable, Identifiable {
    case day = "24H"
    case sevenDays = "7D"

    var id: String { rawValue }
    var seconds: TimeInterval { self == .day ? 86_400 : 604_800 }
    var description: String { self == .day ? "24 hours" : "seven days" }
}

struct AITransferCard: View {
    let snapshot: AIUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InstantHelpTitle(
                    "AI OUTPUT DESTINATIONS",
                    help: "Tracks Cmd+C and Cmd+V as context metadata. A flow requires a copy followed by a paste within 15 minutes. Claude-to-Claude and Codex-to-Codex pairs are excluded; Claude↔Codex and AI-to-other-app flows remain. Raw Copy and Paste totals still count observed shortcuts. Copied images may be stored locally for up to 24 hours; text clipboard contents are never stored."
                )
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
            .prefix(4)
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
