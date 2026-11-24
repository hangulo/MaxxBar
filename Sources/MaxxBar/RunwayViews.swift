import AppKit
import SwiftUI

struct LLMRunwayPanelView: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    var onSampleQuota: (() -> Void)?
    var onCheckClaudeNow: (() -> Void)?
    var quotaWindowLedger: [QuotaWindowRecord] = []
    var isBuildingUsageReport = false
    var onOpenUsageReport: (() -> Void)?
    var isCheckingClaude = false
    var claudeCheckNote: String?
    var onSignInToClaude: (() -> Void)?
    var isWaitingForClaudeSignIn = false
    var claudeSignInNote: String?
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var advancedExpanded = false
    @AppStorage(ProviderVisibility.showClaudeKey) private var showClaude = true
    @AppStorage(ProviderVisibility.showCodexKey) private var showCodex = true

    var body: some View {
        VStack(spacing: 7) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    if runwayLimits.isEmpty {
                        LLMUsageUnavailableCard(message: snapshot.error ?? "Live AI usage unavailable")
                    } else {
                        ForEach(runwayLimits) { limit in
                            LLMUsageLimitCard(
                                limit: limit,
                                title: runwayTitle(for: limit),
                                unavailableMessage: snapshot.providerErrors[limit.name],
                                resetCreditCount: limit.name == "Codex" ? snapshot.resetCreditCount : nil,
                                resetCreditExpirations: limit.name == "Codex" ? snapshot.resetCreditExpirations : [],
                                onCheckNow: limit.name == "Claude" ? onCheckClaudeNow : nil,
                                isChecking: limit.name == "Claude" && isCheckingClaude,
                                checkNote: limit.name == "Claude" ? claudeCheckNote : nil,
                                signIn: limit.name == "Claude" ? claudeSignInPrompt : nil
                            )
                        }
                    }

                    let statusErrors = providerStatusErrors
                    if !statusErrors.isEmpty {
                        LLMProviderStatusCard(errors: statusErrors)
                    }

                    LLMLocalUsageCard(snapshot: snapshot, quotaHistory: quotaHistory, onSampleQuota: onSampleQuota)
                    DrawdownInsightCard(snapshot: snapshot, quotaHistory: quotaHistory)
                    if showClaude || !showCodex {
                        QuotaWasteForecastCard(snapshot: snapshot, quotaHistory: quotaHistory, records: quotaWindowLedger)
                        QuotaLeftAtResetCard(
                            snapshot: snapshot, records: quotaWindowLedger,
                            isBuildingReport: isBuildingUsageReport, onOpenReport: onOpenUsageReport
                        )
                    }
                    LLMAdvancedUsageCard(snapshot: snapshot, isExpanded: $advancedExpanded)
                }
            }

        }
    }

    private var runwayLimits: [LLMUsageLimit] {
        let preferred = snapshot.limits.filter { $0.name == "Codex" || $0.name == "Claude" }
        var result = preferred.isEmpty ? Array(snapshot.limits.prefix(2)) : preferred
        if !result.contains(where: { $0.name == "Claude" }), snapshot.providerErrors["Claude"] != nil {
            result.append(LLMUsageLimit(name: "Claude", primary: nil, secondary: nil))
        }
        return result.filter { limit in
            switch limit.name {
            case "Claude": return showClaude || !showCodex
            case "Codex": return showCodex || !showClaude
            default: return true
            }
        }
    }

    // A runway card with no windows already shows its provider's error in its body,
    // so the status card only lists errors no runway card is showing.
    private var providerStatusErrors: [String: String] {
        var shownInRunway = Set(runwayLimits.filter { !$0.hasRunwayWindows }.map(\.name))
        // The Claude card shows a sign-in problem itself, next to its Sign in again button.
        if claudeSignInPrompt?.needsSignIn == true, runwayLimits.contains(where: { $0.name == "Claude" }) {
            shownInRunway.insert("Claude")
        }
        return snapshot.providerErrors.filter { !shownInRunway.contains($0.key) }
    }

    /// Shown when Claude Code is signed out, within 7 days of its sign-in ending, or while a sign-in is underway.
    private var claudeSignInPrompt: ClaudeSignInPrompt? {
        guard let onSignInToClaude else { return nil }
        let needsSignIn = snapshot.claudeNeedsSignIn
        let warning = needsSignIn ? nil : ClaudeCredentialManager.signInWarning(endsAt: snapshot.claudeSignInEndsAt)
        guard needsSignIn || warning != nil || isWaitingForClaudeSignIn else { return nil }
        return ClaudeSignInPrompt(needsSignIn: needsSignIn, warning: warning, isWaiting: isWaitingForClaudeSignIn,
                                  note: claudeSignInNote, action: onSignInToClaude)
    }

    private func runwayTitle(for limit: LLMUsageLimit) -> String {
        limit.name == "Codex"
            ? "CODEX RUNWAY (\(planName(snapshot.planType)))"
            : "\(limit.name.uppercased()) RUNWAY"
    }

}

