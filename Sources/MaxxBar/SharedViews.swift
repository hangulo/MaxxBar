import AppKit
import SwiftUI

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

func temperature(_ value: Double?) -> String {
    guard let value else {
        return "-\(TemperatureDisplayUnit.preferred.suffix)"
    }
    let unit = TemperatureDisplayUnit.preferred
    return "\(Int(unit.displayValue(celsius: value).rounded()))\(unit.suffix)"
}

func temperaturePercent(_ value: Double?) -> Double {
    guard let value else { return 0 }
    return min(max(value / 120 * 100, 0), 100)
}

func fanStatus(_ snapshot: SensorSnapshot) -> String {
    guard let rpm = snapshot.fanRPM else { return "-" }
    return rpm > 0 ? "ON" : "OFF"
}

func fanPercent(_ snapshot: SensorSnapshot) -> Double {
    guard let rpm = snapshot.fanRPM else { return 0 }
    return rpm > 0 ? 100 : 0
}

func percent(_ value: Int?) -> String {
    guard let value else { return "-%" }
    return "\(value)%"
}

func rpm(_ value: Int?) -> String {
    guard let value else { return "-" }
    return "\(value.formatted()) rpm"
}

private func amps(_ value: Double?) -> String {
    guard let value else { return "-" }
    return String(format: "%.1f A", value)
}

func watts(_ value: Double?) -> String {
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

func tokenCount(_ value: UInt64) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

func dollarEstimate(_ value: Double) -> String {
    if value >= 100 {
        return String(format: "$%.0f", value)
    }
    if value >= 10 {
        return String(format: "$%.1f", value)
    }
    return String(format: "$%.2f", value)
}

private struct LLMQuotaValue {
    let sampledAt: Date
    let remainingPercent: Int
    let planType: String?
    var resetAt: Date? = nil
}

/// True when sample `index` starts a new plan: both plans are known and differ, or remaining jumped up
/// while the previous sample said the weekly reset was still more than a minute away.
private func isPlanChange(_ values: [LLMQuotaValue], at index: Int) -> Bool {
    let previous = values[index - 1]
    let current = values[index]
    if let before = previous.planType, let after = current.planType {
        return before.caseInsensitiveCompare(after) != .orderedSame
    }
    if current.remainingPercent > previous.remainingPercent + 2,
       let resetAt = previous.resetAt,
       current.sampledAt < resetAt.addingTimeInterval(-60) {
        return true
    }
    return false
}

func quotaDrawdownInsight(
    from samples: [LLMQuotaHistorySample],
    provider: String,
    mode: LLMQuotaDrawdownMode
) -> LLMQuotaDrawdownInsight? {
    let values = samples
        .compactMap { sample -> LLMQuotaValue? in
            guard let remaining = sample.weeklyRemainingPercent(for: provider) else { return nil }
            return LLMQuotaValue(
                sampledAt: sample.sampledAt,
                remainingPercent: remaining,
                planType: sample.plan(for: provider),
                resetAt: sample.weeklyResetAt(for: provider)
            )
        }
        .sorted { $0.sampledAt < $1.sampledAt }

    guard values.count >= 2 else { return nil }

    // A plan change rescales the percentages, so it starts a new segment but is not a reset.
    let planChangeIndices = values.indices.dropFirst().filter { isPlanChange(values, at: $0) }
    let resetIndices = values.indices.dropFirst().filter { index in
        !planChangeIndices.contains(index)
            && values[index].remainingPercent - values[index - 1].remainingPercent >= 50
            && values[index].remainingPercent >= 80
    }
    let segmentStarts = (resetIndices + planChangeIndices).sorted()

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
            segmentStart = segmentStarts.last(where: { $0 <= segmentEnd }) ?? 0
            subtitle = "Last exhausted run before the current reset; crossings may fall between samples."
        } else {
            segmentEnd = values.count - 1
            segmentStart = segmentStarts.last(where: { $0 <= segmentEnd }) ?? 0
            subtitle = "Latest sampled drawdown; crossings may fall between samples."
        }
    case .current:
        segmentEnd = values.count - 1
        segmentStart = segmentStarts.last ?? 0
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
        milestones: deduplicatedMilestones(milestones),
        paceText: quotaPaceText(values, since: segmentStarts.last ?? 0)
    )
}

