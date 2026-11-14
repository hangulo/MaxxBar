import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

enum AIUsageReader {
    private struct ActiveContext {
        let app: String
        let bundleID: String
        let url: String?
        let title: String?
        let site: String?
        let tool: String?
        let surface: String?
        let useCase: String
    }

    struct AIActivityRecord: Codable {
        var ts: Date
        var app: String
        var bundleID: String
        var url: String?
        var title: String?
        var site: String?
        var tool: String?
        var surface: String?
        var useCase: String
        var memoryPressurePercent: Int
        var memoryUsedPercent: Int
        var cpuUserPercent: Int
        var cpuSystemPercent: Int
        var codexFiveHourRemainingPercent: Int?
        var codexWeeklyRemainingPercent: Int?
        // Rows written before these fields existed may hold Claude values in the codex fields above.
        var claudeFiveHourRemainingPercent: Int? = nil
        var claudeWeeklyRemainingPercent: Int? = nil
    }

    struct AITransferRecord: Codable {
        var eventType: String
        var ts: Date
        var app: String
        var bundleID: String
        var site: String?
        var url: String?
        var title: String?
        var tool: String?
        var surface: String?
        var useCase: String
        var sourceApp: String?
        var sourceBundleID: String?
        var sourceSite: String?
        var sourceURL: String?
        var sourceTitle: String?
        var sourceTool: String?
        var sourceSurface: String?
        var sourceTS: Date?
        var privacy: String
    }

    nonisolated(unsafe) private static var lastCopyRecord: AITransferRecord?
    nonisolated(unsafe) private static var lastTransferSignature: String?
    nonisolated(unsafe) private static var lastTransferAt: Date?
    nonisolated(unsafe) private static var activityRecordCache: [AIActivityRecord]?
    nonisolated(unsafe) private static var transferRecordCache: [AITransferRecord]?
    private static let transferLock = NSLock()
    private static let recordCacheLock = NSLock()
    private static let transferPairingWindow: TimeInterval = 15 * 60
    private static let recordCacheRetentionDays = 7

    static func recordAndRead(memory: MemorySnapshot, cpuGPU: CPUGPUSnapshot, llmUsage: LLMUsageSnapshot) -> AIUsageSnapshot {
        let context = activeContext()
        let record = record(from: context, memory: memory, cpuGPU: cpuGPU, llmUsage: llmUsage)
        // A locked Mac reports loginwindow as the front app; those samples are noise, not activity.
        guard !isLockScreen(record) else {
            return snapshot(current: nil, error: nil)
        }
        appendActivityRecord(record)
        return snapshot(current: record, error: nil)
    }

    private static func isLockScreen(_ record: AIActivityRecord) -> Bool {
        record.bundleID == "com.apple.loginwindow" || record.app == "loginwindow"
    }

    static func recordClipboardEvent(_ eventType: String) -> AIUsageSnapshot {
        let context = activeContext()
        let now = Date()
        let signature = "\(eventType)|\(context.bundleID)|\(context.url ?? "")"

        transferLock.lock()
        defer { transferLock.unlock() }

        if lastTransferSignature == signature,
           let lastTransferAt,
           now.timeIntervalSince(lastTransferAt) < 0.75 {
            return snapshot(current: recentActivityRecords(days: 7).max { $0.ts < $1.ts }, error: nil)
        }

        let source = eventType == "paste" ? lastCopyRecord : nil
        let hasFreshSource = source.map {
            let age = now.timeIntervalSince($0.ts)
            return age >= 0 && age <= transferPairingWindow
        } ?? false
        let record = AITransferRecord(
            eventType: eventType,
            ts: now,
            app: context.app,
            bundleID: context.bundleID,
            site: context.site,
            url: context.url,
            title: context.title,
            tool: context.tool,
            surface: context.surface,
            useCase: AITaxonomy.useCase(
                before: hasFreshSource ? (source?.sourceSurface ?? source?.surface ?? source?.sourceApp ?? source?.app) : nil,
                surface: hasFreshSource ? (source?.sourceSurface ?? source?.surface) : context.surface,
                after: context.site ?? context.app
            ),
            sourceApp: hasFreshSource ? source?.app : nil,
            sourceBundleID: hasFreshSource ? source?.bundleID : nil,
            sourceSite: hasFreshSource ? source?.site : nil,
            sourceURL: hasFreshSource ? source?.url : nil,
            sourceTitle: hasFreshSource ? source?.title : nil,
            sourceTool: hasFreshSource ? source?.tool : nil,
            sourceSurface: hasFreshSource ? source?.surface : nil,
            sourceTS: hasFreshSource ? source?.ts : nil,
            privacy: "no_clipboard_content"
        )
        appendTransferRecord(record)
        if eventType == "copy" { lastCopyRecord = record }
        lastTransferSignature = signature
        lastTransferAt = now
        return snapshot(current: recentActivityRecords(days: 7).max { $0.ts < $1.ts }, error: nil)
    }

