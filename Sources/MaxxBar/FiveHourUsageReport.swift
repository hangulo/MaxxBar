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

    static func writeFiveHourUsageReport() throws {
        guard let reportURL = fiveHourUsageReportURL,
              let logURL = fiveHourUsageLogURL else {
            return
        }

        let entries = readFiveHourUsageLog(from: logURL)
        let html = fiveHourUsageHTML(entries: entries, rawLogURL: logURL)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try html.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private static func readFiveHourUsageLog(from url: URL) -> [LLMUsageWindowLogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(LLMUsageWindowLogEntry.self, from: data)
            }
            .sorted { $0.windowEndedAt > $1.windowEndedAt }
    }

    private static func fiveHourUsageHTML(entries: [LLMUsageWindowLogEntry], rawLogURL: URL) -> String {
        let latest = entries.first
        let rows = entries.map { entry in
            """
            <tr>
              <td>\(html(entry.windowLabel))</td>
              <td>\(html(dateRange(entry.windowStartedAt, entry.windowEndedAt)))</td>
              <td>\(html(dateTime(entry.recordedAt)))</td>
              <td class="num">\(entry.sessionCount)</td>
              <td class="num">\(tokenString(entry.freshInputTokens))</td>
              <td class="num">\(tokenString(entry.cachedInputTokens))</td>
              <td class="num">\(tokenString(entry.outputTokens))</td>
              <td class="num">\(tokenString(entry.totalTokens))</td>
              <td class="num">\(entry.cacheHitPercent)%</td>
              <td class="num">\(dollarString(entry.estimatedCostUSD))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let latestCards = latest.map { entry in
            """
            <section class="summary">
              <div><span>Window</span><strong>\(html(dateRange(entry.windowStartedAt, entry.windowEndedAt)))</strong></div>
              <div><span>API Est.</span><strong>\(dollarString(entry.estimatedCostUSD))</strong></div>
              <div><span>Cache Hit</span><strong>\(entry.cacheHitPercent)%</strong></div>
              <div><span>Fresh Input</span><strong>\(tokenString(entry.freshInputTokens))</strong></div>
              <div><span>Cached Input</span><strong>\(tokenString(entry.cachedInputTokens))</strong></div>
              <div><span>Output</span><strong>\(tokenString(entry.outputTokens))</strong></div>
            </section>
            """
        } ?? """
        <section class="empty">No 5h usage samples have been recorded yet.</section>
        """

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>MaxxBar Codex 5h Usage Log</title>
          <style>
            :root { color-scheme: dark; --bg:#161922; --panel:#222638; --panel2:#2b3050; --text:#f7f7fb; --muted:#a8abb8; --blue:#0a84ff; --yellow:#ffcc24; }
            body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; background:var(--bg); color:var(--text); }
            main { max-width:1120px; margin:0 auto; padding:28px; }
            h1 { margin:0 0 6px; font-size:28px; color:var(--blue); }
            p { margin:0 0 20px; color:var(--muted); }
            .summary { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:10px; margin:18px 0 20px; }
            .summary div, .empty { background:var(--panel); border-radius:8px; padding:12px 14px; }
            .summary span { display:block; color:var(--muted); font-size:12px; font-weight:650; text-transform:uppercase; letter-spacing:.02em; }
            .summary strong { display:block; margin-top:5px; font-size:22px; }
            table { width:100%; border-collapse:collapse; background:var(--panel); border-radius:8px; overflow:hidden; }
            th, td { padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.07); text-align:left; white-space:nowrap; }
            th { color:var(--blue); font-size:12px; text-transform:uppercase; letter-spacing:.03em; background:var(--panel2); }
            td { color:rgba(247,247,251,.9); font-size:14px; }
            .num { text-align:right; font-variant-numeric:tabular-nums; }
            a { color:var(--blue); }
            footer { margin-top:16px; color:var(--muted); font-size:12px; }
          </style>
        </head>
        <body>
          <main>
            <h1>Codex 5h Usage Log</h1>
            <p>API-equivalent estimate using fresh input, cached input, and output token pricing. Subscription usage may not map directly to API billing.</p>
            \(latestCards)
            <table>
              <thead>
                <tr>
                  <th>Window</th>
                  <th>Start-End</th>
                  <th>Recorded</th>
                  <th class="num">Sessions</th>
                  <th class="num">Fresh</th>
                  <th class="num">Cached</th>
                  <th class="num">Output</th>
                  <th class="num">Total</th>
                  <th class="num">Cache</th>
                  <th class="num">API Est.</th>
                </tr>
              </thead>
              <tbody>
                \(rows)
              </tbody>
            </table>
            <footer>Raw JSONL: <a href="file://\(html(rawLogURL.path))">\(html(rawLogURL.path))</a></footer>
          </main>
        </body>
        </html>
        """
    }

    private static func tokenString(_ value: UInt64) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private static func dollarString(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "$%.0f", value)
        }
        if value >= 10 {
            return String(format: "$%.1f", value)
        }
        return String(format: "$%.2f", value)
    }

    private static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private static func dateRange(_ start: Date, _ end: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "MMM d, h:mm a"
            let startText = formatter.string(from: start)
            formatter.dateFormat = "h:mm a"
            return "\(startText)-\(formatter.string(from: end))"
        }

        formatter.dateFormat = "MMM d, h:mm a"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }

    private static func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
