import Foundation

/// Appends one metadata line to clipboard-metadata.jsonl per Command-C or Command-V. Tracework reads this
/// file for its opt-in clipboard review, so the line format matches what earlier builds wrote. The file is
/// only appended to, never reread; clipboard contents are never read.
struct ClipboardDebugContext: Codable, Equatable {
    let app: String
    let bundleID: String
    let site: String?
    let tool: String?
    let surface: String?
    let provider: String?
}

enum ClipboardDebugEventKind: String, Codable {
    case clipboardState
    case clipboardWrite
    case copyShortcut
    case pasteAttempt
}

struct ClipboardDebugEvent: Codable, Equatable {
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

enum ClipboardMetadataLog {
    private static let lock = NSLock()

    static func recordShortcut(_ eventType: String, context: ClipboardDebugContext, at now: Date = Date()) {
        let event = ClipboardDebugEvent(
            ts: now,
            kind: eventType == "paste" ? .pasteAttempt : .copyShortcut,
            context: context,
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private static var logURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/clipboard-metadata.jsonl")
    }
}