    static func writeReport() -> URL? {
        guard let url = reportURL else { return nil }
        let records = recentActivityRecords(days: 7)
        let transfers = recentTransferRecords(days: 7)
        let llmUsage = LLMUsageReader.read()
        let quotaHistory = recentQuotaHistory()
        let html = reportHTML(records: records, transfers: transfers, llmUsage: llmUsage, quotaHistory: quotaHistory)

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            writeHubIcon(to: url.deletingLastPathComponent())
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func prepareReportForOpening() -> URL? {
        guard let url = reportURL else { return nil }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try openingPlaceholderHTML(for: url).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func openingPlaceholderHTML(for url: URL) -> String {
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        let context: String
        if let modifiedAt {
            context = "Last generated \(relativeReportAge(modifiedAt)) ago. MaxxBar is collecting current Codex and Claude usage, local sessions, and transfer flows now."
        } else {
            context = "No local Hub has been generated yet. MaxxBar is collecting current Codex and Claude usage, local sessions, and transfer flows now."
        }
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="refresh" content="3">
          <title>Refreshing MaxxBar Hub</title>
          <style>
            :root{color-scheme:dark;--bg:#111316;--panel:#202634;--text:#f4f7fb;--muted:#a7b0bd;--blue:#0080ff;--line:#343c48}
            body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
            main{width:min(560px,calc(100vw - 36px));background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:24px}
            .brand{display:flex;align-items:center;gap:12px;margin-bottom:18px;font-weight:800}.brand img{width:40px;height:40px;border-radius:10px}
            h1{margin:0 0 8px;font-size:24px}p{margin:0 0 14px;color:var(--muted)}.bar{height:7px;background:#151923;border-radius:999px;overflow:hidden;margin-top:18px}
            .bar span{display:block;height:100%;width:42%;background:var(--blue);border-radius:999px;animation:load 1.35s ease-in-out infinite alternate}@keyframes load{to{transform:translateX(140%)}}
            small{display:block;margin-top:14px;color:var(--muted)}
          </style>
        </head>
        <body>
          <main>
            <div class="brand"><img src="maxxbar-hub-icon.png" alt="">MaxxBar</div>
            <h1>Refreshing the Hub</h1>
            <p>\(html(context))</p>
            <p>This page opens immediately so the menu bar does not wait on live usage data. It will refresh automatically as soon as the full Hub is ready.</p>
            <div class="bar"><span></span></div>
            <small>Copied images may be stored locally for up to 24 hours. Text clipboard contents and typed text are not stored.</small>
          </main>
        </body>
        </html>
        """
    }

    private static func relativeReportAge(_ date: Date) -> String {
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    private static func record(
        from context: ActiveContext,
        memory: MemorySnapshot,
        cpuGPU: CPUGPUSnapshot,
        llmUsage: LLMUsageSnapshot
    ) -> AIActivityRecord {
        let codexLimit = llmUsage.limits.first { $0.name == "Codex" }
        let claudeLimit = llmUsage.limits.first { $0.name == "Claude" }
        return AIActivityRecord(
            ts: Date(),
            app: context.app,
            bundleID: context.bundleID,
            url: context.url,
            title: context.title,
            site: context.site,
            tool: context.tool,
            surface: context.surface,
            useCase: context.useCase,
            memoryPressurePercent: memory.pressurePercent,
            memoryUsedPercent: memory.usedPercent,
            cpuUserPercent: cpuGPU.cpuUserPercent,
            cpuSystemPercent: cpuGPU.cpuSystemPercent,
            codexFiveHourRemainingPercent: codexLimit?.shortWindow?.remainingPercent,
            codexWeeklyRemainingPercent: codexLimit?.weeklyWindow?.remainingPercent,
            claudeFiveHourRemainingPercent: claudeLimit?.shortWindow?.remainingPercent,
            claudeWeeklyRemainingPercent: claudeLimit?.weeklyWindow?.remainingPercent
        )
    }

    private static func snapshot(current: AIActivityRecord?, error: String?) -> AIUsageSnapshot {
        let records = recentActivityRecords(days: 7)
        let transfers = recentTransferRecords(days: 7)
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let todayRecords = records.filter { $0.ts >= startOfDay }
        let aiRecords = records.filter { $0.tool != nil }
        let todayAIRecords = todayRecords.filter { $0.tool != nil }
        let sevenDaySessions = sessions(from: records)
        let todaySessions = sessions(from: todayRecords)
        let workflows = workflowCounters(from: records)
        let confidence = contextConfidence(workflows: workflows, aiRecords: aiRecords)
        let todayTransfers = transfers.filter { $0.ts >= startOfDay }
        let transferFlows = topTransferFlows(transfers)

        return AIUsageSnapshot(
            sampledAt: current?.ts,
            activeApp: current?.app ?? "Unknown",
            activeSite: current?.site,
            activeTool: current?.tool,
            activeSurface: current?.surface,
            activeUseCase: current?.useCase ?? "Unknown",
            sessionsToday: todaySessions.count,
            sessionsSevenDays: sevenDaySessions.count,
            timeTodaySeconds: inferredAISeconds(todayAIRecords),
            timeSevenDaysSeconds: inferredAISeconds(aiRecords),
            averageSessionSeconds: sevenDaySessions.isEmpty ? 0 : inferredAISeconds(aiRecords) / Double(sevenDaySessions.count),
            contextConfidence: confidence,
            topTools: counters(aiRecords.compactMap(canonicalTool), limit: 4),
            topBeforeApps: counters(workflows.map(\.before), limit: 4),
            topAfterApps: counters(workflows.map(\.after), limit: 4),
            workflowPaths: topWorkflowPaths(workflows),
            copyEventsToday: todayTransfers.filter { $0.eventType == "copy" }.count,
            pasteEventsToday: todayTransfers.filter { $0.eventType == "paste" }.count,
            topCopiedFrom: counters(transfers.filter { $0.eventType == "copy" }.map(transferSourceLabel), limit: 4),
            topPastedInto: counters(transfers.filter(isReliablePasteTransfer).map(transferDestinationLabel), limit: 4),
            transferFlows: transferFlows,
            lastError: error,
            providerSummaries: ["Codex", "Claude"].map {
                providerSummary(
                    provider: $0,
                    records: records,
                    workflows: workflows,
                    transfers: transfers,
                    startOfDay: startOfDay
                )
            }
        )
    }

    private static func providerSummary(
        provider: String,
        records: [AIActivityRecord],
        workflows: [AIWorkflowPath],
        transfers: [AITransferRecord],
        startOfDay: Date
    ) -> AIProviderUsageSummary {
        let providerRecords = records.filter { providerMatches(provider, record: $0) }
        let todayRecords = providerRecords.filter { $0.ts >= startOfDay }
        let providerSessions = sessions(from: providerRecords)
        let todaySessions = sessions(from: todayRecords)
        let providerWorkflows = workflows.filter { providerMatches(provider, tool: nil, surface: $0.surface) }
        let providerTransfers = transfers.filter { providerMatches(provider, transfer: $0) }
        let todayTransfers = providerTransfers.filter { $0.ts >= startOfDay }
        let sevenDayTime = inferredAISeconds(providerRecords)

        return AIProviderUsageSummary(
            provider: provider,
            sessionsToday: todaySessions.count,
            sessionsSevenDays: providerSessions.count,
            timeTodaySeconds: inferredAISeconds(todayRecords),
            timeSevenDaysSeconds: sevenDayTime,
            averageSessionSeconds: providerSessions.isEmpty ? 0 : sevenDayTime / Double(providerSessions.count),
            contextConfidence: contextConfidence(workflows: providerWorkflows, aiRecords: providerRecords),
            topTools: counters(providerRecords.compactMap(canonicalTool), limit: 4),
            topBeforeApps: counters(providerWorkflows.map(\.before), limit: 4),
            topAfterApps: counters(providerWorkflows.map(\.after), limit: 4),
            workflowPaths: topWorkflowPaths(providerWorkflows),
            copyEventsToday: todayTransfers.filter { $0.eventType == "copy" }.count,
            pasteEventsToday: todayTransfers.filter { $0.eventType == "paste" }.count,
            topCopiedFrom: counters(providerTransfers.filter { $0.eventType == "copy" }.map(transferSourceLabel), limit: 4),
            topPastedInto: counters(providerTransfers.filter(isReliablePasteTransfer).map(transferDestinationLabel), limit: 4),
            transferFlows: topTransferFlows(providerTransfers)
        )
    }

    static func providerMatches(_ provider: String, tool: String?, surface: String?) -> Bool {
        let value = [tool, surface].compactMap { $0?.lowercased() }.joined(separator: " ")
        if provider == "Claude" {
            return value.contains("claude")
        }
        return value.contains("codex")
    }

    static func providerMatches(_ provider: String, record: AIActivityRecord) -> Bool {
        if provider == "Codex", record.bundleID.caseInsensitiveCompare("com.openai.codex") == .orderedSame {
            return true
        }
        return providerMatches(provider, tool: record.tool, surface: record.surface)
    }

    static func providerMatches(_ provider: String, transfer: AITransferRecord) -> Bool {
        if provider == "Codex", transfer.sourceBundleID?.caseInsensitiveCompare("com.openai.codex") == .orderedSame {
            return true
        }
        return providerMatches(provider, tool: transfer.sourceTool, surface: transfer.sourceSurface)
    }

    static func canonicalTool(_ record: AIActivityRecord) -> String? {
        record.bundleID.caseInsensitiveCompare("com.openai.codex") == .orderedSame ? "Codex" : record.tool
    }

    private static func activeContext() -> ActiveContext {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        let bundleID = app?.bundleIdentifier ?? ""
        let browser = browserContext(appName: appName, bundleID: bundleID)
        let site = browser.url.flatMap(AITaxonomy.siteLabel)
        let toolInfo = AITaxonomy.tool(appName: appName, bundleID: bundleID, url: browser.url)
        let useCase = AITaxonomy.useCase(before: appName, surface: toolInfo.surface, after: site)
        return ActiveContext(
            app: site ?? appName,
            bundleID: bundleID,
            url: browser.url,
            title: browser.title,
            site: site,
            tool: toolInfo.tool,
            surface: toolInfo.surface,
            useCase: useCase
        )
    }

    private static func browserContext(appName: String, bundleID: String) -> (url: String?, title: String?) {
        guard bundleID == "com.google.Chrome" || bundleID == "com.google.Chrome.canary" || bundleID == "company.thebrowser.Browser" else {
            return (nil, nil)
        }

        let target = bundleID == "company.thebrowser.Browser" || appName.localizedCaseInsensitiveContains("Arc")
            ? "Arc"
            : "Google Chrome"
        let script = """
        tell application "\(target)"
          if (count of windows) is 0 then return ""
          set activeUrl to URL of active tab of front window
          set activeTitle to title of active tab of front window
          return activeUrl & "\n" & activeTitle
        end tell
        """
        let output = runProcess("/usr/bin/osascript", arguments: ["-e", script])
        let parts = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let url = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (url?.isEmpty == true ? nil : url, title?.isEmpty == true ? nil : title)
    }

    private static func siteLabel(_ url: String) -> String? {
        AITaxonomy.siteLabel(url)
    }

    private static func useCase(before: String?, surface: String?, after: String?) -> String {
        AITaxonomy.useCase(before: before, surface: surface, after: after)
    }

    static func sessions(from records: [AIActivityRecord]) -> [[AIActivityRecord]] {
        let aiRecords = records.filter { $0.tool != nil }.sorted { $0.ts < $1.ts }
        var sessions: [[AIActivityRecord]] = []
        for record in aiRecords {
            if let last = sessions.last?.last, record.ts.timeIntervalSince(last.ts) <= 300 {
                sessions[sessions.count - 1].append(record)
            } else {
                sessions.append([record])
            }
        }
        return sessions
    }

    static func inferredAISeconds(_ records: [AIActivityRecord]) -> TimeInterval {
        let sorted = records.sorted { $0.ts < $1.ts }
        guard !sorted.isEmpty else { return 0 }
        var total: TimeInterval = 0
        for index in sorted.indices {
            if index < sorted.index(before: sorted.endIndex) {
                total += min(max(sorted[sorted.index(after: index)].ts.timeIntervalSince(sorted[index].ts), 15), 120)
            } else {
                total += 15
            }
        }
        return total
    }

    static func workflowCounters(from records: [AIActivityRecord]) -> [AIWorkflowPath] {
        let sorted = records.sorted { $0.ts < $1.ts }
        var counts: [String: (before: String, surface: String, after: String, useCase: String, count: Int)] = [:]

        for run in aiRuns(in: sorted) {
            let before = nearestNonAI(in: sorted, from: run.start, step: -1, within: 600) ?? "Start"
            let after = nearestNonAI(in: sorted, from: run.end, step: 1, within: 600) ?? "End"
            let surface = sorted[run.start].bundleID.caseInsensitiveCompare("com.openai.codex") == .orderedSame
                ? "Codex client"
                : (sorted[run.start].surface ?? sorted[run.start].tool ?? "AI")
            let useCase = useCase(before: before, surface: surface, after: after)
            let key = "\(before)|\(surface)|\(after)|\(useCase)"
            var current = counts[key] ?? (before, surface, after, useCase, 0)
            current.count += 1
            counts[key] = current
        }

        return counts.values.map {
            AIWorkflowPath(before: $0.before, surface: $0.surface, after: $0.after, useCase: $0.useCase, count: $0.count)
        }
    }

    private static func aiRuns(in records: [AIActivityRecord]) -> [(start: Int, end: Int)] {
        var runs: [(start: Int, end: Int)] = []
        for index in records.indices where records[index].tool != nil {
            if let last = runs.last,
               records[index].ts.timeIntervalSince(records[last.end].ts) <= 300 {
                runs[runs.count - 1] = (last.start, index)
            } else {
                runs.append((index, index))
            }
        }
        return runs
    }

    private static func nearestNonAI(in records: [AIActivityRecord], from index: Int, step: Int, within seconds: TimeInterval) -> String? {
        var cursor = index + step
        let anchor = records[index].ts
        while records.indices.contains(cursor) {
            if records[cursor].tool == nil {
                guard abs(records[cursor].ts.timeIntervalSince(anchor)) <= seconds else { return nil }
                return records[cursor].site ?? records[cursor].app
            }
            cursor += step
        }
        return nil
    }

    static func counters(_ values: [String], limit: Int) -> [AIUsageCounter] {
        let counts = Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(limit)
            .map { AIUsageCounter(label: $0.key, count: $0.value) }
    }

    static func topWorkflowPaths(_ workflows: [AIWorkflowPath]) -> [AIWorkflowPath] {
        workflows
            .sorted { lhs, rhs in lhs.count == rhs.count ? lhs.id < rhs.id : lhs.count > rhs.count }
            .prefix(6)
            .map { $0 }
    }

    static func topTransferFlows(_ transfers: [AITransferRecord]) -> [AITransferFlow] {
        let pasteEvents = transfers.filter(isReliablePasteTransfer)
        var counts: [String: (source: String, destination: String, useCase: String, count: Int)] = [:]
        for event in pasteEvents {
            let source = event.sourceSurface ?? event.sourceTool ?? event.sourceSite ?? event.sourceApp ?? "Unknown"
            let destination = transferDestinationLabel(event)
            let key = "\(source)|\(destination)|\(event.useCase)"
            var value = counts[key] ?? (source, destination, event.useCase, 0)
            value.count += 1
            counts[key] = value
        }
        return counts.values
            .sorted { lhs, rhs in lhs.count == rhs.count ? lhs.destination < rhs.destination : lhs.count > rhs.count }
            .prefix(8)
            .map { AITransferFlow(source: $0.source, destination: $0.destination, useCase: $0.useCase, count: $0.count, confidence: "High") }
    }

    static func isReliablePasteTransfer(_ record: AITransferRecord) -> Bool {
        guard record.eventType == "paste",
              record.sourceTool != nil,
              let sourceTS = record.sourceTS else {
            return false
        }
        let delay = record.ts.timeIntervalSince(sourceTS)
        guard delay >= 0, delay <= transferPairingWindow else { return false }
        return !isSameAIProviderTransfer(record)
    }

    private static func isSameAIProviderTransfer(_ record: AITransferRecord) -> Bool {
        let source = aiProviderIdentity(
            tool: record.sourceTool,
            surface: record.sourceSurface,
            bundleID: record.sourceBundleID
        )
        let destination = aiProviderIdentity(
            tool: record.tool,
            surface: record.surface,
            bundleID: record.bundleID
        )
        return source != nil && source == destination
    }

    private static func aiProviderIdentity(
        tool: String?,
        surface: String?,
        bundleID: String?
    ) -> String? {
        if bundleID?.caseInsensitiveCompare("com.openai.codex") == .orderedSame {
            return "codex"
        }
        let value = [tool, surface, bundleID]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if value.contains("claude") || value.contains("anthropic") {
            return "claude"
        }
        if value.contains("codex") {
            return "codex"
        }
        return nil
    }

    private static func transferSourceLabel(_ record: AITransferRecord) -> String {
        record.surface ?? record.tool ?? record.site ?? record.app
    }

    static func transferDestinationLabel(_ record: AITransferRecord) -> String {
        record.surface ?? record.tool ?? record.site ?? record.app
    }

    private static func contextConfidence(workflows: [AIWorkflowPath], aiRecords: [AIActivityRecord]) -> String {
        guard !aiRecords.isEmpty else { return "None" }
        if workflows.contains(where: { $0.before != "Start" && $0.after != "End" }) { return "High" }
        if workflows.contains(where: { $0.before != "Start" || $0.after != "End" }) { return "Medium" }
        return "Low"
    }

    private static func recentActivityRecords(days: Int) -> [AIActivityRecord] {
        recordCacheLock.lock()
        if activityRecordCache == nil {
            activityRecordCache = readJSONLines(
                AIActivityRecord.self,
                from: activityLogURL,
                days: recordCacheRetentionDays
            )
        }
        let now = Date()
        let retentionCutoff = now.addingTimeInterval(-Double(recordCacheRetentionDays) * 86_400)
        let retainedRecords = (activityRecordCache ?? []).filter { $0.ts >= retentionCutoff && !isLockScreen($0) }
        activityRecordCache = retainedRecords
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let records = retainedRecords.filter { $0.ts >= cutoff }
        recordCacheLock.unlock()
        return records
    }

    private static func recentTransferRecords(days: Int) -> [AITransferRecord] {
        recordCacheLock.lock()
        if transferRecordCache == nil {
            transferRecordCache = readJSONLines(
                AITransferRecord.self,
                from: transfersLogURL,
                days: recordCacheRetentionDays
            )
        }
        let now = Date()
        let retentionCutoff = now.addingTimeInterval(-Double(recordCacheRetentionDays) * 86_400)
        let retainedRecords = (transferRecordCache ?? []).filter { $0.ts >= retentionCutoff }
        transferRecordCache = retainedRecords
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let records = retainedRecords.filter { $0.ts >= cutoff }
        recordCacheLock.unlock()
        return records
    }

    private static func appendActivityRecord(_ record: AIActivityRecord) {
        recordCacheLock.lock()
        append(record, to: activityLogURL)
        activityRecordCache?.append(record)
        recordCacheLock.unlock()
    }

    private static func appendTransferRecord(_ record: AITransferRecord) {
        recordCacheLock.lock()
        append(record, to: transfersLogURL)
        transferRecordCache?.append(record)
        recordCacheLock.unlock()
    }

    private static func recentQuotaHistory() -> [LLMQuotaHistorySample] {
        guard let directory = supportDirectoryURL,
              let data = try? Data(contentsOf: directory.appendingPathComponent("llm-quota-history.json")),
              let samples = try? JSONDecoder().decode([LLMQuotaHistorySample].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return samples.filter { $0.sampledAt >= cutoff }.sorted { $0.sampledAt < $1.sampledAt }
    }

    /// Reads the file backwards in 1 MB chunks and stops at the first record older than the cutoff,
    /// so a large log costs only its recent tail instead of a full read at every launch.
    private static func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL?, days: Int) -> [T] {
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else {
            return []
        }
        defer { try? handle.close() }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [T] = []
        var offset = (try? handle.seekToEnd()) ?? 0
        var carry = Data()
        let chunkSize: UInt64 = 1 << 20
        reading: while offset > 0 {
            let start = offset >= chunkSize ? offset - chunkSize : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let chunk = try? handle.read(upToCount: Int(offset - start)) else { break }
            offset = start
            var buffer = chunk
            buffer.append(carry)
            var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
            // The first piece may be a partial line; keep it for the next chunk unless this is the file start.
            carry = offset > 0 && !lines.isEmpty ? lines.removeFirst() : Data()
            for lineData in lines.reversed() {
                guard let record = try? decoder.decode(T.self, from: lineData) else {
                    continue
                }
                let timestamp: Date?
                if let activity = record as? AIActivityRecord {
                    timestamp = activity.ts
                } else if let transfer = record as? AITransferRecord {
                    timestamp = transfer.ts
                } else {
                    timestamp = nil
                }
                if let timestamp, timestamp < cutoff {
                    break reading
                }
                records.append(record)
            }
        }
        return records.reversed()
    }

    private static func append<T: Encodable>(_ value: T, to url: URL?) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        } catch {
            return
        }
    }

    private static func runProcess(_ path: String, arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static var supportDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MaxxBar", isDirectory: true)
    }

    static var activityLogURL: URL? {
        supportDirectoryURL?.appendingPathComponent("ai-activity.jsonl")
    }

    static var transfersLogURL: URL? {
        supportDirectoryURL?.appendingPathComponent("ai-transfers.jsonl")
    }

    private static var reportURL: URL? {
        supportDirectoryURL?.appendingPathComponent("maxxbar-hub.html")
    }

    private static func writeHubIcon(to directory: URL) {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            sourceRoot.appendingPathComponent("Assets/AppIcon.iconset/icon_128x128.png"),
            FileManager.default.currentDirectoryPath.isEmpty ? nil : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/AppIcon.iconset/icon_128x128.png")
        ].compactMap { $0 }

        guard let source = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: source) else { return }

        let size = NSSize(width: 96, height: 96)
        let rendered = NSImage(size: size)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        rendered.unlockFocus()

        guard let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("maxxbar-hub-icon.png"), options: .atomic)
    }
}
