import AppKit
import SwiftUI

/// The shareable image, laid out at 540 x 675 points and exported at 2x (1080 x 1350, a 4:5 social post).
/// It shows only percentages, counts and dates. No names, accounts, projects, paths or machine details.
struct WeeklyShareCardView: View {
    let summary: WeeklyShareSummary
    var showDollars = false

    static let size = CGSize(width: 540, height: 675)
    private let ink = Color.white
    private let muted = Color.white.opacity(0.56)
    private let track = Color(red: 52 / 255, green: 56 / 255, blue: 74 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 26)
            headline
            Spacer(minLength: 18)
            allowanceBar
            Spacer(minLength: 22)
            if let rescued = summary.rescuedPoints, let baseline = summary.baselineLeftPercent {
                rescuedRow(rescued, baseline: baseline)
                Spacer(minLength: 22)
            }
            dailyBars
            Spacer(minLength: 18)
            statTiles
            Spacer(minLength: 16)
            footer
        }
        .padding(36)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.background)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("MAXXBAR")
                .font(.system(size: 13, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(Color.claudeCoral)
            Spacer()
            Text(periodLabel.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(muted)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(summary.usedPercent)%")
                .font(.system(size: 112, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(summary.inProgress ? "of my Claude plan put to work so far this week" : "of my Claude plan put to work this week")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allowanceBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(track)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.claudeCoral)
                        .frame(width: width * CGFloat(summary.usedPercent) / 100)
                    if let baseline = summary.baselineLeftPercent {
                        // Where a typical recent week finished, for comparison.
                        Rectangle()
                            .fill(ink)
                            .frame(width: 2, height: 22)
                            .offset(x: width * CGFloat(100 - baseline) / 100 - 1)
                    }
                }
            }
            .frame(height: 14)
            HStack(alignment: .firstTextBaseline) {
                Text(leftLabel)
                    .foregroundStyle(muted)
                Spacer()
                if summary.baselineLeftPercent != nil {
                    HStack(spacing: 6) {
                        Rectangle().fill(ink).frame(width: 2, height: 11)
                        Text("my usual week").foregroundStyle(muted)
                    }
                }
            }
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
        }
    }

    private func rescuedRow(_ points: Int, baseline: Int) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text("+\(points)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(Color.claudeCoral)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 3) {
                Text("points of plan rescued")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink)
                Text("My last \(summary.baselineWeeks == 1 ? "week" : "\(summary.baselineWeeks) weeks") left \(baseline)% unused on average")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
    }

    private var dailyBars: some View {
        let peak = max(summary.days.map(\.turns).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("TURNS PER DAY")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(muted)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(summary.days, id: \.date) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(day.turns > 0 ? Color.claudeCoral.opacity(0.85) : track)
                            .frame(height: max(4, 74 * CGFloat(day.turns) / CGFloat(peak)))
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 94, alignment: .bottom)
        }
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            tile(summary.turns.formatted(), "turns")
            tile("\(summary.activeDays) of 7", "days active")
            tile(compactTokens(summary.tokens), "tokens")
            if showDollars {
                tile(summary.apiValueUSD.formatted(.currency(code: "USD").precision(.fractionLength(0))), "API equivalent")
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(footerNote)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(muted)
            Spacer()
            if let plan = summary.plan {
                Text("Claude \(plan)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(muted)
            }
        }
    }

    private var periodLabel: String {
        let resetDay = summary.resetAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return summary.inProgress ? "Week resets \(resetDay)" : "Week ending \(resetDay)"
    }

    private var leftLabel: String {
        summary.inProgress
            ? "\(summary.leftPercent)% still available before the reset"
            : "\(summary.leftPercent)% expired unused at the reset"
    }

    private var footerNote: String {
        if summary.lowConfidence, let minutes = summary.lastReadingMinutesBeforeReset {
            return "Measured locally with MaxxBar. Last reading \(minutes) min before reset."
        }
        return "Measured locally with MaxxBar"
    }

    private func compactTokens(_ value: UInt64) -> String {
        let number = Double(value)
        if number >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
        if number >= 1_000_000 { return String(format: "%.0fM", number / 1_000_000) }
        if number >= 1_000 { return String(format: "%.0fK", number / 1_000) }
        return "\(value)"
    }
}

