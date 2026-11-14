import Foundation

/// Keeps the append-only logs to their last 30 days. Older lines are not deleted: they move, in order, to
/// `archive/<same name>` next to the logs, so nothing is lost until the archive is removed by hand.
/// Runs at most once a day, on a background queue.
enum LogRetention {
    static let keepDays = 30
    private static let lastRunKey = "logRetentionLastRun"
    /// File name and the JSON key holding each line's timestamp.
    private static let logs: [(name: String, timeKey: String)] = [
        ("ai-activity.jsonl", "ts"),
        ("ai-transfers.jsonl", "ts"),
        ("clipboard-metadata.jsonl", "ts"),
        ("llm-5h-usage-windows.jsonl", "recordedAt")
    ]

    private static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/MaxxBar")
    }

    static func runIfDue(now: Date = Date()) {
        if let last = UserDefaults.standard.object(forKey: lastRunKey) as? Date, now.timeIntervalSince(last) < 86_400 {
            return
        }
        UserDefaults.standard.set(now, forKey: lastRunKey)
        DispatchQueue.global(qos: .background).async {
            let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
            for log in logs {
                trim(directory.appendingPathComponent(log.name), timeKey: log.timeKey, cutoff: cutoff)
            }
        }
    }

    /// Lines are written in time order, so everything before the first recent line is old.
    static func trim(_ url: URL, timeKey: String, cutoff: Date, archiveDirectory: URL? = nil) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let split = firstRecentOffset(handle, timeKey: timeKey, cutoff: cutoff), split > 0 else { return }

        let archiveDirectory = archiveDirectory ?? url.deletingLastPathComponent().appendingPathComponent("archive")
        let archiveURL = archiveDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: archiveURL.path) {
                FileManager.default.createFile(atPath: archiveURL.path, contents: nil)
            }
            let archive = try FileHandle(forWritingTo: archiveURL)
            defer { try? archive.close() }
            try archive.seekToEnd()
            try handle.seek(toOffset: 0)
            var copied: UInt64 = 0
            while copied < split {
                let count = Int(min(UInt64(1 << 20), split - copied))
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
                try archive.write(contentsOf: chunk)
                copied += UInt64(chunk.count)
            }
            guard copied == split else { return }

            try handle.seek(toOffset: split)
            var recent = try handle.readToEnd() ?? Data()
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).trim")
            try recent.write(to: temporary)
            // A line appended while this ran is carried over before the swap.
            let endOffset = split + UInt64(recent.count)
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? UInt64, size > endOffset {
                try handle.seek(toOffset: endOffset)
                recent = try handle.readToEnd() ?? Data()
                let temporaryHandle = try FileHandle(forWritingTo: temporary)
                try temporaryHandle.seekToEnd()
                try temporaryHandle.write(contentsOf: recent)
                try temporaryHandle.close()
            }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            // Best effort: the log stays as it was.
        }
    }

    /// Byte offset of the first line whose timestamp is at or after the cutoff, or the end of the file.
    private static func firstRecentOffset(_ handle: FileHandle, timeKey: String, cutoff: Date) -> UInt64? {
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let marker = Data("\"\(timeKey)\":\"".utf8)
        var offset: UInt64 = 0
        var carry = Data()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            var buffer = carry
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                let line = buffer[lineStart..<newline]
                if let range = line.range(of: marker),
                   let end = line[range.upperBound...].firstIndex(of: UInt8(ascii: "\"")),
                   let text = String(data: line[range.upperBound..<end], encoding: .utf8),
                   let date = formatter.date(from: text) ?? fractional.date(from: text),
                   date >= cutoff {
                    return offset + UInt64(lineStart - buffer.startIndex)
                }
                lineStart = newline + 1
            }
            offset += UInt64(lineStart - buffer.startIndex)
            carry = Data(buffer[lineStart...])
        }
        return offset
    }
}
