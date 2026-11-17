import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

extension MemoryModel {
    nonisolated(unsafe) private static var lastLoggedFiveHourEntry: LLMUsageWindowLogEntry?

    /// Appends a line only when the window's numbers changed; before this, about 90% of lines repeated the previous one.
    /// Called from one background refresh at a time (guarded by isRefreshingLLMUsage).
    nonisolated static func logFiveHourUsageWindow(from usage: LLMUsageSnapshot) {
        guard let estimate = usage.costEstimates.first(where: { $0.label.lowercased() == "5h" }),
              let url = fiveHourUsageLogURL else {
            return
        }
        let entry = LLMUsageWindowLogEntry(provider: "Codex", estimate: estimate)
        var comparable = entry
        comparable.recordedAt = lastLoggedFiveHourEntry?.recordedAt ?? entry.recordedAt
        guard comparable != lastLoggedFiveHourEntry, let line = logLine(for: entry) else { return }
        lastLoggedFiveHourEntry = entry

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            handle.write(line)
        } catch {
            // The app should never block live stats because the usage log could not be written.
        }
    }

    nonisolated private static func logLine(for entry: LLMUsageWindowLogEntry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return nil }
        data.append(0x0A)
        return data
    }
}
