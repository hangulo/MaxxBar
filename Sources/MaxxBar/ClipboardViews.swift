import AppKit
import SwiftUI

private enum ClipboardPanelSection: String, CaseIterable, Identifiable {
    case queue = "Queue"
    case insights = "Insights"

    var id: String { rawValue }
}

struct ClipboardPanelView: View {
    let snapshot: ClipboardDebugSnapshot
    @State private var section = ClipboardPanelSection.queue

    var body: some View {
        VStack(spacing: 7) {
            VStack(spacing: 7) {
                HStack {
                    Text("CLIPBOARD")
                        .sectionTitle()
                    Spacer()
                    Text("Images saved 24h")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                }

                HStack(spacing: 3) {
                    ForEach(ClipboardPanelSection.allCases) { item in
                        Button {
                            section = item
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .foregroundStyle(section == item ? .white : .white.opacity(0.6))
                                .background(section == item ? Color.panelLift : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.background.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(12)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            if section == .queue {
                clipboardQueue
            } else {
                clipboardInsights
            }
        }
    }

    private var clipboardQueue: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                clipboardMetric("Writes", value: snapshot.writesToday)
                clipboardMetric("Pastes", value: snapshot.pasteAttemptsToday)
                clipboardMetric("Images", value: snapshot.imageWritesToday)
                clipboardMetric("Known", value: snapshot.pasteSourceKnownPercent, suffix: "%")
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    if snapshot.events.isEmpty {
                        Text("The next clipboard change will appear here.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        ForEach(Array(snapshot.events.prefix(60))) { event in
                            clipboardEventRow(
                                event,
                                isCurrent: (event.kind == .clipboardWrite || event.kind == .clipboardState)
                                    && event.id == snapshot.currentClipboardWrite?.id
                            )
                        }
                    }
                }
            }
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var clipboardInsights: some View {
        ScrollView {
            VStack(spacing: 7) {
                clipboardInsightNote
                providerCard(snapshot.providerSummary("Claude"), color: .claudeCoral)
                providerCard(snapshot.providerSummary("Codex"), color: .codexBlue)
            }
        }
    }

    private var clipboardInsightNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WHAT MAXXBAR CAN SEE")
                .sectionTitle()
            Text("Writes include keyboard shortcuts, menus, Copy buttons, and screenshots. Paste attempts currently mean observed ⌘V. macOS does not expose a general event when an app reads the clipboard.")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Text("Copied images are stored locally for up to 24 hours (100 images / 250 MB). Text and other clipboard payloads are never stored.")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func clipboardMetric(_ label: String, value: Int, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(value)\(suffix)")
                .font(.system(size: 17, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func clipboardEventRow(_ event: ClipboardDebugEvent, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: eventIcon(event))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(eventColor(event))
                .frame(width: 18, height: 18)
                .background(eventColor(event).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if isCurrent {
                        Text("CURRENT CLIPBOARD")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.accentBlue)
                    } else {
                        Text(eventTitle(event))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    Spacer()
                    Text(event.ts, style: .relative)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.42))
                }

                HStack(spacing: 4) {
                    Text(event.context.label)
                        .font(.system(size: 11, weight: .semibold))
                    if !event.contentKinds.isEmpty {
                        Text("· \(event.contentKinds.joined(separator: ", "))")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                Text(eventDetail(event))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
            }

            clipboardImageThumbnail(event)
        }
        .padding(9)
        .background(isCurrent ? Color.accentBlue.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isCurrent ? Color.accentBlue.opacity(0.45) : Color.white.opacity(0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(event.typeIdentifiers.isEmpty ? "No clipboard type metadata" : event.typeIdentifiers.joined(separator: "\n"))
    }

    @ViewBuilder
    private func clipboardImageThumbnail(_ event: ClipboardDebugEvent) -> some View {
        if let thumbnailPath = event.imageThumbnailPath,
           let imagePath = event.imagePath,
           FileManager.default.fileExists(atPath: imagePath),
           let image = NSImage(contentsOfFile: thumbnailPath) {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: imagePath))
            } label: {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                    }
            }
            .buttonStyle(.plain)
            .help("Open saved image\n\(imagePath)")
            .accessibilityLabel("Open copied image")
        }
    }

    private func providerCard(_ summary: ClipboardProviderDebugSummary, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(summary.provider.uppercased())
                    .sectionTitle()
                Spacer()
            }

            HStack(spacing: 6) {
                providerMetric(
                    "Into \(summary.provider)",
                    value: "\(summary.inboundPasteAttempts)",
                    detail: "\(summary.inboundKnownPercent)% source known"
                )
                providerMetric(
                    "Out of \(summary.provider)",
                    value: "\(summary.outboundWrites)",
                    detail: "\(summary.outboundTracedPercent)% destination traced"
                )
            }

            flowLine("From", counters: summary.topInboundSources)
            flowLine("To", counters: summary.topOutboundDestinations)
        }
        .padding(12)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func providerMetric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
            Text(value)
                .font(.system(size: 18, weight: .semibold))
            Text(detail)
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.background.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func flowLine(_ label: String, counters: [ClipboardDebugCounter]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 28, alignment: .leading)
            Text(counters.prefix(3).map { "\($0.label) \($0.count)×" }.joined(separator: "  ·  ").nonEmpty ?? "Unknown")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func eventTitle(_ event: ClipboardDebugEvent) -> String {
        switch event.kind {
        case .clipboardState: return "Clipboard at launch"
        case .clipboardWrite: return "Clipboard history"
        case .copyShortcut: return "Copy shortcut"
        case .pasteAttempt: return "Paste attempt"
        }
    }

    private func eventIcon(_ event: ClipboardDebugEvent) -> String {
        switch event.kind {
        case .clipboardState: return event.contentKinds.contains("Image") ? "photo" : "doc.on.clipboard"
        case .clipboardWrite: return event.contentKinds.contains("Image") ? "photo" : "doc.on.clipboard"
        case .copyShortcut: return "keyboard"
        case .pasteAttempt: return "arrow.down.doc"
        }
    }

    private func eventColor(_ event: ClipboardDebugEvent) -> Color {
        if event.context.provider == "Claude" { return .claudeCoral }
        if event.context.provider == "Codex" { return .codexBlue }
        return .accentBlue
    }

    private func eventDetail(_ event: ClipboardDebugEvent) -> String {
        if event.kind == .pasteAttempt {
            if let source = event.sourceContext?.label, let age = event.sourceAgeSeconds {
                return "From \(source) · \(age)s after clipboard changed"
            }
            return "Source unknown"
        }
        if event.kind == .copyShortcut {
            return "Shortcut observed; waiting for clipboard change"
        }
        if event.kind == .clipboardState {
            return "Present when MaxxBar started · origin unknown"
        }
        if let imagePath = event.imagePath {
            return FileManager.default.fileExists(atPath: imagePath)
                ? "Saved locally for 24h · Click thumbnail to open"
                : "Saved image expired · metadata retained"
        }
        return "Change #\(event.changeCount ?? 0) · \(event.itemCount ?? 0) item(s) · \(event.typeIdentifiers.count) type(s)"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
