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
