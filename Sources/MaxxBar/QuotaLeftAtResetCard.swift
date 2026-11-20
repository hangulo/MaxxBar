import SwiftUI

let leftAtResetHelp = """
Your weekly Claude allowance at each reset, from llm-window-ledger.jsonl: orange is what you used, gray is what expired unused. The last bar, outlined, is this week so far.

The weekly allowance is the real expiry, so 5 hour windows are left to the full report. Faded bars are low confidence: the last reading came more than 30 minutes before the reset. A question mark means it came more than 12 hours before, so the figure is unknown.
"""

/// "Unused credits": a compact bar per weekly reset (used vs expired unused), with a link to the full usage report.
struct QuotaLeftAtResetCard: View {
    let snapshot: LLMUsageSnapshot
    let records: [QuotaWindowRecord]
    var isBuildingReport = false
    var onOpenReport: (() -> Void)?

    static let maxBars = 6
    /// Same cutoff the report uses: a reading this long before the reset says nothing about the end of the week.
    static let unknownAge = 12 * 3_600

    var body: some View {
        let bars = self.bars
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle("UNUSED CREDITS", help: leftAtResetHelp, color: .claudeCoral)
                Spacer()
                Button(isBuildingReport ? "Building report…" : "Open full report") { onOpenReport?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.claudeCoral)
                    .disabled(onOpenReport == nil || isBuildingReport)
                    .help("Write the usage report with drill downs and open it in your browser")
            }

            if bars.isEmpty {
                Text("No weekly reset yet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(bars) { bar in
                        WeeklyResetBar(bar: bar)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    legend(Color.claudeCoral, "Used")
                    legend(Color.freeGray, "Expired unused")
                    Spacer()
                    if let average {
                        Text("\(average)% left on avg")
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 10, weight: .medium))
            }
        }
        .sectionStyle()
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var weekly: [QuotaWindowRecord] {
        records.filter { $0.kind == .weekly }.sorted { $0.windowResetAt < $1.windowResetAt }
    }

    private var average: Int? {
        let known = weekly.filter { $0.sampleAgeAtResetSeconds <= Self.unknownAge }
        guard !known.isEmpty else { return nil }
        return Int((Double(known.map(\.leftPercent).reduce(0, +)) / Double(known.count)).rounded())
    }

    private var bars: [WeeklyResetBar.Model] {
        let live = snapshot.limits.first { $0.name == "Claude" }?.weeklyWindow
        let liveBar = live.flatMap { window -> WeeklyResetBar.Model? in
            guard let reset = window.resetAt,
                  !weekly.contains(where: { abs($0.windowResetAt.timeIntervalSince(reset)) < QuotaWindowLedger.sameResetTolerance })
            else { return nil }
            return WeeklyResetBar.Model(resetAt: reset, left: window.remainingPercent, state: .live)
        }
        let closed = weekly.suffix(Self.maxBars - (liveBar == nil ? 0 : 1)).map { record in
            WeeklyResetBar.Model(
                resetAt: record.windowResetAt, left: record.leftPercent,
                state: record.sampleAgeAtResetSeconds > Self.unknownAge ? .unknown
                    : record.lowConfidence ? .lowConfidence : .closed,
                ageMinutes: record.sampleAgeAtResetSeconds / 60
            )
        }
        return closed + (liveBar.map { [$0] } ?? [])
    }
}

/// One week: used (orange) at the bottom, expired unused (gray) on top, unused percentage above.
struct WeeklyResetBar: View {
    struct Model: Identifiable {
        enum State { case closed, lowConfidence, unknown, live }
        var id: Date { resetAt }
        let resetAt: Date
        let left: Int
        let state: State
        var ageMinutes = 0
    }

    let bar: Model
    static let plotHeight: CGFloat = 64

    var body: some View {
        let left = CGFloat(min(max(bar.left, 0), 100)) / 100
        VStack(spacing: 3) {
            Text(bar.state == .unknown ? "?" : "\(bar.left)%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(bar.state == .closed || bar.state == .live ? 0.78 : 0.45))
                .monospacedDigit()
            VStack(spacing: 0) {
                unused
                    .frame(height: Self.plotHeight * left)
                Rectangle()
                    .fill(Color.claudeCoral)
                    .frame(height: Self.plotHeight * (1 - left))
            }
            .frame(maxWidth: 30)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                if bar.state == .live {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.freeGray.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            Text(bar.state == .live ? "so far" : bar.resetAt.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(help)
    }

    @ViewBuilder private var unused: some View {
        switch bar.state {
        case .closed: Rectangle().fill(Color.freeGray.opacity(0.75))
        case .lowConfidence: Rectangle().fill(Color.freeGray.opacity(0.4))
        case .unknown: Rectangle().fill(Color.freeGray.opacity(0.18))
        case .live: Rectangle().fill(Color.clear)
        }
    }

    private var help: String {
        let reset = bar.resetAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        switch bar.state {
        case .live: return "This week so far: \(bar.left)% left, resets \(reset)"
        case .closed: return "Week ending \(reset): \(bar.left)% expired unused, \(100 - bar.left)% used"
        case .lowConfidence:
            return "Week ending \(reset): \(bar.left)% expired unused (low confidence, last reading \(bar.ageMinutes) minutes before the reset)"
        case .unknown:
            return "Week ending \(reset): unknown, the last reading was \(bar.ageMinutes / 60) hours before the reset"
        }
    }
}
