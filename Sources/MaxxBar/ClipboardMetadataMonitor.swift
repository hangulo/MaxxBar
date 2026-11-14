import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardImagePayload: Sendable {
    let data: Data
    let typeIdentifier: String
}

struct ClipboardStoredImage: Sendable {
    let imagePath: String
    let thumbnailPath: String
}

struct ClipboardDebugContext: Codable, Equatable {
    let app: String
    let bundleID: String
    let site: String?
    let tool: String?
    let surface: String?
    let provider: String?

    var label: String {
        surface ?? tool ?? site ?? app
    }
}

enum ClipboardDebugEventKind: String, Codable {
    case clipboardState
    case clipboardWrite
    case copyShortcut
    case pasteAttempt
}

struct ClipboardDebugEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    let ts: Date
    let kind: ClipboardDebugEventKind
    let context: ClipboardDebugContext
    let changeCount: Int?
    let itemCount: Int?
    let typeIdentifiers: [String]
    let contentKinds: [String]
    let sourceEventID: UUID?
    let sourceContext: ClipboardDebugContext?
    let sourceTS: Date?
    let sourceAgeSeconds: Int?
    let imagePath: String?
    let imageThumbnailPath: String?
    let privacy: String
}

struct ClipboardDebugCounter: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let count: Int
}

struct ClipboardProviderDebugSummary: Identifiable, Equatable {
    var id: String { provider }
    let provider: String
    let inboundPasteAttempts: Int
    let knownInboundSources: Int
    let outboundWrites: Int
    let tracedOutboundWrites: Int
    let topInboundSources: [ClipboardDebugCounter]
    let topOutboundDestinations: [ClipboardDebugCounter]

    var inboundKnownPercent: Int {
        guard inboundPasteAttempts > 0 else { return 0 }
        return Int((Double(knownInboundSources) / Double(inboundPasteAttempts) * 100).rounded())
    }

    var outboundTracedPercent: Int {
        guard outboundWrites > 0 else { return 0 }
        return Int((Double(tracedOutboundWrites) / Double(outboundWrites) * 100).rounded())
    }
}

struct ClipboardDebugSnapshot: Equatable {
    let events: [ClipboardDebugEvent]

    var currentClipboardWrite: ClipboardDebugEvent? {
        events.first { $0.kind == .clipboardWrite || $0.kind == .clipboardState }
    }

    var eventsToday: [ClipboardDebugEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        return events.filter { $0.ts >= start }
    }

    var writesToday: Int {
        eventsToday.filter { $0.kind == .clipboardWrite }.count
    }

    var pasteAttemptsToday: Int {
        eventsToday.filter { $0.kind == .pasteAttempt }.count
    }

    var imageWritesToday: Int {
        eventsToday.filter {
            $0.kind == .clipboardWrite && $0.contentKinds.contains("Image")
        }.count
    }

    var knownPasteSourcesToday: Int {
        eventsToday.filter {
            $0.kind == .pasteAttempt && $0.sourceContext != nil
        }.count
    }

    var pasteSourceKnownPercent: Int {
        guard pasteAttemptsToday > 0 else { return 0 }
        return Int((Double(knownPasteSourcesToday) / Double(pasteAttemptsToday) * 100).rounded())
    }

    func providerSummary(_ provider: String) -> ClipboardProviderDebugSummary {
        let normalized = provider.lowercased()
        let inbound = eventsToday.filter {
            $0.kind == .pasteAttempt && $0.context.provider?.lowercased() == normalized
        }
        let outbound = eventsToday.filter {
            $0.kind == .clipboardWrite && $0.context.provider?.lowercased() == normalized
        }
        let outboundIDs = Set(outbound.map(\.id))
        let tracedOutboundIDs = Set(
            eventsToday.compactMap { event -> UUID? in
                guard event.kind == .pasteAttempt,
                      let sourceEventID = event.sourceEventID,
                      outboundIDs.contains(sourceEventID) else {
                    return nil
                }
                return sourceEventID
            }
        )
        let sources = counters(inbound.compactMap { $0.sourceContext?.label })
        let destinations = counters(
            eventsToday.compactMap { event -> String? in
                guard event.kind == .pasteAttempt,
                      let sourceEventID = event.sourceEventID,
                      outboundIDs.contains(sourceEventID) else {
                    return nil
                }
                return event.context.label
            }
        )

        return ClipboardProviderDebugSummary(
            provider: provider,
            inboundPasteAttempts: inbound.count,
            knownInboundSources: inbound.filter { $0.sourceContext != nil }.count,
            outboundWrites: outbound.count,
            tracedOutboundWrites: tracedOutboundIDs.count,
            topInboundSources: sources,
            topOutboundDestinations: destinations
        )
    }

