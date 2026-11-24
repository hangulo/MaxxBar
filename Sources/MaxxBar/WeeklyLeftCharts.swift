import SwiftUI

let weeklyLeftHelp = """
Weekly allowance left over the last 24 hours, 72 hours, or seven days (pick with the toggle). One small chart per limit: Claude for all models, each per-model weekly limit Claude reports (for example Fable), and Codex when you show it.

The Claude all models chart and the Codex chart also draw the 5h window as a thinner, fainter line, so you can see each 5h burst against the weekly drop. The 5h line steps back to 100 at each 5h reset.

Hover a chart to read the values at that time. A jump up in the bold line is a weekly reset. Claude history starts when MaxxBar first records its quota; earlier values are unavailable.
"""

/// One weekly limit's remaining percentage over time.
struct WeeklyLeftSeries: Identifiable {
    var id: String { title }
    let title: String
    let color: Color
    let points: [(at: Date, left: Int)]
    let resetAt: Date?
    /// The 5h window over the same range, drawn as a fainter line; empty for limits without one.
    var fiveHourPoints: [(at: Date, left: Int)] = []
}

extension WeeklyLeftSeries {
    /// The series to draw for the providers shown: Claude all models, each Claude model limit, then Codex.
    static func make(
        history: [LLMQuotaHistorySample],
        snapshot: LLMUsageSnapshot,
        from start: Date,
        to end: Date,
        drawsClaude: Bool,
        drawsCodex: Bool
    ) -> [WeeklyLeftSeries] {
        let samples = history.sorted { $0.sampledAt < $1.sampledAt }
        // Keep the last reading before the range so the line starts at the left edge.
        func points(_ value: (LLMQuotaHistorySample) -> Int?) -> [(at: Date, left: Int)] {
            let all = samples.compactMap { sample in value(sample).map { (at: sample.sampledAt, left: $0) } }
            let inside = all.filter { $0.at >= start }
            guard let before = all.last(where: { $0.at < start }) else { return inside }
            return [(at: start, left: before.left)] + inside
        }
        func fiveHour(_ provider: String) -> [(at: Date, left: Int)] {
            let readings = samples.compactMap { sample in
                sample.fiveHourRemainingPercent(for: provider).map {
                    FiveHourLeftPoints.Reading(at: sample.sampledAt, left: $0, resetAt: sample.fiveHourResetAt(for: provider))
                }
            }
            return FiveHourLeftPoints.make(readings, from: start, to: end)
        }
        var result: [WeeklyLeftSeries] = []
        if drawsClaude {
            let claude = snapshot.limits.first { $0.name == "Claude" }
            result.append(WeeklyLeftSeries(
                title: "All models", color: .claudeCoral,
                points: points(\.claudeWeeklyRemainingPercent),
                resetAt: claude?.weeklyWindow?.resetAt ?? samples.last?.claudeWeeklyResetAt,
                fiveHourPoints: fiveHour("Claude")
            ))
            let live = snapshot.limits.filter { $0.name.hasPrefix("Claude ") && $0.weeklyWindow != nil }
                .map { String($0.name.dropFirst("Claude ".count)) }
            let recorded = samples.flatMap { ($0.claudeModelWeeklyRemaining ?? [:]).keys }
            for model in Set(live + recorded).sorted() {
                let limit = snapshot.limits.first { $0.name == "Claude \(model)" }
                result.append(WeeklyLeftSeries(
                    title: model, color: .claudeCoral,
                    points: points { $0.claudeModelWeeklyRemaining?[model] },
                    resetAt: limit?.weeklyWindow?.resetAt ?? samples.last?.claudeModelWeeklyResetAt?[model]
                ))
            }
        }
        if drawsCodex {
            let codex = snapshot.limits.first { $0.name == "Codex" }
            result.append(WeeklyLeftSeries(
                title: "Codex", color: .accentBlue,
                points: points(\.weeklyRemainingPercent),
                resetAt: codex?.weeklyWindow?.resetAt ?? samples.last?.codexWeeklyResetAt,
                fiveHourPoints: fiveHour("Codex")
            ))
        }
        return result
    }
}