/// Renders the card to PNG for the clipboard or a file.
@MainActor
enum WeeklyShareCardExporter {
    static func pngData(_ summary: WeeklyShareSummary, showDollars: Bool) -> Data? {
        let renderer = ImageRenderer(content: WeeklyShareCardView(summary: summary, showDollars: showDollars))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    @discardableResult
    static func copy(_ summary: WeeklyShareSummary, showDollars: Bool) -> Bool {
        guard let data = pngData(summary, showDollars: showDollars) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    /// Writes the PNG to ~/Downloads and selects it in Finder.
    static func saveToDownloads(_ summary: WeeklyShareSummary, showDollars: Bool) -> URL? {
        guard let data = pngData(summary, showDollars: showDollars) else { return nil }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let url = folder.appendingPathComponent("maxxbar-week-\(APICostLedger.dayKey(summary.resetAt)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    static func write(_ summary: WeeklyShareSummary, showDollars: Bool, to url: URL) throws {
        guard let data = pngData(summary, showDollars: showDollars) else { throw RenderError.pngEncodingFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

let weeklyShareCardHelp = """
A weekly image for a social post: how much of your Claude plan went to work, what expired at the reset, and how many points you rescued compared with your usual week.

It shows only percentages, counts and dates. No names, accounts, projects, file paths or machine details. The API dollar figure is off unless you switch it on.
"""

/// Runway panel section: preview, copy or save the weekly share card.
struct WeeklyShareCardSection: View {
    let snapshot: LLMUsageSnapshot
    let records: [QuotaWindowRecord]
    @AppStorage("shareCardShowDollars") private var showDollars = false
    @AppStorage("shareCardPeriod") private var periodRaw = WeeklyShareCard.Period.lastFullWeek.rawValue
    @State private var summary: WeeklyShareSummary?
    @State private var previewPresented = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle("SHARE CARD", help: weeklyShareCardHelp, color: .claudeCoral)
                Spacer()
                Picker("", selection: $periodRaw) {
                    Text("Last week").tag(WeeklyShareCard.Period.lastFullWeek.rawValue)
                    Text("So far").tag(WeeklyShareCard.Period.thisWeekSoFar.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 118)
            }

            if let summary {
                Text(summaryLine(summary))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                Toggle("Show API dollar value", isOn: $showDollars)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.62))
                HStack(spacing: 12) {
                    actionButton("Preview") { previewPresented.toggle() }
                        .popover(isPresented: $previewPresented, arrowEdge: .leading) {
                            WeeklyShareCardView(summary: summary, showDollars: showDollars)
                                .scaleEffect(0.6, anchor: .topLeading)
                                .frame(width: WeeklyShareCardView.size.width * 0.6,
                                       height: WeeklyShareCardView.size.height * 0.6, alignment: .topLeading)
                        }
                    actionButton("Copy image") {
                        flash(WeeklyShareCardExporter.copy(summary, showDollars: showDollars) ? "Copied" : "Could not render")
                    }
                    actionButton("Save PNG") {
                        flash(WeeklyShareCardExporter.saveToDownloads(summary, showDollars: showDollars) != nil
                              ? "Saved to Downloads" : "Could not save")
                    }
                    Spacer()
                    if let note {
                        Text(note).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            } else {
                Text("Needs one closed weekly window or a live weekly reading")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .sectionStyle()
        .task(id: refreshKey) { await refresh() }
    }

    private var period: WeeklyShareCard.Period {
        WeeklyShareCard.Period(rawValue: periodRaw) ?? .lastFullWeek
    }

    private var live: WeeklyShareCard.LiveWeek? {
        guard let window = snapshot.limits.first(where: { $0.name == "Claude" })?.weeklyWindow,
              let reset = window.resetAt else { return nil }
        return WeeklyShareCard.LiveWeek(usedPercent: window.usedPercent, resetAt: reset)
    }

    private var refreshKey: String {
        "\(periodRaw)|\(records.count)|\(records.last?.windowResetAt.timeIntervalSince1970 ?? 0)|\(live?.usedPercent ?? -1)"
    }

    private func refresh() async {
        let records = records, live = live, plan = snapshot.claudePlanType, period = period
        let built = await Task.detached(priority: .utility) {
            WeeklyShareCard.summary(records: records, live: live, plan: plan, period: period) {
                APICostLedger.days(provider: "Claude", from: $0, through: $1)
            }
        }.value
        summary = built
    }

    private func summaryLine(_ summary: WeeklyShareSummary) -> String {
        var line = summary.inProgress
            ? "\(summary.usedPercent)% put to work so far"
            : "\(summary.usedPercent)% put to work, \(summary.leftPercent)% expired"
        if let rescued = summary.rescuedPoints { line += ", +\(rescued) rescued" }
        return line
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.claudeCoral)
    }

    private func flash(_ text: String) {
        note = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if note == text { note = nil }
        }
    }
}