    private func counters(_ labels: [String]) -> [ClipboardDebugCounter] {
        Dictionary(grouping: labels, by: { $0 })
            .map { ClipboardDebugCounter(label: $0.key, count: $0.value.count) }
            .sorted {
                $0.count == $1.count
                    ? $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                    : $0.count > $1.count
            }
    }

    static let empty = ClipboardDebugSnapshot(events: [])

    static let demo = ClipboardDebugSnapshot(
        events: [
            ClipboardDebugEvent(
                ts: Date().addingTimeInterval(-40),
                kind: .clipboardWrite,
                context: ClipboardDebugContext(
                    app: "Claude",
                    bundleID: "com.anthropic.claudefordesktop",
                    site: nil,
                    tool: "Claude",
                    surface: "Claude client",
                    provider: "Claude"
                ),
                changeCount: 418,
                itemCount: 1,
                typeIdentifiers: ["public.tiff", "public.png"],
                contentKinds: ["Image"],
                sourceEventID: nil,
                sourceContext: nil,
                sourceTS: nil,
                sourceAgeSeconds: nil,
                imagePath: nil,
                imageThumbnailPath: nil,
                privacy: "metadata_only"
            ),
            ClipboardDebugEvent(
                ts: Date().addingTimeInterval(-25),
                kind: .pasteAttempt,
                context: ClipboardDebugContext(
                    app: "Slack",
                    bundleID: "com.tinyspeck.slackmacgap",
                    site: nil,
                    tool: nil,
                    surface: "Slack",
                    provider: nil
                ),
                changeCount: 418,
                itemCount: 1,
                typeIdentifiers: ["public.tiff", "public.png"],
                contentKinds: ["Image"],
                sourceEventID: nil,
                sourceContext: ClipboardDebugContext(
                    app: "Claude",
                    bundleID: "com.anthropic.claudefordesktop",
                    site: nil,
                    tool: "Claude",
                    surface: "Claude client",
                    provider: "Claude"
                ),
                sourceTS: Date().addingTimeInterval(-40),
                sourceAgeSeconds: 15,
                imagePath: nil,
                imageThumbnailPath: nil,
                privacy: "metadata_only"
            ),
            ClipboardDebugEvent(
                ts: Date().addingTimeInterval(-8),
                kind: .pasteAttempt,
                context: ClipboardDebugContext(
                    app: "Claude",
                    bundleID: "com.anthropic.claudefordesktop",
                    site: nil,
                    tool: "Claude",
                    surface: "Claude client",
                    provider: "Claude"
                ),
                changeCount: nil,
                itemCount: nil,
                typeIdentifiers: [],
                contentKinds: [],
                sourceEventID: nil,
                sourceContext: nil,
                sourceTS: nil,
                sourceAgeSeconds: nil,
                imagePath: nil,
                imageThumbnailPath: nil,
                privacy: "metadata_only"
            )
        ]
    )
}

@MainActor
final class ClipboardMetadataMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int?
    private var onChange: ((
        _ changeCount: Int,
        _ itemCount: Int,
        _ typeIdentifiers: [String],
        _ observedChange: Bool,
        _ imagePayload: ClipboardImagePayload?
    ) -> Void)?

    func start(onChange: @escaping (
        _ changeCount: Int,
        _ itemCount: Int,
        _ typeIdentifiers: [String],
        _ observedChange: Bool,
        _ imagePayload: ClipboardImagePayload?
    ) -> Void) {
        guard timer == nil else { return }
        self.onChange = onChange
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        let items = pasteboard.pasteboardItems ?? []
        let types = Set(items.flatMap { $0.types.map(\.rawValue) })
        onChange(pasteboard.changeCount, items.count, types.sorted(), false, nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        timer?.tolerance = 0.08
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastChangeCount = nil
        onChange = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        let items = pasteboard.pasteboardItems ?? []
        let types = Set(items.flatMap { $0.types.map(\.rawValue) })
        let imagePayload = Self.imagePayload(from: pasteboard)
        onChange?(current, items.count, types.sorted(), true, imagePayload)
    }

    private static func imagePayload(from pasteboard: NSPasteboard) -> ClipboardImagePayload? {
        let preferredTypes = [
            NSPasteboard.PasteboardType.png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType.tiff
        ]
        for type in preferredTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return ClipboardImagePayload(data: data, typeIdentifier: type.rawValue)
            }
        }

        let declaredTypes = pasteboard.types?.map { $0.rawValue.lowercased() } ?? []
        guard declaredTypes.contains(where: {
            $0.contains("image")
                || $0.contains("png")
                || $0.contains("jpeg")
                || $0.contains("tiff")
                || $0.contains("file-url")
        }) else {
            return nil
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let data = image.tiffRepresentation,
              !data.isEmpty else {
            return nil
        }
        return ClipboardImagePayload(data: data, typeIdentifier: NSPasteboard.PasteboardType.tiff.rawValue)
    }
}