/// A small, narrow line chart of one weekly limit: no per-sample markers, hover to read a value.
struct WeeklyLeftMiniChart: View {
    let series: WeeklyLeftSeries
    let start: Date
    let end: Date
    let range: LLMQuotaHistoryRange
    @State private var hovered: (at: Date, left: Int)?
    @State private var hoveredFiveHour: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(series.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let hovered {
                    Text(quotaHoverTime(hovered.at, range: range))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                if !series.fiveHourPoints.isEmpty {
                    Text("5h \((hoveredFiveHour ?? series.fiveHourPoints.last?.left).map { "\($0)%" } ?? "n/a")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(series.color.opacity(0.6))
                        .lineLimit(1)
                }
                Text((hovered?.left ?? series.points.last?.left).map { "\($0)%" } ?? "n/a")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(series.color)
            }
            .monospacedDigit()

            GeometryReader { proxy in
                let rect = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 0, dy: 2)
                ZStack(alignment: .topLeading) {
                    ForEach([0, 50, 100], id: \.self) { marker in
                        Path { path in
                            let y = yPosition(marker, in: rect)
                            path.move(to: CGPoint(x: rect.minX, y: y))
                            path.addLine(to: CGPoint(x: rect.maxX, y: y))
                        }
                        .stroke(Color.freeGray.opacity(marker == 50 ? 0.3 : 0.18), lineWidth: 1)
                    }
                    if series.points.isEmpty {
                        Text("No readings yet")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        if !series.fiveHourPoints.isEmpty {
                            line(series.fiveHourPoints, in: rect)
                                .stroke(series.color.opacity(0.42), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                        }
                        line(series.points, in: rect)
                            .stroke(series.color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                    if let hovered {
                        let x = xPosition(hovered.at, in: rect)
                        Path { path in
                            path.move(to: CGPoint(x: x, y: rect.minY))
                            path.addLine(to: CGPoint(x: x, y: rect.maxY))
                        }
                        .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        Circle()
                            .fill(series.color)
                            .frame(width: 5, height: 5)
                            .position(x: x, y: yPosition(hovered.left, in: rect))
                        if let hoveredFiveHour {
                            Circle()
                                .fill(series.color.opacity(0.6))
                                .frame(width: 4, height: 4)
                                .position(x: x, y: yPosition(hoveredFiveHour, in: rect))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovered = reading(series.points, atX: location.x, in: rect)
                        hoveredFiveHour = reading(series.fiveHourPoints, atX: location.x, in: rect)?.left
                    case .ended:
                        hovered = nil
                        hoveredFiveHour = nil
                    }
                }
            }
            .frame(height: series.fiveHourPoints.isEmpty ? 38 : 44)

            Text(series.resetAt.map { "resets \($0.formatted(.dateTime.weekday(.abbreviated).hour()))" } ?? " ")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
    }

    private func xPosition(_ date: Date, in rect: CGRect) -> CGFloat {
        let span = max(end.timeIntervalSince(start), 1)
        let fraction = min(max(date.timeIntervalSince(start) / span, 0), 1)
        return rect.minX + rect.width * fraction
    }

    private func yPosition(_ percent: Int, in rect: CGRect) -> CGFloat {
        rect.maxY - rect.height * CGFloat(min(max(percent, 0), 100)) / 100
    }

    private func line(_ points: [(at: Date, left: Int)], in rect: CGRect) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let position = CGPoint(x: xPosition(point.at, in: rect), y: yPosition(point.left, in: rect))
                index == 0 ? path.move(to: position) : path.addLine(to: position)
            }
            // Carry the last reading to now so a quiet stretch still reads as a plateau.
            if let last = points.last, last.at < end {
                path.addLine(to: CGPoint(x: xPosition(end, in: rect), y: yPosition(last.left, in: rect)))
            }
        }
    }

    /// The reading in effect at a horizontal position: the last one at or before that time.
    private func reading(_ points: [(at: Date, left: Int)], atX x: CGFloat, in rect: CGRect) -> (at: Date, left: Int)? {
        guard rect.width > 0, !points.isEmpty else { return nil }
        let fraction = min(max((x - rect.minX) / rect.width, 0), 1)
        let date = start.addingTimeInterval(end.timeIntervalSince(start) * fraction)
        return points.last { $0.at <= date } ?? points.first
    }
}

/// The small charts laid out two per row.
struct WeeklyLeftChartGrid: View {
    let series: [WeeklyLeftSeries]
    let start: Date
    let end: Date
    let range: LLMQuotaHistoryRange

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 8) {
            ForEach(series) { item in
                WeeklyLeftMiniChart(series: item, start: start, end: end, range: range)
            }
        }
    }
}
