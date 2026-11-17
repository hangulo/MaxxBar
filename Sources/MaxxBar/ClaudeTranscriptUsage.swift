import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

extension LLMUsageReader {
    /// Every Claude Code and Desktop transcript on disk.
    private static func claudeTranscriptURLs() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let roots = [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions", isDirectory: true)
        ]
        var urls: [URL] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard url.lastPathComponent != "audit.jsonl",
                      url.path.contains("/projects/") else { continue }
                urls.append(url)
            }
        }
        return urls
    }

    static func readLocalClaudeUsage() -> LocalProviderUsage {
        var urls = claudeTranscriptURLs()
        // Every number on screen covers at most 7 days, so older transcripts are only read to fill the
        // 30-row recent session list. This keeps launch from parsing every transcript ever written.
        let modifiedAt = Dictionary(uniqueKeysWithValues: urls.map {
            ($0.path, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        })
        let recentCutoff = Date().addingTimeInterval(-8 * 86_400)
        urls = urls
            .sorted { modifiedAt[$0.path, default: .distantPast] > modifiedAt[$1.path, default: .distantPast] }
            .enumerated()
            .filter { $0.offset < 30 || modifiedAt[$0.element.path, default: .distantPast] >= recentCutoff }
            .map(\.element)
        let livePaths = Set(urls.map(\.path))
        loadClaudeParseCacheIfNeeded()
        claudeParsedFilesLock.lock()
        claudeParsedFiles = claudeParsedFiles.filter { livePaths.contains($0.key) }
        claudeParsedFilesLock.unlock()
        defer { saveClaudeParseCacheIfNeeded() }

        let sidecarTitles = claudeSidecarTitles()
        let generatedTitles = loadClaudeGeneratedTitles()
        let transcripts = urls.compactMap {
            claudeTranscript(from: $0, sidecarTitles: sidecarTitles, generatedTitles: generatedTitles)
        }
        scheduleClaudeTitleGeneration(for: transcripts, cached: generatedTitles)
        let sessions = uniqueSessions(transcripts.map(\.session))
        let modelEvents = uniqueClaudeModelEvents(transcripts.flatMap(\.modelEvents))
        let now = Date()
        // Days from a week ago on are fully covered by the transcripts read above (files modified in 8 days).
        APICostLedger.record(
            apiCostEvents(modelEvents), provider: "Claude",
            completeFrom: Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: now))
        )
        scheduleClaudeCostBackfillIfNeeded()
        func usageWindow(label: String, seconds: TimeInterval) -> LLMLocalUsageWindow {
            let matching = modelEvents.filter { now.timeIntervalSince($0.timestamp ?? .distantPast) <= seconds }
            return LLMLocalUsageWindow(
                label: label,
                tokens: matching.reduce(0) { $0 + $1.tokens },
                threads: Set(matching.map(\.sessionID)).count
            )
        }
        let windows = [
            usageWindow(label: "1h", seconds: 3_600),
            usageWindow(label: "5h", seconds: 18_000),
            usageWindow(label: "24h", seconds: 86_400),
            usageWindow(label: "7d", seconds: 604_800)
        ]
        let recent = sessions.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        let weekly = sessions
            .filter { now.timeIntervalSince($0.updatedAt ?? $0.createdAt ?? .distantPast) <= 604_800 }
            .sorted { $0.tokens == $1.tokens
                ? ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
                : $0.tokens > $1.tokens
            }
        return LocalProviderUsage(
            fiveHourTokens: windows.first(where: { $0.label == "5h" })?.tokens ?? 0,
            weeklyTokens: windows.first(where: { $0.label == "7d" })?.tokens ?? 0,
            weeklyThreads: windows.first(where: { $0.label == "7d" })?.threads ?? 0,
            windows: windows,
            costEstimates: [],
            recentSessions: Array(recent.prefix(30)),
            topWeeklySessions: Array(weekly.prefix(30)),
            modelUsage: modelUsageTotals(from: modelEvents, since: now.addingTimeInterval(-604_800)),
            dailyModelUsage: modelUsageTotals(from: modelEvents, since: now.addingTimeInterval(-86_400)),
            usageBuckets: LLMUsageBucket.hourly(
                provider: "Claude",
                calls: modelEvents.map { (call: $0.call, modelName: $0.modelName) },
                now: now
            ),
            claudeUsagePoints: minuteUsagePoints(modelEvents, now: now)
        )
    }

    /// Tokens per minute for the last 8 days, raw and weighted by API price, for the quota estimator.
    static func minuteUsagePoints(_ events: [ClaudeModelUsageEvent], now: Date) -> [ClaudeQuotaEstimator.UsagePoint] {
        let cutoff = now.addingTimeInterval(-ClaudeReadingLog.retention)
        var minutes: [Int: ClaudeQuotaEstimator.UsagePoint] = [:]
        for event in events {
            guard let at = event.timestamp, at >= cutoff, at <= now.addingTimeInterval(300),
                  !event.modelName.localizedCaseInsensitiveContains("synthetic") else { continue }
            let call = event.call
            let cost = LLMTokenPricing.rates(for: event.modelName).breakdown(
                inputTokens: call.inputTokens, cachedInputTokens: call.cachedInputTokens,
                cacheWriteInputTokens: call.cacheWriteInputTokens, cacheWrite1hInputTokens: call.cacheWrite1hInputTokens,
                outputTokens: call.outputTokens
            ).total
            // Each point is stamped at the end of its minute, so a reading's own minute is placed within a minute.
            let minute = Int(ceil(at.timeIntervalSince1970 / 60))
            var point = minutes[minute] ?? .init(at: Date(timeIntervalSince1970: Double(minute) * 60), tokens: 0, weightedTokens: 0)
            point.tokens += Double(call.inputTokens + call.outputTokens)
            point.weightedTokens += cost / 5 * 1_000_000
            minutes[minute] = point
        }
        return minutes.values.sorted { $0.at < $1.at }
    }

    private static func modelUsageTotals(from sessions: [LLMUsageSession]) -> [LLMModelUsageTotal] {
        let totals = sessions.map { session in
            LLMModelUsageTotal(
                provider: session.provider,
                modelName: compactText(session.modelName, fallback: "Model unavailable"),
                tokens: session.tokenUsage?.totalTokens ?? session.tokens,
                sessionCount: 1
            )
        }
        return mergedModelUsage(totals)
    }

    private static func apiCostEvents(_ events: [ClaudeModelUsageEvent]) -> [APICostEvent] {
        events.compactMap { event in
            guard let at = event.timestamp, let usage = event.usage,
                  !event.modelName.localizedCaseInsensitiveContains("synthetic") else { return nil }
            let cost = LLMTokenPricing.rates(for: event.modelName).breakdown(
                inputTokens: usage.inputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                cacheWriteInputTokens: usage.cacheWriteInputTokens,
                cacheWrite1hInputTokens: usage.cacheWrite1hInputTokens,
                outputTokens: usage.outputTokens
            ).total
            return APICostEvent(
                at: at, costUSD: cost, inputTokens: usage.inputTokens, cachedInputTokens: usage.cachedInputTokens,
                cacheWriteInputTokens: usage.cacheWriteInputTokens, outputTokens: usage.outputTokens
            )
        }
    }

    nonisolated(unsafe) private static var claudeCostBackfillStarted = false

    /// Once per install: price every request in every transcript on disk, so "this month" has history from
    /// before the ledger existed. Runs in the background; transcripts are read one at a time.
    private static func scheduleClaudeCostBackfillIfNeeded() {
        claudeParsedFilesLock.lock()
        let start = !claudeCostBackfillStarted
        claudeCostBackfillStarted = true
        claudeParsedFilesLock.unlock()
        // Version 2 dedupes requests copied into resumed or forked transcripts, so it runs once more.
        guard start, !APICostLedger.isBackfilled(provider: "Claude", mark: "Claude.v2") else { return }
        DispatchQueue.global(qos: .background).async {
            var seen = Set<String>()
            var events: [APICostEvent] = []
            for url in claudeTranscriptURLs() {
                autoreleasepool {
                    guard let parsed = parsedClaudeFile(url),
                          !(parsed.cwd?.hasPrefix(claudeTitlerDirectory.path) ?? false) else { return }
                    for (key, value) in parsed.requestUsage where seen.insert(requestDedupeKey(sessionID: parsed.sessionID, requestID: key)).inserted {
                        let event = ClaudeModelUsageEvent(
                            requestID: key, sessionID: parsed.sessionID, modelName: value.modelName,
                            tokens: value.usage.totalTokens, timestamp: value.timestamp ?? parsed.updatedAt,
                            call: tokenCall(value.usage, at: value.timestamp ?? parsed.updatedAt), usage: value.usage
                        )
                        events.append(contentsOf: apiCostEvents([event]))
                    }
                }
            }
            APICostLedger.record(events, provider: "Claude", completeFrom: nil, backfill: true, mark: "Claude.v2")
        }
    }

    /// Every priced Claude request in every transcript on disk, for the usage report. Slow on first use (it reads
    /// all transcripts); later calls reuse the parse cache. Requests copied into forked sessions count once.
    static func usageReportRequests() -> (requests: [UsageReportRequest], sessions: [String: UsageReportSession]) {
        let sidecarTitles = claudeSidecarTitles()
        let generatedTitles = loadClaudeGeneratedTitles()
        var seen = Set<String>()
        var requests: [UsageReportRequest] = []
        var sessions: [String: UsageReportSession] = [:]
        for url in claudeTranscriptURLs() {
            autoreleasepool {
                guard let transcript = claudeTranscript(from: url, sidecarTitles: sidecarTitles, generatedTitles: generatedTitles)
                else { return }
                let session = transcript.session
                sessions[session.id] = UsageReportSession(title: session.title, project: session.projectName)
                for event in transcript.modelEvents
                where seen.insert(requestDedupeKey(sessionID: event.sessionID, requestID: event.requestID)).inserted {
                    guard let at = event.timestamp, let usage = event.usage,
                          !event.modelName.localizedCaseInsensitiveContains("synthetic") else { continue }
                    let cost = LLMTokenPricing.rates(for: event.modelName).breakdown(
                        inputTokens: usage.inputTokens,
                        cachedInputTokens: usage.cachedInputTokens,
                        cacheWriteInputTokens: usage.cacheWriteInputTokens,
                        cacheWrite1hInputTokens: usage.cacheWrite1hInputTokens,
                        outputTokens: usage.outputTokens
                    )
                    requests.append(UsageReportRequest(
                        at: at, sessionID: event.sessionID, model: event.modelName, cost: cost,
                        tokens: usage.inputTokens + usage.outputTokens
                    ))
                }
            }
        }
        return (requests, sessions)
    }

    private static func tokenCall(_ usage: LLMTokenUsageSummary, at timestamp: Date?) -> LLMTokenCall {
        LLMTokenCall(
            timestamp: timestamp,
            inputTokens: usage.inputTokens,
            cachedInputTokens: usage.cachedInputTokens,
            cacheWriteInputTokens: usage.cacheWriteInputTokens,
            cacheWrite1hInputTokens: usage.cacheWrite1hInputTokens,
            outputTokens: usage.outputTokens
        )
    }

    private static func uniqueClaudeModelEvents(_ events: [ClaudeModelUsageEvent]) -> [ClaudeModelUsageEvent] {
        var seen = Set<String>()
        return events.filter { seen.insert(requestDedupeKey(sessionID: $0.sessionID, requestID: $0.requestID)).inserted }
    }

    /// A resumed or forked session copies earlier lines, request ids included, into a new transcript; counting
    /// each request id once keeps those from being double counted. Line-number fallbacks stay per session.
    private static func requestDedupeKey(sessionID: String, requestID: String) -> String {
        requestID.hasPrefix("line-") ? "\(sessionID)|\(requestID)" : requestID
    }

    private static func modelUsageTotals(
        from events: [ClaudeModelUsageEvent],
        since cutoff: Date
    ) -> [LLMModelUsageTotal] {
        let recent = events.filter {
            ($0.timestamp ?? .distantPast) >= cutoff
                && $0.tokens > 0
                && !$0.modelName.localizedCaseInsensitiveContains("synthetic")
        }
        let groups = Dictionary(grouping: recent, by: { $0.modelName })
        return groups.map { modelName, modelEvents in
            LLMModelUsageTotal(
                provider: "Claude",
                modelName: modelName,
                tokens: modelEvents.reduce(UInt64(0)) { $0 + $1.tokens },
                sessionCount: Set(modelEvents.map(\.sessionID)).count
            )
        }.sorted {
            $0.tokens == $1.tokens
                ? $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending
                : $0.tokens > $1.tokens
        }
    }

    private struct ClaudeParsedFile {
        var sessionID: String
        var title: String?
        var summary: String?
        var preview: String?
        var cwd: String?
        var model: String?
        var createdAt: Date?
        var updatedAt: Date?
        var requestUsage: [String: (usage: LLMTokenUsageSummary, modelName: String, timestamp: Date?)]
    }

    struct ClaudeParsedFileStamp: Equatable {
        let size: Int
        let modified: Date
    }

    private struct ClaudeParsedFileEntry {
        let stamp: ClaudeParsedFileStamp
        let parsed: ClaudeParsedFile
        /// Byte offset just past the last complete line parsed, and how many lines that was.
        let offset: UInt64
        let lineCount: Int
    }

    nonisolated(unsafe) private static var claudeParsedFiles: [String: ClaudeParsedFileEntry] = [:]
    private static let claudeParsedFilesLock = NSLock()

    // MARK: Parse cache on disk
    // Launch used to start cold and parse every recent transcript again. The parsed totals are saved to
    // claude-parse-cache.json so a launch only reads what was appended since the last run.

    private struct DiskParsedFile: Codable {
        struct Request: Codable {
            var input: UInt64
            var cached: UInt64
            var output: UInt64
            var total: UInt64
            var cacheWrite: UInt64
            var cacheWrite1h: UInt64
            var model: String
            var at: Date?
        }
        var size: Int
        var modified: Date
        var offset: UInt64
        var lineCount: Int
        var sessionID: String
        var title: String?
        var summary: String?
        var preview: String?
        var cwd: String?
        var model: String?
        var createdAt: Date?
        var updatedAt: Date?
        var requests: [String: Request]
    }

    private static let claudeParseCacheVersion = 1
    private struct DiskParseCache: Codable {
        var version: Int
        var files: [String: DiskParsedFile]
    }

    nonisolated(unsafe) private static var claudeParseCacheLoaded = false
    nonisolated(unsafe) private static var claudeParseCacheDirty = false
    nonisolated(unsafe) private static var claudeParseCacheSavedAt: Date?
    private static let claudeParseCacheSaveInterval: TimeInterval = 300

    private static var claudeParseCacheURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/claude-parse-cache.json")
    }

    private static func loadClaudeParseCacheIfNeeded() {
        claudeParsedFilesLock.lock()
        defer { claudeParsedFilesLock.unlock() }
        guard !claudeParseCacheLoaded else { return }
        claudeParseCacheLoaded = true
        guard let data = try? Data(contentsOf: claudeParseCacheURL),
              let cache = try? JSONDecoder().decode(DiskParseCache.self, from: data),
              cache.version == claudeParseCacheVersion else { return }
        for (path, file) in cache.files where claudeParsedFiles[path] == nil {
            let requests = file.requests.mapValues { request in
                (
                    usage: LLMTokenUsageSummary(
                        inputTokens: request.input,
                        cachedInputTokens: request.cached,
                        outputTokens: request.output,
                        reasoningOutputTokens: 0,
                        totalTokens: request.total,
                        turnCount: 1,
                        cacheWriteInputTokens: request.cacheWrite,
                        cacheWrite1hInputTokens: request.cacheWrite1h
                    ),
                    modelName: request.model,
                    timestamp: request.at
                )
            }
            claudeParsedFiles[path] = ClaudeParsedFileEntry(
                stamp: ClaudeParsedFileStamp(size: file.size, modified: file.modified),
                parsed: ClaudeParsedFile(
                    sessionID: file.sessionID, title: file.title, summary: file.summary, preview: file.preview,
                    cwd: file.cwd, model: file.model, createdAt: file.createdAt, updatedAt: file.updatedAt,
                    requestUsage: requests
                ),
                offset: file.offset,
                lineCount: file.lineCount
            )
        }
    }

    /// Written at most every five minutes, and only after a transcript was parsed.
    private static func saveClaudeParseCacheIfNeeded() {
        claudeParsedFilesLock.lock()
        let now = Date()
        guard claudeParseCacheDirty,
              claudeParseCacheSavedAt.map({ now.timeIntervalSince($0) >= claudeParseCacheSaveInterval }) ?? true else {
            claudeParsedFilesLock.unlock()
            return
        }
        let files = claudeParsedFiles.mapValues { entry in
            DiskParsedFile(
                size: entry.stamp.size, modified: entry.stamp.modified, offset: entry.offset, lineCount: entry.lineCount,
                sessionID: entry.parsed.sessionID, title: entry.parsed.title, summary: entry.parsed.summary,
                preview: entry.parsed.preview, cwd: entry.parsed.cwd, model: entry.parsed.model,
                createdAt: entry.parsed.createdAt, updatedAt: entry.parsed.updatedAt,
                requests: entry.parsed.requestUsage.mapValues { request in
                    DiskParsedFile.Request(
                        input: request.usage.inputTokens, cached: request.usage.cachedInputTokens,
                        output: request.usage.outputTokens, total: request.usage.totalTokens,
                        cacheWrite: request.usage.cacheWriteInputTokens,
                        cacheWrite1h: request.usage.cacheWrite1hInputTokens,
                        model: request.modelName, at: request.timestamp
                    )
                }
            )
        }
        claudeParseCacheDirty = false
        claudeParseCacheSavedAt = now
        claudeParsedFilesLock.unlock()
        guard let data = try? JSONEncoder().encode(DiskParseCache(version: claudeParseCacheVersion, files: files)) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: claudeParseCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: claudeParseCacheURL, options: .atomic)
    }

    /// Parses a transcript once and reuses the result until the file's size or modification date changes.
    /// Transcripts only grow, so a grown file is parsed from where the last pass stopped instead of from byte zero.
    private static func parsedClaudeFile(_ url: URL) -> ClaudeParsedFile? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var stamp: ClaudeParsedFileStamp?
        if let size = values?.fileSize, let modified = values?.contentModificationDate {
            stamp = ClaudeParsedFileStamp(size: size, modified: modified)
        }
        claudeParsedFilesLock.lock()
        let hit = claudeParsedFiles[url.path]
        claudeParsedFilesLock.unlock()
        if let hit, let stamp, hit.stamp == stamp { return hit.parsed }
        let resume = hit.flatMap { hit -> ClaudeParsedFileEntry? in
            guard let stamp, stamp.size > hit.stamp.size, UInt64(stamp.size) >= hit.offset else { return nil }
            return hit
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let startOffset = resume?.offset ?? 0
        guard (try? handle.seek(toOffset: startOffset)) != nil,
              let data = try? handle.readToEnd() else { return resume?.parsed }
        // Stop at the last newline: a line still being written is picked up on the next pass.
        let consumed = (data.lastIndex(of: 0x0A).map { $0 - data.startIndex + 1 }) ?? 0
        let previous = resume?.parsed
        var sessionID = previous?.sessionID ?? url.deletingPathExtension().lastPathComponent
        var title = previous?.title
        var summary = previous?.summary
        var preview = previous?.preview
        var cwd = previous?.cwd
        var model = previous?.model
        var createdAt = previous?.createdAt
        var updatedAt = previous?.updatedAt
        var requestUsage = previous?.requestUsage ?? [:]
        var lineCount = resume?.lineCount ?? 0

        for line in data.prefix(consumed).split(separator: 0x0A, omittingEmptySubsequences: true) {
            let index = lineCount
            lineCount += 1
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let value = object["sessionId"] as? String, !value.isEmpty { sessionID = value }
            if let value = object["customTitle"] as? String, !value.isEmpty { title = value }
            if title == nil, let value = object["aiTitle"] as? String, !value.isEmpty { title = value }
            if (object["type"] as? String) == "summary",
               let value = object["summary"] as? String, !value.isEmpty { summary = value }
            if let value = object["cwd"] as? String, !value.isEmpty { cwd = value }
            let eventTimestamp = (object["timestamp"] as? String).flatMap(iso8601Date)
            if let date = eventTimestamp {
                createdAt = min(createdAt ?? date, date)
                updatedAt = max(updatedAt ?? date, date)
            }

            guard let message = object["message"] as? [String: Any] else { continue }
            if preview == nil,
               (object["type"] as? String) == "user",
               (message["role"] as? String) == "user" {
                preview = claudeMessageText(message["content"]).flatMap(claudePromptText)
            }
            guard (object["type"] as? String) == "assistant",
                  let usage = message["usage"] as? [String: Any] else { continue }
            if let value = message["model"] as? String, !value.isEmpty { model = value }
            let input = uint64(usage["input_tokens"])
            let cacheCreated = uint64(usage["cache_creation_input_tokens"])
            let cacheRead = uint64(usage["cache_read_input_tokens"])
            let cacheCreated1h = uint64((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"])
            let output = uint64(usage["output_tokens"])
            let key = (object["requestId"] as? String) ?? (object["uuid"] as? String) ?? "line-\(index)"
            requestUsage[key] = (
                LLMTokenUsageSummary(
                    inputTokens: input + cacheCreated + cacheRead,
                    cachedInputTokens: cacheRead,
                    outputTokens: output,
                    reasoningOutputTokens: 0,
                    totalTokens: input + cacheCreated + cacheRead + output,
                    turnCount: 1,
                    cacheWriteInputTokens: cacheCreated,
                    cacheWrite1hInputTokens: cacheCreated1h
                ),
                compactText(message["model"] as? String ?? "", fallback: "Claude model unavailable"),
                eventTimestamp
            )
        }


        let parsed = ClaudeParsedFile(
            sessionID: sessionID,
            title: title,
            summary: summary,
            preview: preview,
            cwd: cwd,
            model: model,
            createdAt: createdAt,
            updatedAt: updatedAt,
            requestUsage: requestUsage
        )
        if let stamp {
            claudeParsedFilesLock.lock()
            claudeParsedFiles[url.path] = ClaudeParsedFileEntry(
                stamp: stamp, parsed: parsed, offset: startOffset + UInt64(consumed), lineCount: lineCount
            )
            claudeParseCacheDirty = true
            claudeParsedFilesLock.unlock()
        }
        return parsed
    }

    private static func claudeTranscript(
        from url: URL,
        sidecarTitles: [String: String],
        generatedTitles: [String: String]
    ) -> ClaudeTranscript? {
        guard let parsed = parsedClaudeFile(url) else { return nil }
        let sessionID = parsed.sessionID
        let title = parsed.title
        let summary = parsed.summary
        let preview = parsed.preview
        let cwd = parsed.cwd
        let model = parsed.model
        let createdAt = parsed.createdAt
        let updatedAt = parsed.updatedAt
        let requestUsage = parsed.requestUsage

        let totals = LLMTokenUsageSummary(calls: requestUsage.values.map { value in
            LLMTokenCall(
                timestamp: value.timestamp,
                inputTokens: value.usage.inputTokens,
                cachedInputTokens: value.usage.cachedInputTokens,
                cacheWriteInputTokens: value.usage.cacheWriteInputTokens,
                cacheWrite1hInputTokens: value.usage.cacheWrite1hInputTokens,
                outputTokens: value.usage.outputTokens
            )
        })
        guard createdAt != nil || updatedAt != nil || totals.totalTokens > 0 else { return nil }
        if let cwd, cwd.hasPrefix(claudeTitlerDirectory.path) { return nil }
        let realTitle = [title, summary, sidecarTitles[sessionID]]
            .compactMap { $0 }
            .first { !isPlaceholderClaudeTitle($0) }
        let generatedTitle = generatedTitles[sessionID].flatMap { $0.isEmpty ? nil : "Thread: \($0)" }
        let cleanPreview = compactText(preview ?? "", fallback: "No prompt preview stored")
        let dominantModel = Dictionary(grouping: requestUsage.values, by: \.modelName)
            .map { (model: $0.key, tokens: $0.value.reduce(UInt64(0)) { $0 + $1.usage.totalTokens }) }
            .max { $0.tokens < $1.tokens }?.model
        let session = LLMUsageSession(
            id: sessionID,
            provider: "Claude",
            title: compactText(realTitle ?? generatedTitle ?? preview ?? "", fallback: "Claude session"),
            projectName: projectName(from: cwd ?? ""),
            modelName: dominantModel ?? compactText(model ?? "", fallback: "Claude model unavailable"),
            preview: trimmed(cleanPreview, maxLength: 500),
            rolloutPath: url.path,
            tokens: totals.totalTokens,
            tokenUsage: totals.totalTokens > 0 ? totals : nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let events = requestUsage.map { key, value in
            ClaudeModelUsageEvent(
                requestID: key,
                sessionID: sessionID,
                modelName: value.modelName,
                tokens: value.usage.totalTokens,
                timestamp: value.timestamp ?? updatedAt,
                call: tokenCall(value.usage, at: value.timestamp ?? updatedAt),
                usage: value.usage
            )
        }
        return ClaudeTranscript(session: session, modelEvents: events, untitledPrompt: realTitle == nil ? preview : nil)
    }

    private static let claudeTitleQueue = DispatchQueue(label: "MaxxBar.ClaudeTitles", qos: .utility)
    nonisolated(unsafe) private static var claudeTitleGenerationRunning = false
    nonisolated(unsafe) private static var claudeTitleAuthFailedAt: Date?

    private static var claudeGeneratedTitlesURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/MaxxBar/claude-session-titles.json")
    }

    private static var claudeTitlerDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/MaxxBar/titler", isDirectory: true)
    }

    /// Short titles made by the Claude CLI for untitled sessions, keyed by session id; "" marks a failed attempt.
    private static func loadClaudeGeneratedTitles() -> [String: String] {
        guard let data = try? Data(contentsOf: claudeGeneratedTitlesURL),
              let titles = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return titles
    }

    /// Titles up to three recent untitled sessions in the background; they show up on a later refresh.
    private static func scheduleClaudeTitleGeneration(for transcripts: [ClaudeTranscript], cached: [String: String]) {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let pending = transcripts
            .filter { $0.untitledPrompt != nil && cached[$0.session.id] == nil && ($0.session.updatedAt ?? .distantPast) >= cutoff }
            .sorted { ($0.session.updatedAt ?? .distantPast) > ($1.session.updatedAt ?? .distantPast) }
            .prefix(3)
            .compactMap { transcript in transcript.untitledPrompt.map { (id: transcript.session.id, prompt: $0) } }
        guard !pending.isEmpty, let binary = claudeBinaryPath() else { return }
        claudeTitleQueue.async {
            guard !claudeTitleGenerationRunning else { return }
            if let failedAt = claudeTitleAuthFailedAt, Date().timeIntervalSince(failedAt) < 60 * 60 { return }
            claudeTitleGenerationRunning = true
            defer { claudeTitleGenerationRunning = false }
            var titles = loadClaudeGeneratedTitles()
            for item in pending where titles[item.id] == nil {
                guard let result = generateClaudeTitle(for: item.prompt, binary: binary) else {
                    claudeTitleAuthFailedAt = Date()
                    break
                }
                titles[item.id] = result
                if let data = try? JSONEncoder().encode(titles) {
                    try? data.write(to: claudeGeneratedTitlesURL, options: .atomic)
                }
            }
        }
    }

    private static func claudeBinaryPath() -> String? {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Returns a sanitized title, "" when the call fails, or nil when the CLI isn't signed in (so it's retried later).
    private static func generateClaudeTitle(for prompt: String, binary: String) -> String? {
        try? FileManager.default.createDirectory(at: claudeTitlerDirectory, withIntermediateDirectories: true)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["-p", "--model", "haiku", "--no-session-persistence", "--tools", ""]
        task.currentDirectoryURL = claudeTitlerDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        task.environment = environment
        let input = Pipe()
        let output = Pipe()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = output
        do {
            try task.run()
        } catch {
            return ""
        }
        let request = "Write a 3-5 word title in sentence case for this task. Reply with the title only.\n\n" + String(prompt.prefix(1500))
        input.fileHandleForWriting.write(Data(request.utf8))
        try? input.fileHandleForWriting.close()
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        timeout.cancel()
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.localizedCaseInsensitiveContains("authenticate") || text.localizedCaseInsensitiveContains("/login") { return nil }
        guard task.terminationReason == .exit, task.terminationStatus == 0 else { return "" }
        return sanitizedClaudeTitle(text)
    }

    private static func sanitizedClaudeTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var title = line
            .replacingOccurrences(of: "^(#+|\\*+|title:)\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*“”‘’ ").union(.whitespaces))
        while let last = title.last, ".!?,;:".contains(last) { title.removeLast() }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*“”‘’ "))
        return title.count <= 60 ? title : String(title.prefix(57)).trimmingCharacters(in: .whitespaces) + "..."
    }

    private static func claudeMessageText(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let blocks = value as? [[String: Any]] else { return nil }
        let text = blocks.compactMap { block -> String? in
            guard (block["type"] as? String) == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static let claudeWrapperPrefixes = [
        "<system-reminder>", "<command-", "<local-command", "<wake", "<task-notification>"
    ]

    /// Turns a raw first prompt into readable text: skips hook/system wrappers and
    /// unwraps coordinator relay envelopes down to the person's words or the note.
    private static func claudePromptText(_ text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if claudeWrapperPrefixes.contains(where: { body.hasPrefix($0) }) { return nil }
        if body.contains("<relay") || body.contains("<coordinator-relay>") {
            body = claudeTagContent(in: body, pattern: "<cited\\b[^>]*author=\"user\"[^>]*>([\\s\\S]*?)</cited>")
                ?? claudeTagContent(in: body, pattern: "<note>([\\s\\S]*?)</note>")
                ?? body
        }
        let clean = body
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func claudeTagContent(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let content = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    /// Generic names the desktop app gives sessions started from a project; they say nothing about the work.
    private static func isPlaceholderClaudeTitle(_ title: String) -> Bool {
        let lower = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("local session") || lower == "untitled" || lower == "new session"
    }

    /// Titles the Claude desktop app keeps beside its Code sessions, keyed by CLI session id.
    private static func claudeSidecarTitles() -> [String: String] {
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return [:] }
        var titles: [String: String] = [:]
        for case let url as URL in enumerator
        where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("local_") {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = object["cliSessionId"] as? String,
                  let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  !title.hasPrefix("Remote Control session"),
                  !isPlaceholderClaudeTitle(title) else { continue }
            titles[sessionID] = title
        }
        return titles
    }

    private static func uint64(_ value: Any?) -> UInt64 {
        if let value = value as? UInt64 { return value }
        if let value = value as? Int { return UInt64(max(value, 0)) }
        if let value = value as? Double { return UInt64(max(value, 0)) }
        if let value = value as? String { return UInt64(value) ?? 0 }
        return 0
    }
}