enum ClipboardImageStore {
    private static let retentionInterval: TimeInterval = 24 * 60 * 60
    private static let maximumImageCount = 100
    private static let maximumStoredBytes: Int64 = 250 * 1_024 * 1_024
    private static let thumbnailMaxPixelSize = 240

    static func save(_ payload: ClipboardImagePayload, changeCount: Int) -> ClipboardStoredImage? {
        guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil),
              let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let directory = imageDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let stem = "clipboard-\(Int(Date().timeIntervalSince1970 * 1_000))-\(changeCount)-\(UUID().uuidString)"
        let imageURL = directory.appendingPathComponent("\(stem)-full.png")
        let thumbnailURL = directory.appendingPathComponent("\(stem)-thumb.png")
        guard writePNG(fullImage, to: imageURL),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
                ] as CFDictionary
              ),
              writePNG(thumbnail, to: thumbnailURL) else {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
            return nil
        }

        cleanup(directory: directory)
        guard FileManager.default.fileExists(atPath: imageURL.path),
              FileManager.default.fileExists(atPath: thumbnailURL.path) else {
            return nil
        }
        return ClipboardStoredImage(imagePath: imageURL.path, thumbnailPath: thumbnailURL.path)
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func cleanup(directory: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let fullImages = files
            .filter { $0.lastPathComponent.hasSuffix("-full.png") }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

        let cutoff = Date().addingTimeInterval(-retentionInterval)
        var retainedBytes: Int64 = 0
        for (index, imageURL) in fullImages.enumerated() {
            let thumbnailURL = thumbnailURL(for: imageURL)
            let imageValues = try? imageURL.resourceValues(forKeys: keys)
            let thumbnailValues = try? thumbnailURL.resourceValues(forKeys: keys)
            let pairBytes = Int64(imageValues?.fileSize ?? 0) + Int64(thumbnailValues?.fileSize ?? 0)
            let modifiedAt = imageValues?.contentModificationDate ?? .distantPast
            let shouldRemove = modifiedAt < cutoff
                || index >= maximumImageCount
                || retainedBytes + pairBytes > maximumStoredBytes

            if shouldRemove {
                try? FileManager.default.removeItem(at: imageURL)
                try? FileManager.default.removeItem(at: thumbnailURL)
            } else {
                retainedBytes += pairBytes
            }
        }

        for thumbnailURL in files where thumbnailURL.lastPathComponent.hasSuffix("-thumb.png") {
            let fullURL = fullImageURL(for: thumbnailURL)
            if !FileManager.default.fileExists(atPath: fullURL.path) {
                try? FileManager.default.removeItem(at: thumbnailURL)
            }
        }
    }

    private static func thumbnailURL(for imageURL: URL) -> URL {
        imageURL
            .deletingLastPathComponent()
            .appendingPathComponent(imageURL.lastPathComponent.replacingOccurrences(of: "-full.png", with: "-thumb.png"))
    }

    private static func fullImageURL(for thumbnailURL: URL) -> URL {
        thumbnailURL
            .deletingLastPathComponent()
            .appendingPathComponent(thumbnailURL.lastPathComponent.replacingOccurrences(of: "-thumb.png", with: "-full.png"))
    }

    private static var imageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MaxxBar", isDirectory: true)
            .appendingPathComponent("clipboard-images", isDirectory: true)
    }
}

enum ClipboardDebugReader {
    nonisolated(unsafe) private static var latestWrite: ClipboardDebugEvent?
    private static let lock = NSLock()
    private static let sourceWindow: TimeInterval = 15 * 60

    static func snapshot() -> ClipboardDebugSnapshot {
        ClipboardDebugSnapshot(events: readRecentEvents())
    }

