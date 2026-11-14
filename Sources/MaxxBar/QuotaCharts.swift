import AppKit
import SwiftUI

enum LLMQuotaHistoryRange: String, CaseIterable, Identifiable {
    case sixHours = "6H"
    case day = "24H"
    case threeDays = "72H"
    case sevenDays = "1W"

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .sixHours:
            return 6 * 60 * 60
        case .day:
            return 24 * 60 * 60
        case .threeDays:
            return 3 * 24 * 60 * 60
        case .sevenDays:
            return 7 * 24 * 60 * 60
        }
    }
}

struct LLMQuotaHistoryRangeToggle: View {
    @Binding var selection: LLMQuotaHistoryRange
    var ranges = LLMQuotaHistoryRange.allCases

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ranges) { range in
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
    var rangeSelection: Binding<LLMQuotaHistoryRange>?
    @State private var hoveredPoint: LLMQuotaPlotPoint?
    @AppStorage(ProviderVisibility.showClaudeKey) private var showClaude = true
    @AppStorage(ProviderVisibility.showCodexKey) private var showCodex = true

    private var drawsCodex: Bool { showCodex || !showClaude }
    private var drawsClaude: Bool { showClaude || !showCodex }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                if drawsClaude {
                    seriesLegend("Claude", keyPath: \.claudeWeeklyRemainingPercent, color: .claudeCoral)
                }
                if drawsCodex {
                    seriesLegend("Codex", keyPath: \.weeklyRemainingPercent, color: .accentBlue)
                }
                Spacer()
                if let rangeSelection {
                    LLMQuotaHistoryRangeToggle(selection: rangeSelection, ranges: [.day, .threeDays, .sevenDays])
                } else {
                    Text(range.rawValue).foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(size: 10, weight: .medium))
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

                    if drawsCodex {
                        linePath(for: \.weeklyRemainingPercent, in: chartRect)
                            .stroke(
                                Color.accentBlue.opacity(0.28),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )
                        linePath(for: \.weeklyRemainingPercent, in: chartRect)
                            .stroke(
                                Color.accentBlue,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                            )
                        sampleDots(for: \.weeklyRemainingPercent, color: .accentBlue, label: "Codex", in: chartRect)
                    }
                    if drawsClaude {
                        linePath(for: \.claudeWeeklyRemainingPercent, in: chartRect)
                            .stroke(Color.claudeCoral.opacity(0.25), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        linePath(for: \.claudeWeeklyRemainingPercent, in: chartRect)
                            .stroke(Color.claudeCoral, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        sampleDots(for: \.claudeWeeklyRemainingPercent, color: .claudeCoral, label: "Claude", in: chartRect)
                    }

                    if let hoveredPoint {
                        hoverIndicator(for: hoveredPoint, in: chartRect)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoveredPoint = nearestPoint(to: location, in: chartRect)
                    case .ended:
                        hoveredPoint = nil
                    }
                }
            }
            .frame(height: 58)
        }
    }

    private func seriesLegend(_ name: String, keyPath: KeyPath<LLMQuotaHistorySample, Int?>, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(name)
            Text(samples.last?[keyPath: keyPath].map { "\($0)%" } ?? "—")
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }

    private func sampleDots(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, color: Color, label: String, in rect: CGRect) -> some View {
        ForEach(changePlotPoints(for: keyPath, label: label)) { point in
            Circle()
                .fill(color.opacity(0.82))
                .overlay(Circle().stroke(Color.background.opacity(0.9), lineWidth: 0.8))
                .frame(width: 4, height: 4)
                .position(pointPosition(for: point, in: rect))
        }
    }

    private func hoverIndicator(for point: LLMQuotaPlotPoint, in rect: CGRect) -> some View {
        let color: Color = point.series == "Claude" ? .claudeCoral : .accentBlue
        let position = pointPosition(for: point, in: rect)
        let tooltipX = min(max(position.x, rect.minX + 62), rect.maxX - 62)
        let tooltipY = position.y < rect.midY ? position.y + 15 : position.y - 15

        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: position.x, y: rect.minY))
                path.addLine(to: CGPoint(x: position.x, y: rect.maxY))
            }
            .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(color, lineWidth: 2))
                .frame(width: 9, height: 9)
                .position(position)

            Text("\(point.series) \(point.remainingPercent)% · \(quotaHoverTime(point.sampledAt, range: range))")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.background.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.55), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .position(x: tooltipX, y: tooltipY)
        }
    }

    private func nearestPoint(to location: CGPoint, in rect: CGRect) -> LLMQuotaPlotPoint? {
        let points = (drawsCodex ? changePlotPoints(for: \.weeklyRemainingPercent, label: "Codex") : [])
            + (drawsClaude ? changePlotPoints(for: \.claudeWeeklyRemainingPercent, label: "Claude") : [])
        guard location.x >= rect.minX - 8, location.x <= rect.maxX + 8 else { return nil }
        return points.min {
            hypot(pointPosition(for: $0, in: rect).x - location.x, pointPosition(for: $0, in: rect).y - location.y)
                < hypot(pointPosition(for: $1, in: rect).x - location.x, pointPosition(for: $1, in: rect).y - location.y)
        }
    }

    private func changePlotPoints(for keyPath: KeyPath<LLMQuotaHistorySample, Int?>, label: String) -> [LLMQuotaPlotPoint] {
        let values = samples.compactMap { sample -> (Date, Int)? in
            guard let remaining = sample[keyPath: keyPath] else { return nil }
            return (sample.sampledAt, remaining)
        }
        // Keep the range endpoints and the first sample of each new percentage.
        // The full series still draws the line so plateaus retain their duration.
        return values.enumerated().compactMap { index, value in
            let isEndpoint = index == 0 || index == values.count - 1
            let changed = index > 0 && value.1 != values[index - 1].1
            guard isEndpoint || changed else { return nil }
            return LLMQuotaPlotPoint(series: label, sampledAt: value.0, remainingPercent: value.1)
        }
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
        let end = Date()
        return (end.addingTimeInterval(-range.interval), end)
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
    /// Burn rate over the current segment (since the last reset or plan change), when there is one to show.
    var paceText: String? = nil
}

struct LLMQuotaMilestone: Identifiable {
    var id: String { "\(label)-\(sampledAt.timeIntervalSince1970)-\(remainingPercent)" }
    let label: String
    let sampledAt: Date
    let remainingPercent: Int
}

struct LLMQuotaDrawdownInsightView: View {
    let insight: LLMQuotaDrawdownInsight
    var accent: Color = .accentBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(insight.startPercent)% → \(insight.endPercent)% in")
                        .foregroundStyle(.white.opacity(0.86))
                    Text(insight.durationText)
                        .foregroundStyle(accent)
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

            if let paceText = insight.paceText {
                Text(paceText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .monospacedDigit()
                    .lineLimit(2)
            }

            VStack(spacing: 2) {
                ForEach(insight.milestones) { milestone in
                    HStack(spacing: 7) {
                        Text(milestone.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.9))
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
