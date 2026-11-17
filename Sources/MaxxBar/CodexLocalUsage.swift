import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

extension LLMUsageReader {
    static func readLocalCodexUsage() -> LocalProviderUsage {
        let databasePath = "\(NSHomeDirectory())/.codex/state_5.sqlite"
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return .empty
        }

        let windows = [
            localWindow(databasePath: databasePath, label: "1h", seconds: 3_600),
            localWindow(databasePath: databasePath, label: "5h", seconds: 18_000),
            localWindow(databasePath: databasePath, label: "24h", seconds: 86_400),
            localWindow(databasePath: databasePath, label: "7d", seconds: 604_800)
        ]
        let fiveHour = windows.first(where: { $0.label == "5h" }) ?? LLMLocalUsageWindow(label: "5h", tokens: 0, threads: 0)
        let weekly = windows.first(where: { $0.label == "7d" }) ?? LLMLocalUsageWindow(label: "7d", tokens: 0, threads: 0)

        return LocalProviderUsage(
            fiveHourTokens: fiveHour.tokens,
            weeklyTokens: weekly.tokens,
            weeklyThreads: weekly.threads,
            windows: windows,
            costEstimates: costEstimates(databasePath: databasePath),
            recentSessions: sessions(databasePath: databasePath, mode: .recent),
            topWeeklySessions: sessions(databasePath: databasePath, mode: .highestWeekly),
            modelUsage: codexModelUsage(databasePath: databasePath, seconds: 604_800),
            dailyModelUsage: codexModelUsage(databasePath: databasePath, seconds: 86_400),
            usageBuckets: codexUsageBuckets(databasePath: databasePath)
        )
    }

    /// Hourly totals from the per-request token events in rollouts active in the last 7 days.
    /// Rollouts are parsed incrementally (see `CodexRolloutCache`), so this mostly reuses earlier work.
    private static func codexUsageBuckets(databasePath: String) -> [LLMUsageBucket] {
        let query = """
        select rollout_path, replace(replace(coalesce(nullif(model,''), ''), char(10), ' '), char(9), ' ')
        from threads
        where tokens_used > 0
          and coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-\(Int(LLMUsageBucket.retentionSeconds)))*1000
          and rollout_path is not null
          and rollout_path != '';
        """
        var calls: [(call: LLMTokenCall, modelName: String)] = []
        for row in sqliteRows(databasePath: databasePath, query: query) {
            guard let rolloutPath = row.first, tokenUsageSummary(from: rolloutPath) != nil else { continue }
            let modelName = row.count > 1 ? row[1] : ""
            calls += cachedCodexCalls(rolloutPath).map { (call: $0, modelName: modelName) }
        }
        return LLMUsageBucket.hourly(provider: "Codex", calls: calls)
    }

    private static func cachedCodexCalls(_ rolloutPath: String) -> [LLMTokenCall] {
        let path = rolloutPath.trimmingCharacters(in: .whitespacesAndNewlines)
        codexRolloutCache.lock.lock()
        defer { codexRolloutCache.lock.unlock() }
        return codexRolloutCache.entries[path]?.calls ?? []
    }

    private static func codexModelUsage(databasePath: String, seconds: Int) -> [LLMModelUsageTotal] {
        let query = """
        select
            replace(replace(coalesce(nullif(model,''), nullif(model_provider,''), 'Model unavailable'), char(10), ' '), char(9), ' '),
            coalesce(sum(tokens_used),0),
            count(*)
        from threads
        where coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-\(seconds))*1000
        group by 1
        order by 2 desc;
        """
        return sqliteRows(databasePath: databasePath, query: query).compactMap { row in
            guard row.count >= 3 else { return nil }
            return LLMModelUsageTotal(
                provider: "Codex",
                modelName: compactText(row[0], fallback: "Model unavailable"),
                tokens: UInt64(row[1]) ?? 0,
                sessionCount: Int(row[2]) ?? 0
            )
        }
    }

    private static func localWindow(databasePath: String, label: String, seconds: Int) -> LLMLocalUsageWindow {
        let query = """
        select coalesce(sum(tokens_used),0), count(*)
        from threads
        where coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-\(seconds))*1000;
        """
        let row = sqliteRows(databasePath: databasePath, query: query).first ?? []
        return LLMLocalUsageWindow(
            label: label,
            tokens: row.indices.contains(0) ? UInt64(row[0]) ?? 0 : 0,
            threads: row.indices.contains(1) ? Int(row[1]) ?? 0 : 0
        )
    }

    private static func costEstimates(databasePath: String) -> [LLMTokenCostEstimate] {
        let endedAt = Date()
        return [
            costEstimate(databasePath: databasePath, label: "5h", seconds: 18_000, endedAt: endedAt),
            costEstimate(databasePath: databasePath, label: "Weekly", seconds: 604_800, endedAt: endedAt)
        ].compactMap { $0 }
    }

    private static func costEstimate(databasePath: String, label: String, seconds: Int, endedAt: Date) -> LLMTokenCostEstimate? {
        let query = """
        select rollout_path
        from threads
        where tokens_used > 0
          and coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-\(seconds))*1000
          and rollout_path is not null
          and rollout_path != '';
        """

        var sessionCount = 0
        var inputTokens: UInt64 = 0
        var cachedInputTokens: UInt64 = 0
        var outputTokens: UInt64 = 0
        var totalTokens: UInt64 = 0

        for row in sqliteRows(databasePath: databasePath, query: query) {
            guard let rolloutPath = row.first,
                  let usage = tokenUsageSummary(from: rolloutPath) else {
                continue
            }
            sessionCount += 1
            inputTokens += usage.inputTokens
            cachedInputTokens += usage.cachedInputTokens
            outputTokens += usage.outputTokens
            totalTokens += max(usage.totalTokens, usage.inputTokens + usage.outputTokens)
        }

        guard sessionCount > 0 else { return nil }

        return LLMTokenCostEstimate(
            label: label,
            sessionCount: sessionCount,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            windowStartedAt: endedAt.addingTimeInterval(-TimeInterval(seconds)),
            windowEndedAt: endedAt
        )
    }

    private enum SessionQueryMode {
        case recent
        case highestWeekly
    }

    private static func sessions(databasePath: String, mode: SessionQueryMode) -> [LLMUsageSession] {
        let indexTitles = sessionIndexTitles()
        let whereClause = mode == .highestWeekly
            ? "where tokens_used > 0 and coalesce(updated_at_ms, updated_at * 1000) >= (strftime('%s','now')-7*24*3600)*1000"
            : "where coalesce(updated_at_ms, updated_at * 1000) > 0"
        let orderClause = mode == .highestWeekly
            ? "order by tokens_used desc, coalesce(updated_at_ms, updated_at * 1000) desc"
            : "order by coalesce(updated_at_ms, updated_at * 1000) desc"
        let query = """
        select
            id,
            replace(replace(coalesce(nullif(title,''),'Untitled'), char(10), ' '), char(9), ' '),
            coalesce(tokens_used,0),
            coalesce(created_at_ms, created_at * 1000),
            coalesce(updated_at_ms, updated_at * 1000),
            replace(replace(coalesce(nullif(model,''), nullif(model_provider,''), ''), char(10), ' '), char(9), ' '),
            replace(replace(coalesce(nullif(cwd,''), ''), char(10), ' '), char(9), ' '),
            replace(replace(coalesce(nullif(preview,''), nullif(first_user_message,''), ''), char(10), ' '), char(9), ' '),
            rollout_path
        from threads
        \(whereClause)
        \(orderClause)
        limit 30;
        """

        return sqliteRows(databasePath: databasePath, query: query).compactMap { row in
            guard row.count >= 9 else { return nil }
            let title = sessionTitle(id: row[0], sqliteTitle: row[1], indexTitles: indexTitles)
            let tokens = UInt64(row[2]) ?? 0
            let createdAt = TimeInterval(row[3]).map { Date(timeIntervalSince1970: $0 / 1000) }
            let updatedAt = TimeInterval(row[4]).map { Date(timeIntervalSince1970: $0 / 1000) }
            let model = compactText(row[5], fallback: "Model unavailable")
            let project = projectName(from: row[6])
            let preview = compactText(row[7], fallback: "No prompt preview stored")
            let rolloutPath = compactText(row[8], fallback: "")
            return LLMUsageSession(
                id: row[0],
                provider: "Codex",
                title: title,
                projectName: project,
                modelName: model,
                preview: preview,
                rolloutPath: rolloutPath,
                tokens: tokens,
                tokenUsage: tokenUsageSummary(from: rolloutPath),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private static func sessionTitle(id: String, sqliteTitle: String, indexTitles: [String: String]) -> String {
        if let indexTitle = indexTitles[id],
           !indexTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return indexTitle
        }
        return compactText(sqliteTitle, fallback: "Untitled")
    }

    private static func sessionIndexTitles() -> [String: String] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/session_index.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let decoder = JSONDecoder()
        var titles: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(SessionIndexEntry.self, from: data),
                  let title = entry.thread_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                continue
            }
            titles[entry.id] = title
        }
        return titles
    }

    /// Per-rollout parse state. Rollout files are append-only, so each refresh reads only the new lines.
    private final class CodexRolloutCache: @unchecked Sendable {
        struct Entry {
            var parsedOffset: UInt64 = 0
            var calls: [LLMTokenCall] = []
            var totals: [String: UInt64]?
        }

        let lock = NSLock()
        var entries: [String: Entry] = [:]
    }

    private static let codexRolloutCache = CodexRolloutCache()

    private static func tokenUsageSummary(from rolloutPath: String) -> LLMTokenUsageSummary? {
        let path = rolloutPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        codexRolloutCache.lock.lock()
        defer {
            codexRolloutCache.lock.unlock()
        }
        var entry = codexRolloutCache.entries[path] ?? CodexRolloutCache.Entry()
        let fileSize = (try? handle.seekToEnd()) ?? 0
        if fileSize < entry.parsedOffset {
            entry = CodexRolloutCache.Entry()
        }
        if fileSize > entry.parsedOffset {
            try? handle.seek(toOffset: entry.parsedOffset)
            let data = handle.readDataToEndOfFile()
            if let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) {
                let complete = data[data.startIndex...lastNewline]
                entry.parsedOffset += UInt64(complete.count)
                parseCodexTokenEvents(String(decoding: complete, as: UTF8.self), into: &entry)
            }
        }
        codexRolloutCache.entries[path] = entry

        guard let totals = entry.totals else { return nil }

        var summary = LLMTokenUsageSummary(calls: entry.calls)
        summary.inputTokens = totals["input_tokens"] ?? 0
        summary.cachedInputTokens = totals["cached_input_tokens"] ?? 0
        summary.cacheWriteInputTokens = totals["cache_write_input_tokens"] ?? 0
        summary.outputTokens = totals["output_tokens"] ?? 0
        summary.reasoningOutputTokens = totals["reasoning_output_tokens"] ?? 0
        summary.totalTokens = totals["total_tokens"] ?? 0
        if summary.totalTokens == 0 {
            summary.totalTokens = summary.inputTokens + summary.outputTokens + summary.reasoningOutputTokens
        }
        return summary
    }

    private static func parseCodexTokenEvents(_ text: String, into entry: inout CodexRolloutCache.Entry) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.contains("\"token_count\"") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any] else {
                continue
            }

            if let last = info["last_token_usage"] as? [String: Any] {
                entry.calls.append(LLMTokenCall(
                    timestamp: (object["timestamp"] as? String).flatMap(iso8601Date),
                    inputTokens: tokenValue(last, "input_tokens"),
                    cachedInputTokens: tokenValue(last, "cached_input_tokens"),
                    cacheWriteInputTokens: tokenValue(last, "cache_write_input_tokens"),
                    outputTokens: tokenValue(last, "output_tokens")
                ))
            }

            let totalUsage = (info["total_token_usage"] as? [String: Any]) ?? info
            entry.totals = ["input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"]
                .reduce(into: [:]) { $0[$1] = tokenValue(totalUsage, $1) }
        }
    }

    private static func tokenValue(_ dictionary: [String: Any], _ key: String) -> UInt64 {
        if let value = dictionary[key] as? UInt64 {
            return value
        }
        if let value = dictionary[key] as? Int {
            return UInt64(max(value, 0))
        }
        if let value = dictionary[key] as? Double {
            return UInt64(max(value, 0))
        }
        if let value = dictionary[key] as? String {
            return UInt64(value) ?? 0
        }
        return 0
    }

    private static func sqliteRows(databasePath: String, query: String) -> [[String]] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = ["-batch", "-separator", "\t", databasePath, query]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    static func snapshotWithLocalUsage(
        _ local: LocalProviderUsage,
        error: String?
    ) -> LLMUsageSnapshot {
        LLMUsageSnapshot(
            email: nil,
            planType: nil,
            limits: [],
            creditsBalance: nil,
            resetCreditCount: nil,
            resetCreditExpirations: [],
            lastUpdated: Date(),
            localFiveHourTokens: local.fiveHourTokens,
            localWeeklyTokens: local.weeklyTokens,
            localWeeklyThreads: local.weeklyThreads,
            localWindows: local.windows,
            costEstimates: local.costEstimates,
            recentSessions: local.recentSessions,
            topWeeklySessions: local.topWeeklySessions,
            error: error
        )
    }

    static func compactText(_ text: String, fallback: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? fallback : trimmedText
    }

    static func trimmed(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength - 1)
        return String(text[..<end]) + "..."
    }

    static func projectName(from path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "Project unavailable" }
        return URL(fileURLWithPath: trimmedPath).lastPathComponent
    }
}