    static func recordWrite(
        changeCount: Int,
        itemCount: Int,
        typeIdentifiers: [String],
        storedImage: ClipboardStoredImage?
    ) -> ClipboardDebugSnapshot {
        let context = AIUsageReader.currentClipboardDebugContext()
        let event = ClipboardDebugEvent(
            ts: Date(),
            kind: .clipboardWrite,
            context: context,
            changeCount: changeCount,
            itemCount: itemCount,
            typeIdentifiers: typeIdentifiers,
            contentKinds: contentKinds(for: typeIdentifiers),
            sourceEventID: nil,
            sourceContext: nil,
            sourceTS: nil,
            sourceAgeSeconds: nil,
            imagePath: storedImage?.imagePath,
            imageThumbnailPath: storedImage?.thumbnailPath,
            privacy: storedImage == nil ? "metadata_only" : "image_payload_local_24h"
        )
        lock.lock()
        latestWrite = event
        append(event)
        lock.unlock()
        return snapshot()
    }

    static func recordCurrentState(
        changeCount: Int,
        itemCount: Int,
        typeIdentifiers: [String]
    ) -> ClipboardDebugSnapshot {
        let event = ClipboardDebugEvent(
            ts: Date(),
            kind: .clipboardState,
            context: ClipboardDebugContext(
                app: "Unknown origin",
                bundleID: "",
                site: nil,
                tool: nil,
                surface: nil,
                provider: nil
            ),
            changeCount: changeCount,
            itemCount: itemCount,
            typeIdentifiers: typeIdentifiers,
            contentKinds: contentKinds(for: typeIdentifiers),
            sourceEventID: nil,
            sourceContext: nil,
            sourceTS: nil,
            sourceAgeSeconds: nil,
            imagePath: nil,
            imageThumbnailPath: nil,
            privacy: "metadata_only"
        )
        lock.lock()
        latestWrite = event
        append(event)
        lock.unlock()
        return snapshot()
    }

    static func recordShortcut(_ eventType: String) -> ClipboardDebugSnapshot {
        let now = Date()
        let kind: ClipboardDebugEventKind = eventType == "paste" ? .pasteAttempt : .copyShortcut
        let source: ClipboardDebugEvent?
        lock.lock()
        if latestWrite == nil {
            latestWrite = readRecentEvents().first(where: { $0.kind == .clipboardWrite })
        }
        if kind == .pasteAttempt,
           let candidate = latestWrite,
           now.timeIntervalSince(candidate.ts) >= 0,
           now.timeIntervalSince(candidate.ts) <= sourceWindow {
            source = candidate
        } else {
            source = nil
        }
        let event = ClipboardDebugEvent(
            ts: now,
            kind: kind,
            context: AIUsageReader.currentClipboardDebugContext(),
            changeCount: source?.changeCount,
            itemCount: source?.itemCount,
            typeIdentifiers: source?.typeIdentifiers ?? [],
            contentKinds: source?.contentKinds ?? [],
            sourceEventID: source?.id,
            sourceContext: source?.kind == .clipboardState ? nil : source?.context,
            sourceTS: source?.ts,
            sourceAgeSeconds: source.map { Int(now.timeIntervalSince($0.ts).rounded()) },
            imagePath: nil,
            imageThumbnailPath: nil,
            privacy: "metadata_only"
        )
        append(event)
        lock.unlock()
        return snapshot()
    }

    private static func contentKinds(for types: [String]) -> [String] {
        let values = types.map { $0.lowercased() }
        var kinds: [String] = []
        if values.contains(where: { $0.contains("png") || $0.contains("tiff") || $0.contains("jpeg") || $0.contains("image") }) {
            kinds.append("Image")
        }
        if values.contains(where: { $0.contains("file-url") || $0.contains("filenames") }) {
            kinds.append("Files")
        }
        if values.contains(where: { $0.contains("pdf") }) {
            kinds.append("PDF")
        }
        if values.contains(where: { $0.contains("url") && !$0.contains("file-url") }) {
            kinds.append("URL")
        }
        if values.contains(where: { $0.contains("text") || $0.contains("string") || $0.contains("utf8") }) {
            kinds.append("Text")
        }
        if values.contains(where: { $0.contains("html") || $0.contains("rtf") }) {
            kinds.append("Rich text")
        }
        return kinds.isEmpty ? ["Other"] : kinds
    }

    private static func readRecentEvents() -> [ClipboardDebugEvent] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> ClipboardDebugEvent? in
                guard let data = String(line).data(using: .utf8),
                      let event = try? decoder.decode(ClipboardDebugEvent.self, from: data),
                      event.ts >= cutoff else {
                    return nil
                }
                return event
            }
            .sorted { $0.ts > $1.ts }
            .prefix(250)
            .map { $0 }
    }

    private static func append(_ event: ClipboardDebugEvent) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(event) else { return }
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        } catch {
            return
        }
    }

    private static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("MaxxBar", isDirectory: true)
            .appendingPathComponent("clipboard-metadata.jsonl")
    }
}