/// Burn rate from the last reset or plan change to now, and whether the week lasts until its reset at that pace.
/// Samples from before a plan change are never mixed in, because their percentages measure a different allowance.
private func quotaPaceText(_ values: [LLMQuotaValue], since start: Int) -> String? {
    guard let last = values.last, start < values.count - 1 else { return nil }
    let first = values[start]
    let hours = last.sampledAt.timeIntervalSince(first.sampledAt) / 3_600
    let used = first.remainingPercent - last.remainingPercent
    guard hours >= 1, used > 0 else { return nil }
    let perDay = Double(used) / hours * 24
    let rate = perDay >= 10 ? String(format: "%.0f%%/day", perDay) : String(format: "%.1f%%/day", perDay)
    let hoursLeft = Double(last.remainingPercent) / (perDay / 24)
    let emptyAt = last.sampledAt.addingTimeInterval(hoursLeft * 3_600)
    if let resetAt = last.resetAt, emptyAt >= resetAt {
        // Times already end in "a.m." or "p.m.", so the sentence ends there without another period.
        return "Pace \(rate) since \(quotaDayTime(first.sampledAt)); lasts until the reset"
    }
    return "Pace \(rate) since \(quotaDayTime(first.sampledAt)); runs out around \(quotaDayTime(emptyAt))"
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

func aiDuration(_ interval: TimeInterval) -> String {
    let minutes = max(Int((interval / 60).rounded()), 0)
    if minutes >= 60 {
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    return "\(minutes)m"
}

func planName(_ value: String?) -> String {
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

func resetLabel(_ value: Date?) -> String {
    guard let value else { return "Reset unavailable" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return "Resets \(formatter.localizedString(for: value, relativeTo: Date()))"
}

func resetCreditExpirationLine(_ expiration: LLMResetCreditExpiration) -> String {
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

func relativeTime(_ value: Date?) -> String {
    guard let value else { return "-" }
    if abs(value.timeIntervalSinceNow) < 60 {
        return "Now"
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: value, relativeTo: Date())
}

func absoluteTime(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: value)
}

func quotaHoverTime(_ value: Date, range: LLMQuotaHistoryRange) -> String {
    if range == .threeDays || range == .sevenDays {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: value)
    }
    return exactClockTime(value)
}

func quotaMilestoneTime(_ value: Date) -> String {
    exactClockTime(value)
}

/// "Tue 4:00 p.m." for times that may be days away.
private func quotaDayTime(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE"
    return "\(formatter.string(from: value)) \(exactClockTime(value))"
}

func exactClockTime(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: value)
        .replacingOccurrences(of: "AM", with: "a.m.")
        .replacingOccurrences(of: "PM", with: "p.m.")
}

func localDrawdownUpdatedAt(_ value: Date?) -> String {
    guard let value else { return "not sampled" }
    return exactClockTime(value)
}

func trimmedText(_ text: String, maxLength: Int) -> String {
    guard text.count > maxLength else { return text }
    let end = text.index(text.startIndex, offsetBy: maxLength - 1)
    return String(text[..<end]) + "..."
}

let codexRunwayHelp = """
Shows your live Codex quota windows from the usage API. The 5h bar is the short runway you feel during heavy work; the weekly bar shows the longer reset cycle, and reset credits appear when the API reports them.
"""

let claudeRunwayHelp = """
Shows your live Claude five-hour and weekly usage windows when Claude Code OAuth is available. Claude Desktop, Claude Code, and claude.ai draw from shared usage limits; local Claude sessions remain visible even when live limits are unavailable.
"""

let limitDrawdownHelp = """
Shows weekly quota remaining over the last 24 hours, 72 hours, or seven days (pick with the toggle): Claude in orange and Codex in blue, for the providers you show. Markers and hover details focus on changes rather than repeated samples. Claude history starts when MaxxBar first records its quota; earlier values are unavailable.
"""

let sessionTimelineHelp = """
Shows recent local Codex sessions in the selected drawdown window, newest first. Bar position is the session time range, thickness roughly follows token volume, and the tooltip gives the full session detail.
"""

let drawdownInsightHelp = """
Summarizes the latest sampled weekly runway drop for your primary provider (Claude when it is shown, otherwise Codex) from the last seven days of local quota history. A plan change starts a new segment, and the pace line only uses samples taken since the last reset or plan change. Exact crossing times are bounded by how often MaxxBar sampled the API.
"""

let maxxInsightsHelp = """
Summarizes local AI activity MaxxBar has observed today: session count, inferred AI time, average session length, the current detected AI surface, and confidence in the context signal.
"""

private let contextConfidenceHelp = """
Context confidence is how much before/after app context MaxxBar has around detected AI use. High means it saw both sides of the workflow often enough to trust the pattern; Medium or Low means the context is sparse or mostly inferred.
"""

let aiFlowHelp = """
Shows lightweight before -> AI -> after patterns from local app and site metadata. It helps answer which tools you use, what usually leads into AI, and where work tends to go afterward.
"""

let topTokenUsersHelp = """
Lists local Codex and Claude sessions by recency or token usage. Use All, Codex, or Claude to isolate a provider while keeping the selected Recent or Highest ordering.
"""

let availableDetailHelp = """
Shows raw limit groups returned by the Codex usage API. This is mostly diagnostic detail for checking additional model-specific limits beyond the main Codex runway.
"""

let advancedHelp = """
Advanced keeps deeper local token/session diagnostics out of the main Runway view. Open it when you need session-level token users, cache estimates, or raw API limit detail.
"""

struct InstantHelpTitle: View {
    let title: String
    let help: String
    var font: Font = .system(size: 13.5, weight: .medium)
    var color: Color = .accentBlue
    var hoverDelay: TimeInterval = 0.65
    @State private var isHoverPresented = false
    @State private var isPinned = false
    @State private var pendingHelpTask: DispatchWorkItem?

    init(
        _ title: String,
        help: String,
        font: Font = .system(size: 13.5, weight: .medium),
        color: Color = .accentBlue,
        hoverDelay: TimeInterval = 0.65
    ) {
        self.title = title
        self.help = help
        self.font = font
        self.color = color
        self.hoverDelay = hoverDelay
    }

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(color)
            .contentShape(Rectangle())
            .onHover(perform: handleHover)
            .onTapGesture {
                pendingHelpTask?.cancel()
                isHoverPresented = false
                isPinned.toggle()
            }
            .popover(
                isPresented: Binding(
                    get: { isHoverPresented || isPinned },
                    set: { newValue in
                        if !newValue {
                            isHoverPresented = false
                            isPinned = false
                        }
                    }
                ),
                arrowEdge: .top
            ) {
                HelpPopoverText(help: help)
            }
    }

    private func handleHover(_ isHovered: Bool) {
        pendingHelpTask?.cancel()
        if isHovered {
            let task = DispatchWorkItem {
                isHoverPresented = true
            }
            pendingHelpTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: task)
        } else {
            isHoverPresented = false
        }
    }
}

struct ImmediateHelpPopover<Content: View>: View {
    let help: String
    @ViewBuilder var content: Content
    @State private var isPresented = false

    var body: some View {
        content
            .contentShape(Rectangle())
            .onHover { isPresented = $0 }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                HelpPopoverText(help: help, width: 210)
            }
    }
}

struct HelpPopoverText: View {
    let help: String
    var width: CGFloat = 270

    var body: some View {
        Text(help)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.white.opacity(0.92))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.background)
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
    static let codexBlue = Color(red: 72 / 255, green: 157 / 255, blue: 255 / 255)
    static let chatGPTGreen = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    static let claudeCoral = Color(red: 224 / 255, green: 129 / 255, blue: 92 / 255)
    static let wiredPink = Color(red: 248 / 255, green: 65 / 255, blue: 151 / 255)
    static let compressedYellow = Color(red: 255 / 255, green: 202 / 255, blue: 18 / 255)
    static let freeGray = Color(red: 104 / 255, green: 111 / 255, blue: 132 / 255)
}