struct LLMUsageLimitCard: View {
    let limit: LLMUsageLimit
    var title: String?
    var unavailableMessage: String? = nil
    var resetCreditCount: Int? = nil
    var resetCreditExpirations: [LLMResetCreditExpiration] = []
    var onCheckNow: (() -> Void)? = nil
    var isChecking = false
    var checkNote: String? = nil
    var signIn: ClaudeSignInPrompt? = nil
    @State private var resetDetailsPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle(
                    title ?? limit.name.uppercased(),
                    help: limit.name.hasPrefix("Claude") ? claudeRunwayHelp : codexRunwayHelp,
                    color: providerColor
                )
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
            if let onCheckNow {
                HStack(spacing: 6) {
                    if let checkNote = visibleCheckNote, !isChecking {
                        Text(checkNote)
                    } else if let summary = limit.readingSummary() {
                        Text(summary)
                    }
                    Spacer()
                    if isChecking {
                        ProgressView().controlSize(.mini)
                        Text("Checking…")
                    } else {
                        Button("Check now", action: onCheckNow)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentBlue)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.56))
            } else if let cachedAt = limit.cachedAt {
                Text("Last checked \(cachedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.56))
            }
            let windows = orderedWindows
            if windows.isEmpty {
                Text(unavailableMessage ?? "No live limit windows returned by the usage API.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.56))
            } else {
                ForEach(windows, id: \.label) { window in
                    LLMUsageProgress(window: window, color: providerColor)
                }
                if signIn?.needsSignIn == true, let unavailableMessage {
                    Text(unavailableMessage)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let signIn {
                ClaudeSignInRow(prompt: signIn)
            }
        }
        .sectionStyle()
        .overlay(RoundedRectangle(cornerRadius: 8).fill(providerColor.opacity(limit.name.hasPrefix("Claude") ? 0.045 : 0)).allowsHitTesting(false))
    }

    private var providerColor: Color { limit.name.hasPrefix("Claude") ? .claudeCoral : .accentBlue }

    // With no windows the body already shows unavailableMessage; don't repeat it above.
    private var visibleCheckNote: String? {
        guard let checkNote else { return nil }
        if !limit.hasRunwayWindows || signIn?.needsSignIn == true, checkNote == unavailableMessage { return nil }
        return checkNote
    }

    private var orderedWindows: [LLMUsageWindow] {
        [limit.shortWindow, limit.weeklyWindow]
            .compactMap { $0 }
            .reduce(into: [LLMUsageWindow]()) { result, window in
                if !result.contains(where: { $0.label == window.label && $0.windowSeconds == window.windowSeconds }) {
                    result.append(window)
                }
            }
    }
}

struct ClaudeSignInPrompt {
    /// Signed out or expired: the card's message already says what happened.
    var needsSignIn: Bool
    /// The 7-day warning, when the sign-in still works but ends soon.
    var warning: String?
    var isWaiting: Bool
    var note: String?
    var action: () -> Void
}

/// The 7-day warning or the sign-in progress, with the one-click "Sign in again" button.
struct ClaudeSignInRow: View {
    let prompt: ClaudeSignInPrompt
    private static let amber = Color(red: 255 / 255, green: 184 / 255, blue: 77 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let warning = prompt.warning {
                Text(warning)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Self.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if prompt.isWaiting {
                    ProgressView().controlSize(.mini)
                }
                if let note = prompt.note {
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Sign in again", action: prompt.action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(prompt.isWaiting ? Color.white.opacity(0.35) : Color.claudeCoral)
                    .disabled(prompt.isWaiting)
                    .help("Opens Terminal and runs claude auth login")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

extension LLMUsageLimit {
    var hasRunwayWindows: Bool { shortWindow != nil || weeklyWindow != nil }
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
            Text("AI USAGE")
                .sectionTitle()
            Text(message)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
        }
        .sectionStyle()
    }
}

struct LLMProviderStatusCard: View {
    let errors: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROVIDER STATUS")
                .sectionTitle()
            ForEach(errors.keys.sorted(), id: \.self) { provider in
                Text("\(provider): \(errors[provider] ?? "Unavailable")")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sectionStyle()
    }
}

struct DrawdownInsightCard: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    @State private var mode = LLMQuotaDrawdownMode.last
    @AppStorage(ProviderVisibility.showClaudeKey) private var showClaude = true
    @AppStorage(ProviderVisibility.showCodexKey) private var showCodex = true

    private var provider: String { showClaude || !showCodex ? "Claude" : "Codex" }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle("\(provider.uppercased()) DRAWDOWN", help: drawdownInsightHelp)
                Spacer()
                if insight != nil {
                    LLMQuotaDrawdownModeToggle(selection: $mode)
                }
            }

            if let insight {
                LLMQuotaDrawdownInsightView(insight: insight, accent: provider == "Claude" ? .claudeCoral : .accentBlue)
            } else {
                Text("No local drawdown pattern yet")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .sectionStyle()
    }

    private var insight: LLMQuotaDrawdownInsight? {
        quotaDrawdownInsight(from: rangedQuotaHistory, provider: provider, mode: mode)
    }

    private var rangedQuotaHistory: [LLMQuotaHistorySample] {
        let cutoff = Date().addingTimeInterval(-LLMQuotaHistoryRange.sevenDays.interval)
        let samples = effectiveQuotaHistory.filter { $0.sampledAt >= cutoff }
        return samples.isEmpty ? Array(effectiveQuotaHistory.suffix(1)) : samples
    }

    private var effectiveQuotaHistory: [LLMQuotaHistorySample] {
        quotaHistoryWithLiveReading(quotaHistory, snapshot: snapshot)
    }
}

/// The saved history plus the current reading when it is newer than the last saved sample.
private func quotaHistoryWithLiveReading(_ history: [LLMQuotaHistorySample], snapshot: LLMUsageSnapshot) -> [LLMQuotaHistorySample] {
    let codex = snapshot.limits.first { $0.name == "Codex" }
    let claude = snapshot.limits.first { $0.name == "Claude" }
    guard let updatedAt = snapshot.lastUpdated, codex != nil || claude != nil,
          updatedAt > (history.last?.sampledAt ?? .distantPast) else {
        return history
    }
    let modelWeeklies = Dictionary(
        snapshot.limits.compactMap { limit -> (String, LLMUsageWindow)? in
            guard limit.name.hasPrefix("Claude "), let weekly = limit.weeklyWindow else { return nil }
            return (String(limit.name.dropFirst("Claude ".count)), weekly)
        },
        uniquingKeysWith: { first, _ in first }
    )
    return history + [LLMQuotaHistorySample(
        sampledAt: updatedAt,
        primaryRemainingPercent: codex?.shortWindow?.remainingPercent,
        weeklyRemainingPercent: codex?.weeklyWindow?.remainingPercent,
        planType: codex == nil ? nil : snapshot.planType,
        claudeWeeklyRemainingPercent: claude?.weeklyWindow?.remainingPercent,
        claudeFiveHourRemainingPercent: claude?.shortWindow?.remainingPercent,
        claudePlanType: claude == nil ? nil : snapshot.claudePlanType,
        claudeSource: claude?.source,
        codexFiveHourResetAt: codex?.shortWindow?.resetAt,
        codexWeeklyResetAt: codex?.weeklyWindow?.resetAt,
        claudeFiveHourResetAt: claude?.shortWindow?.resetAt,
        claudeWeeklyResetAt: claude?.weeklyWindow?.resetAt,
        claudeModelWeeklyRemaining: modelWeeklies.isEmpty ? nil : modelWeeklies.mapValues(\.remainingPercent),
        claudeModelWeeklyResetAt: modelWeeklies.isEmpty ? nil : modelWeeklies.compactMapValues(\.resetAt)
    )]
}

struct LLMLocalUsageCard: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    var onSampleQuota: (() -> Void)?
    @AppStorage("weeklyDrawdownRange") private var drawdownRange = LLMQuotaHistoryRange.sevenDays
    @AppStorage(ProviderVisibility.showClaudeKey) private var showClaude = true
    @AppStorage(ProviderVisibility.showCodexKey) private var showCodex = true

    var body: some View {
        let end = Date()
        let start = end.addingTimeInterval(-drawdownRange.interval)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                InstantHelpTitle("WEEKLY LEFT", help: weeklyLeftHelp)
                Spacer()
                LLMQuotaHistoryRangeToggle(selection: $drawdownRange, ranges: [.day, .threeDays, .sevenDays])
            }

            WeeklyLeftChartGrid(
                series: WeeklyLeftSeries.make(
                    history: effectiveQuotaHistory, snapshot: snapshot, from: start, to: end,
                    drawsClaude: showClaude || !showCodex, drawsCodex: showCodex || !showClaude
                ),
                start: start, end: end, range: drawdownRange
            )

            Button {
                onSampleQuota?()
            } label: {
                Text("Updated \(localDrawdownUpdatedAt(effectiveQuotaHistory.last?.sampledAt))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .monospacedDigit()
            }
            .buttonStyle(.plain)
            .disabled(onSampleQuota == nil)
            .help("Capture the current weekly values now")
        }
        .sectionStyle()
    }

    private var effectiveQuotaHistory: [LLMQuotaHistorySample] {
        quotaHistoryWithLiveReading(quotaHistory, snapshot: snapshot)
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
                LLMQuotaHistoryRangeToggle(
                    selection: $range,
                    ranges: [.sixHours, .day]
                )
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
