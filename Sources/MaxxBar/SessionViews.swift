import AppKit
import SwiftUI

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
                    hoverMetric("Rebuilds", "\(usage.rebuildCount)")
                    hoverMetric("Cache", "\(usage.cacheHitPercent)%")
                }
            }

            if let usage = session.tokenUsage {
                let cost = usage.costBreakdown(for: session.modelName)
                VStack(alignment: .leading, spacing: 3) {
                    hoverLine("Fresh input", "\(tokenCount(usage.freshInputTokens)) • \(dollarEstimate(cost.freshInput))")
                    if usage.cacheWriteInputTokens > 0 {
                        hoverLine("Cache write", "\(tokenCount(usage.cacheWriteInputTokens)) • \(dollarEstimate(cost.cacheWrite))")
                    }
                    hoverLine("Cache read", "\(tokenCount(usage.cachedInputTokens)) • \(dollarEstimate(cost.cacheRead))")
                    hoverLine("Output", "\(tokenCount(usage.outputTokens)) • \(dollarEstimate(cost.output))")
                    if usage.reasoningOutputTokens > 0 {
                        hoverLine("Reasoning", tokenCount(usage.reasoningOutputTokens))
                    }
                    hoverLine("Cost est.", "\(dollarEstimate(cost.total)) lifetime")
                    if let recent = usage.last24h {
                        hoverLine("Last 24h", "\(dollarEstimate(recent.costBreakdown(for: session.modelName).total)) • \(tokenCount(recent.totalTokens))")
                    }
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
    @State private var providerFilter = LLMSessionProviderFilter.all
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

                LLMSessionProviderToggle(selection: $providerFilter)

                if selectedSessions.isEmpty {
                    Text("No \(providerFilter.emptyStateLabel) session token detail found")
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
        return Array(sessions.filter(providerFilter.matches).prefix(5))
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

enum LLMSessionProviderFilter: String, CaseIterable, Identifiable {
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

    var emptyStateLabel: String {
        self == .all ? "local" : rawValue
    }

    func matches(_ session: LLMUsageSession) -> Bool {
        self == .all || session.provider.caseInsensitiveCompare(rawValue) == .orderedSame
    }
}

struct LLMSessionProviderToggle: View {
    @Binding var selection: LLMSessionProviderFilter

    var body: some View {
        HStack(spacing: 3) {
            ForEach(LLMSessionProviderFilter.allCases) { provider in
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
        .background(Color.background.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                Text(session.provider)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(providerColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(providerColor.opacity(0.15))
                    .clipShape(Capsule())
                Text("\(session.projectName) • \(session.modelName)")
                    .foregroundStyle(.white.opacity(0.56))
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
        let rebuilds = usage.rebuildCount == 1 ? "1 rebuild" : "\(usage.rebuildCount) rebuilds"
        return "\(dollarEstimate(usage.estimatedCost(for: session.modelName))) • \(rebuilds)"
    }

    private var providerColor: Color {
        session.provider.caseInsensitiveCompare("Claude") == .orderedSame ? .claudeCoral : .codexBlue
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
        let cost = usage.costBreakdown(for: modelName)
        VStack(alignment: .leading, spacing: 3) {
            LLMSessionMetricRow(label: "API est.", value: "\(dollarEstimate(cost.total)) lifetime")
            if let recent = usage.last24h {
                LLMSessionMetricRow(label: "Last 24h", value: "\(dollarEstimate(recent.costBreakdown(for: modelName).total)) • \(tokenCount(recent.totalTokens)) • \(recent.callCount) calls • \(recent.rebuildCount) rebuilds")
            }
            LLMSessionMetricRow(label: "Est. rate", value: usage.pricingLabel(for: modelName))
            LLMSessionMetricRow(label: "Cache read", value: "\(tokenCount(usage.cachedInputTokens)) • \(dollarEstimate(cost.cacheRead))")
            if usage.cacheWriteInputTokens > 0 {
                LLMSessionMetricRow(label: "Cache write", value: "\(tokenCount(usage.cacheWriteInputTokens)) • \(dollarEstimate(cost.cacheWrite))")
            }
            LLMSessionMetricRow(label: "Fresh input", value: "\(tokenCount(usage.freshInputTokens)) • \(dollarEstimate(cost.freshInput))")
            LLMSessionMetricRow(label: "Output", value: "\(tokenCount(usage.outputTokens)) • \(dollarEstimate(cost.output))")
            if usage.reasoningOutputTokens > 0 {
                LLMSessionMetricRow(label: "Reasoning", value: "\(tokenCount(usage.reasoningOutputTokens)) (in output)")
            }
            LLMSessionMetricRow(label: "Rebuilds", value: "\(usage.rebuildCount) calls with half+ of a 30K+ prompt uncached")
            if usage.peakContextTokens > 0 {
                LLMSessionMetricRow(label: "Peak context", value: tokenCount(usage.peakContextTokens))
            }
            LLMSessionMetricRow(label: "Cache hit", value: "\(usage.cacheHitPercent)% of input")
            LLMSessionMetricRow(label: "Total", value: "\(tokenCount(usage.totalTokens)) incl. cache reads")
            if usage.turnCount > 0 {
                LLMSessionMetricRow(label: "Model calls", value: "\(usage.turnCount)")
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
    var color: Color = .accentBlue

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
                        .fill(color)
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
