import SwiftUI

let leftAtResetHelp = """
What was still unused when each Claude window reset, from llm-window-ledger.jsonl.

5 hour figures are what was left in that window. An idle 5 hour window only costs something if the weekly allowance also resets with credit left, so the weekly figure is the real expiry.

Gray values are low confidence: the last reading came more than 30 minutes before the reset.
"""

/// "Left at reset": unused share of the last closed Claude windows, with a link to the full usage report.
struct QuotaLeftAtResetCard: View {
    let snapshot: LLMUsageSnapshot
    let records: [QuotaWindowRecord]
    var isBuildingReport = false
    var onOpenReport: (() -> Void)?

    var body: some View {
        let summary = QuotaLeftAtReset(records: records)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle("LEFT AT RESET", help: leftAtResetHelp, color: .claudeCoral)
                Spacer()
                Button(isBuildingReport ? "Building report…" : "Open full report") { onOpenReport?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.claudeCoral)
                    .disabled(onOpenReport == nil || isBuildingReport)
                    .help("Write the usage report with drill downs and open it in your browser")
            }

            if records.isEmpty {
                Text("No closed window yet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                row("Last 5h window", record: summary.lastFiveHour, suffix: "left in window")
                averageRow("5h today", summary.fiveHourAverageToday, count: summary.fiveHourCountToday)
                averageRow("5h, 7 days", summary.fiveHourAverageWeek, count: summary.fiveHourCountWeek)
                row("Last weekly reset", record: summary.lastWeekly, suffix: "expired unused")
            }
            if let weekly = claude?.weeklyWindow {
                liveRow("This week so far", window: weekly)
            }
            ForEach(modelLimits, id: \.name) { limit in
                if let window = limit.weeklyWindow {
                    liveRow("\(limit.name.dropFirst("Claude ".count)) weekly", window: window,
                            closed: summary.lastModelWeekly[String(limit.name.dropFirst("Claude ".count))])
                }
            }
        }
        .sectionStyle()
    }

    private var claude: LLMUsageLimit? { snapshot.limits.first { $0.name == "Claude" } }
    private var modelLimits: [LLMUsageLimit] {
        snapshot.limits.filter { $0.name.hasPrefix("Claude ") && $0.weeklyWindow != nil }
    }

    private func row(_ label: String, record: QuotaWindowRecord?, suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.white.opacity(0.62))
            Spacer()
            if let record {
                Text("\(record.leftPercent)% \(suffix)")
                    .foregroundStyle(.white.opacity(record.lowConfidence ? 0.4 : 0.9))
                Text(record.windowResetAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                Text("None yet").foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .help(record.map { $0.lowConfidence
            ? "Low confidence: the last reading was \($0.sampleAgeAtResetSeconds / 60) minutes before the reset"
            : "Last reading \($0.sampleAgeAtResetSeconds / 60) minutes before the reset" } ?? "")
    }

    private func averageRow(_ label: String, _ value: Double?, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text(value.map { "\(Int($0.rounded()))% left in window" } ?? "No window closed")
                .foregroundStyle(.white.opacity(value == nil ? 0.4 : 0.9))
            if count > 0 {
                Text("\(count) window\(count == 1 ? "" : "s")").foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
    }

    private func liveRow(_ label: String, window: LLMUsageWindow, closed: QuotaWindowRecord? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text("\(window.remainingPercent)% left").foregroundStyle(.white.opacity(0.9))
            if let reset = window.resetAt {
                Text("resets \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .help(closed.map { "Last reset left \($0.leftPercent)% unused\($0.lowConfidence ? " (low confidence)" : "")" } ?? "")
    }
}
