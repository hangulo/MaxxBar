import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

extension AIUsageReader {
    static func reportHTML(records: [AIActivityRecord], moments: [MaxxMomentRecord], transfers: [AITransferRecord], llmUsage: LLMUsageSnapshot, quotaHistory: [LLMQuotaHistorySample]) -> String {
        let aiRecords = records.filter { $0.tool != nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayAIRecords = aiRecords.filter { $0.ts >= startOfDay }
        let topTools = counters(aiRecords.compactMap(canonicalTool), limit: 8)
        let todayTools = counters(todayAIRecords.compactMap(canonicalTool), limit: 8)
        let useCases = counters(aiRecords.map(\.useCase), limit: 8)
        let outputDestinations = counters(transfers.filter(isReliablePasteTransfer).map(transferDestinationLabel), limit: 8)
        let totalAISeconds = inferredAISeconds(aiRecords)
        let sessionCount = sessions(from: records).count
        let todaySessionCount = sessions(from: todayAIRecords).count
        let todayTransferEventCount = transfers.filter { $0.ts >= startOfDay }.count
        let insightEventCount = todaySessionCount + todayTransferEventCount
        let latest = records.sorted { $0.ts < $1.ts }.last
        let codexLimit = llmUsage.limits.first(where: { $0.name == "Codex" }) ?? llmUsage.limits.first
        let remaining = codexLimit?.shortWindow?.remainingPercent ?? codexLimit?.weeklyWindow?.remainingPercent
        let runwayLabel = remaining.map { $0 <= 10 ? "Critical" : ($0 <= 25 ? "Watch" : "Healthy") } ?? "Unavailable"
        let runwayValue = llmUsage.limits
            .filter { $0.name == "Codex" || $0.name == "Claude" }
            .compactMap { limit -> String? in
                guard let value = limit.shortWindow?.remainingPercent ?? limit.weeklyWindow?.remainingPercent else { return nil }
                return "\(limit.name) \(value)%"
            }
            .joined(separator: " · ")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>MaxxBar Hub</title>
          <link rel="icon" type="image/png" href="maxxbar-hub-icon.png">
          <style>
            :root{color-scheme:dark;--bg:#111315;--panel:#181b1e;--panel2:#21252a;--text:#f0f2f5;--muted:#b8bec7;--line:#2d3135;--line2:#3a3f46;--accent:#0080ff;--top:rgba(17,19,21,.92)}
            :root[data-theme=light]{color-scheme:light;--bg:#faf8f3;--panel:#fff;--panel2:#f3f0e9;--text:#20231f;--muted:#646a61;--line:#ddd9cf;--line2:#cbc6ba;--accent:#0078f0;--top:rgba(250,248,243,.92)}
            *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;line-height:1.45}
            .topline{position:sticky;top:0;z-index:10;min-height:64px;display:flex;align-items:center;gap:18px;padding:0 30px;background:var(--top);border-bottom:1px solid var(--line);backdrop-filter:blur(14px)}.brand{display:flex;align-items:center;gap:10px;font-weight:750}.brand-logo{width:38px;height:38px;display:block;border-radius:10px;object-fit:cover}.tabs{display:flex;gap:4px}.tabs a{color:var(--muted);text-decoration:none;padding:7px 10px;border-radius:7px;font-size:12px;font-weight:700}.tabs a:hover{background:var(--panel2);color:var(--text)}.spacer{flex:1}.theme{border:1px solid var(--line2);background:var(--panel2);color:var(--text);border-radius:8px;padding:7px 10px;cursor:pointer}.content{max-width:1280px;margin:auto;padding:28px 30px 48px}
            h1{margin:0 0 4px;font-size:30px}h2{font-size:15px;text-transform:uppercase;letter-spacing:0;margin:0 0 12px;color:var(--accent)}
            .sub{color:var(--muted);margin:0 0 22px}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:18px}.card,.panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px}.card span{display:block;color:var(--muted);font-size:12px}.card strong{display:block;font-size:24px;margin-top:4px}.two{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:18px}.list div{display:flex;justify-content:space-between;gap:16px;padding:8px 0;border-bottom:1px solid var(--line)}.list div:last-child{border-bottom:0}.list span{color:var(--muted);font-variant-numeric:tabular-nums}.paths div,.ai-path-top div{display:flex;align-items:center;gap:7px;flex-wrap:wrap;padding:8px 0;border-bottom:1px solid var(--line);color:var(--muted);font-size:12px}.paths em,.ai-path-top em{font:700 10px/1 ui-monospace,SFMono-Regular,Menlo,monospace;font-style:normal;color:var(--muted)}.paths span,.ai-path-top span{color:var(--accent);font-weight:900}.ai-path-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:12px}.ai-path-head h2{margin:0 0 6px}.ai-path-head p{margin:0;color:var(--muted)}.ai-path-head strong{font:800 12px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--accent);background:rgba(0,128,255,.10);border-radius:999px;padding:7px 10px;white-space:nowrap}.ai-sankey-wrap{overflow:hidden;border:1px solid var(--line);border-radius:8px;background:var(--panel2);padding:10px}.ai-sankey{display:block;width:100%;height:auto}.ai-sankey-stage{fill:var(--muted);font:800 11px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:0;text-transform:uppercase}.ai-sankey-link{fill:none;stroke:var(--accent);stroke-linecap:round;opacity:.18}.ai-sankey-link:hover{opacity:.38}.ai-sankey-node{fill:var(--accent);opacity:.68}.ai-sankey-icon text{font:800 8px/1 ui-monospace,SFMono-Regular,Menlo,monospace}.ai-sankey-label{fill:var(--text);font:700 12px/1 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}.ai-sankey-count{fill:var(--muted);font:700 10px/1 ui-monospace,SFMono-Regular,Menlo,monospace}.ai-path-top{display:grid;gap:2px;margin-top:12px}.footer{margin-top:20px;color:var(--muted);font-size:12px}.flows{display:grid;gap:8px}.flow{display:grid;grid-template-columns:minmax(0,1fr) 24px minmax(0,1fr) auto;gap:8px;align-items:center;padding:10px;background:var(--panel2);border-radius:7px}.arrow{color:var(--accent);font-weight:900}.badge{font:750 10px ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--accent)}@media(max-width:760px){.topline{padding:12px 18px;flex-wrap:wrap}.tabs{order:3;width:100%;overflow:auto}.content{padding:22px 18px}.grid,.two{grid-template-columns:1fr 1fr}.flow{grid-template-columns:1fr 20px 1fr}.flow .badge{grid-column:1/-1}}
            .tabs button{border:0;background:transparent;color:var(--muted);padding:8px 11px;border-radius:7px;font:700 12px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;cursor:pointer;white-space:nowrap}.tabs button:hover{background:var(--panel2);color:var(--text)}.tabs button.active{background:var(--accent);color:white}.hub-page{display:none}.hub-page.active{display:block}.page-head{margin:0 0 22px;padding-bottom:18px;border-bottom:1px solid var(--line)}.page-head h1{font-size:32px;margin:0 0 6px}.page-head p{margin:0;color:var(--muted);max-width:760px}.page-kicker{display:block;color:var(--accent);font:800 11px ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:0;text-transform:uppercase;margin-bottom:7px}.panel{margin-bottom:18px}.meter{height:8px;background:var(--panel2);border-radius:99px;overflow:hidden;margin:7px 0 4px}.meter span{display:block;height:100%;background:var(--accent);border-radius:99px}.metric-row{display:grid;grid-template-columns:minmax(190px,1fr) minmax(160px,2fr) auto;gap:14px;align-items:center;padding:10px 0;border-bottom:1px solid var(--line)}.metric-row:last-child{border-bottom:0}.metric-row small,.detail-grid dt{color:var(--muted)}.metric-row strong,.num{font-variant-numeric:tabular-nums}.metric-row .window-label strong,.metric-row .window-label small{display:block}.metric-row .window-label small{margin-top:2px}.timeline{display:grid;gap:9px}.timeline-session{background:var(--panel);border:1px solid var(--line);border-radius:8px;overflow:hidden}.timeline-session summary{list-style:none;cursor:pointer}.timeline-session summary::-webkit-details-marker{display:none}.timeline-session[open] summary{border-bottom:1px solid var(--line)}.timeline-row{display:grid;grid-template-columns:minmax(150px,240px) 1fr auto;gap:12px;align-items:center;padding:12px 14px}.timeline-label strong,.timeline-label small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.timeline-label small{color:var(--muted)}.timeline-track{position:relative;height:18px;background:var(--panel2);border-radius:5px;overflow:hidden}.timeline-bar{position:absolute;top:3px;height:12px;min-width:3px;background:var(--accent);border-radius:4px}.session-list{display:grid;gap:9px}.session{background:var(--panel);border:1px solid var(--line);border-radius:8px;overflow:hidden}.session summary{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:18px;padding:14px;cursor:pointer;list-style:none}.session summary::-webkit-details-marker{display:none}.session summary strong,.session summary small{display:block}.session summary small{color:var(--muted);margin-top:3px}.session[open] summary{border-bottom:1px solid var(--line)}.session-body{padding:14px}.detail-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px 18px;margin:0}.detail-grid div{padding:7px 0;border-bottom:1px solid var(--line)}.detail-grid dt{font-size:11px}.detail-grid dd{margin:3px 0 0;font-weight:650;word-break:break-word}.preview{margin:14px 0 0;padding:12px;background:var(--panel2);border-radius:7px;color:var(--muted);white-space:pre-wrap}.data-table{width:100%;border-collapse:collapse}.data-table th,.data-table td{text-align:left;padding:9px 8px;border-bottom:1px solid var(--line)}.data-table th{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:0}.data-table td.num,.data-table th.num{text-align:right}.quota-chart{width:100%;height:auto;display:block;background:var(--panel2);border-radius:8px}.quota-primary{fill:none;stroke:var(--accent);stroke-width:3}.quota-weekly{fill:none;stroke:#8bb4ff;stroke-width:2}.chart-grid{stroke:var(--line);stroke-width:1}.legend{display:flex;gap:16px;color:var(--muted);font-size:12px;margin-top:8px}.dot{width:8px;height:8px;border-radius:50%;display:inline-block;margin-right:5px}
            .content{padding:18px 24px 34px}.page-head{margin-bottom:12px;padding-bottom:10px}.page-head h1{font-size:28px;margin-bottom:4px}.page-kicker{margin-bottom:4px}.grid{gap:8px;margin-bottom:10px}.card,.panel{padding:10px 12px}.two{gap:8px;margin-bottom:10px;align-items:start}.list div{padding:5px 0}.panel{margin-bottom:10px}.sub{margin-bottom:10px}.footer{margin-top:14px}.scope-toggle{display:inline-flex;gap:3px;padding:3px;background:var(--panel2);border:1px solid var(--line);border-radius:8px;margin:0 0 10px}.scope-toggle button{border:0;background:transparent;color:var(--muted);padding:5px 12px;border-radius:6px;font:750 11px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;cursor:pointer}.scope-toggle button.active{background:var(--accent);color:white}.insight-scope{display:none}.insight-scope.active{display:block}.model-summary{color:var(--muted);margin:0 0 8px;font-size:12px}.model-usage{display:grid;gap:2px}.model-row{display:grid;grid-template-columns:minmax(180px,1.4fr) minmax(160px,2fr) 44px;gap:14px;align-items:center;padding:8px 0;border-bottom:1px solid var(--line)}.model-row:last-child{border-bottom:0}.model-label strong,.model-label span{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.model-label span{color:var(--muted);font-size:11px;margin-top:2px}.model-meter{height:7px;background:var(--panel2);border-radius:99px;overflow:hidden}.model-meter span{display:block;height:100%;background:var(--accent);border-radius:99px}
            @media(max-width:760px){.content{padding:16px 14px}.grid,.two{grid-template-columns:1fr}.detail-grid{grid-template-columns:1fr 1fr}.timeline-row{grid-template-columns:110px 1fr}.timeline-row>.num{display:none}.metric-row{grid-template-columns:1fr auto}.metric-row>.meter-wrap{grid-column:1/-1;grid-row:2}.model-row{grid-template-columns:minmax(0,1fr) 42px}.model-meter{grid-column:1/-1;grid-row:2}.tabs button{padding:7px 9px}}
          </style>
        </head>
        <body>
          <header class="topline"><div class="brand"><img class="brand-logo" src="maxxbar-hub-icon.png" alt="">MaxxBar</div><nav class="tabs"><button data-page="overview" onclick="showPage('overview')">Overview</button><button data-page="insights" onclick="showPage('insights')">AI Insights</button><button data-page="runway" onclick="showPage('runway')">Runway</button><button data-page="sessions" onclick="showPage('sessions')">Sessions</button></nav><span class="spacer"></span><button class="theme" onclick="toggleTheme()">Light / Dark</button></header>
          <main class="content">
          <section id="page-overview" class="hub-page">
            \(pageHeading("Overview", "The complete daily picture: current AI work, runway, patterns, transfers, and recent sessions."))
            <div class="grid">
              \(card("AI sessions today", "\(todaySessionCount)", "\(sessionCount) in 7 days"))
              \(card("AI time", duration(totalAISeconds), "sample-inferred · 7 days"))
              \(card("AI transfers", "\(transfers.filter(isReliablePasteTransfer).count)", "recent cross-app destinations"))
              \(card("Insight events today", "\(insightEventCount)", "sessions · copy/paste"))
              \(card("Active", html(latest?.tool ?? latest?.app ?? "Unknown"), html(latest?.surface ?? latest?.site ?? "latest sample")))
              \(card("AI runway", runwayValue.isEmpty ? "—" : html(runwayValue), runwayLabel))
            </div>
            \(panel("Pattern Summary", patternSummary(todayTools: todayTools, weeklyTools: topTools, useCases: useCases, destinations: outputDestinations)))
            <div class="two">\(panel("Today’s AI Tools", list(todayTools)))\(panel("7-day AI Tools", list(topTools)))</div>
          </section>

          <section id="page-insights" class="hub-page">
            \(pageHeading("AI Insights", "Which models you use, how usage is distributed, how AI enters your work, and where generated output goes afterward."))
            <div class="scope-toggle"><button data-insight-filter="all" onclick="showInsightScope('all')">All</button><button data-insight-filter="codex" onclick="showInsightScope('codex')">Codex</button><button data-insight-filter="claude" onclick="showInsightScope('claude')">Claude</button></div>
            <div class="insight-scope" data-insight-scope="all">\(insightPanels(records: records, transfers: transfers, llmUsage: llmUsage, provider: nil, startOfDay: startOfDay))</div>
            <div class="insight-scope" data-insight-scope="codex">\(insightPanels(records: records, transfers: transfers, llmUsage: llmUsage, provider: "Codex", startOfDay: startOfDay))</div>
            <div class="insight-scope" data-insight-scope="claude">\(insightPanels(records: records, transfers: transfers, llmUsage: llmUsage, provider: "Claude", startOfDay: startOfDay))</div>
          </section>

          <section id="page-runway" class="hub-page">
            \(pageHeading("Runway", "Live Codex and Claude limits, Codex drawdown history, combined local usage windows, and the same session timeline available in the menu bar."))
            \(limitPanels(llmUsage))
            \(panel("Limit Drawdown · 7 days", quotaChart(quotaHistory, fallback: llmUsage)))
            \(panel("Session Timeline · 24 hours", sessionTimeline(llmUsage)))
          </section>

          <section id="page-sessions" class="hub-page">
            \(pageHeading("Sessions", "All locally discovered Codex and Claude sessions. Expand any row for token, cache, cost, timing, provider, model, project, and preview detail."))
            \(sessionAccordions(llmUsage))
          </section>

          <div class="footer">Activity: \(html(activityLogURL?.path ?? "-"))<br>Transfers: \(html(transfersLogURL?.path ?? "-"))</div>
          </main>
          <script>
          function toggleTheme(){var r=document.documentElement;r.dataset.theme=r.dataset.theme==='light'?'dark':'light';localStorage.setItem('maxxbar:hub:theme',r.dataset.theme)}
          function showPage(name){var page=document.getElementById('page-'+name);if(!page)name='overview';document.querySelectorAll('.hub-page').forEach(function(el){el.classList.toggle('active',el.id==='page-'+name)});document.querySelectorAll('[data-page]').forEach(function(el){el.classList.toggle('active',el.dataset.page===name)});history.replaceState(null,'','#'+name);window.scrollTo(0,0)}
          function showInsightScope(name){if(!document.querySelector('[data-insight-scope="'+name+'"]'))name='all';document.querySelectorAll('[data-insight-scope]').forEach(function(el){el.classList.toggle('active',el.dataset.insightScope===name)});document.querySelectorAll('[data-insight-filter]').forEach(function(el){el.classList.toggle('active',el.dataset.insightFilter===name)});localStorage.setItem('maxxbar:hub:insight-scope',name)}
          document.documentElement.dataset.theme=localStorage.getItem('maxxbar:hub:theme')||'dark';showInsightScope(localStorage.getItem('maxxbar:hub:insight-scope')||'all');showPage((location.hash||'#overview').slice(1));
          </script>
        </body>
        </html>
        """
    }

    private static func insightPanels(
        records: [AIActivityRecord],
        transfers: [AITransferRecord],
        llmUsage: LLMUsageSnapshot,
        provider: String?,
        startOfDay: Date
    ) -> String {
        let providerRecords = records.filter { record in
            record.tool != nil && (provider == nil || providerMatches(provider!, record: record))
        }
        let providerTransfers = transfers.filter { transfer in
            provider == nil || providerMatches(provider!, transfer: transfer)
        }
        let allWorkflows = topWorkflowPaths(workflowCounters(from: records))
        let workflows = provider.map { selected in
            allWorkflows.filter { providerMatches(selected, tool: nil, surface: $0.surface) }
        } ?? allWorkflows
        let todayRecords = providerRecords.filter { $0.ts >= startOfDay }
        let todayTools = counters(todayRecords.compactMap(canonicalTool), limit: 8)
        let weeklyTools = counters(providerRecords.compactMap(canonicalTool), limit: 8)
        let useCases = counters(providerRecords.map(\.useCase), limit: 8)
        let flows = topTransferFlows(providerTransfers)
        let destinations = counters(
            providerTransfers
                .filter(isReliablePasteTransfer)
                .map(transferDestinationLabel),
            limit: 8
        )
        let before = counters(workflows.map(\.before), limit: 8)
        let after = counters(workflows.map(\.after), limit: 8)

        return """
        \(modelUsagePanel(llmUsage, provider: provider))
        <div class="two">\(panel("Today’s AI Tools", list(todayTools)))\(panel("7-day AI Tools", list(weeklyTools)))</div>
        \(panel("AI Output Destinations", transferRows(flows)))
        <div class="two">\(panel("Likely Use Cases · 7 days", list(useCases)))\(panel("Where AI Output Went", list(destinations)))</div>
        <div class="two">\(panel("Before AI", list(before)))\(panel("After AI", list(after)))</div>
        \(pathVisual(workflows))
        """
    }

    private static func modelUsagePanel(_ snapshot: LLMUsageSnapshot, provider: String?) -> String {
        let summary = snapshot.modelUsageSummary(provider: provider)
        guard !summary.models.isEmpty else {
            return panel("Model Usage · 7 days", "<p class=\"sub\">No local model context found in the last seven days.</p>")
        }
        let rows = summary.models.map { model in
            let barColor = model.provider.caseInsensitiveCompare("Claude") == .orderedSame ? "#e0815c" : "var(--accent)"
            return """
            <div class="model-row">
              <div class="model-label"><strong>\(html(model.modelName))</strong><span>\(html(model.provider)) · \(model.sessionCount) session\(model.sessionCount == 1 ? "" : "s") · \(compactTokenCount(model.tokens)) tokens</span></div>
              <div class="model-meter"><span style="width:\(model.sharePercent)%;background:\(barColor)"></span></div>
              <strong class="num">\(model.sharePercent == 0 && model.tokens > 0 ? "&lt;1%" : "\(model.sharePercent)%")</strong>
            </div>
            """
        }.joined()
        let context = "\(summary.sessionCount) sessions · \(compactTokenCount(summary.totalTokens)) recorded tokens · distribution by \(summary.distributionBasis)"
        return panel("Model Usage · 7 days", "<p class=\"model-summary\">\(html(context))</p><div class=\"model-usage\">\(rows)</div>")
    }

    private static func card(_ title: String, _ value: String, _ subtitle: String) -> String {
        "<div class=\"card\"><span>\(html(title))</span><strong>\(value)</strong><span>\(html(subtitle))</span></div>"
    }

    private static func panel(_ title: String, _ body: String) -> String {
        "<div class=\"panel\"><h2>\(html(title))</h2>\(body)</div>"
    }

    private static func list(_ rows: [AIUsageCounter]) -> String {
        guard !rows.isEmpty else { return "<p class=\"sub\">No local signals yet.</p>" }
        return "<div class=\"list\">" + rows.map { "<div><strong>\(html($0.label))</strong><span>\($0.count)</span></div>" }.joined() + "</div>"
    }

    private static func pathRows(_ paths: [AIWorkflowPath]) -> String {
        guard !paths.isEmpty else { return "<p class=\"sub\">No before -> AI -> after paths yet.</p>" }
        return "<div class=\"paths\">" + paths.map {
            "<div><strong>\(html($0.before)) -> \(html($0.surface)) -> \(html($0.after))</strong><em>\(html($0.useCase))</em><span>\($0.count)x</span></div>"
        }.joined() + "</div>"
    }

    private static func transferRows(_ flows: [AITransferFlow]) -> String {
        guard !flows.isEmpty else {
            let message = CGPreflightListenEventAccess()
                ? "Input Monitoring is enabled. No new AI-to-work-app copy/paste pairs have been captured on this Mac yet."
                : "No AI copy/paste destinations yet. Grant Input Monitoring, then copy from an AI surface and paste into a work app."
            return "<p class=\"sub\">\(html(message))</p>"
        }
        return "<div class=\"flows\">" + flows.map {
            "<div class=\"flow\"><strong>\(html($0.source))</strong><span class=\"arrow\">→</span><strong>\(html($0.destination))</strong><span class=\"badge\">\(html($0.useCase)) · \($0.count)x · \(html($0.confidence))</span></div>"
        }.joined() + "</div>"
    }

    private static func patternSummary(todayTools: [AIUsageCounter], weeklyTools: [AIUsageCounter], useCases: [AIUsageCounter], destinations: [AIUsageCounter]) -> String {
        let today = todayTools.first?.label ?? "no detected AI tool"
        let week = weeklyTools.first?.label ?? "no detected AI tool"
        let useCase = useCases.first?.label ?? "no inferred workflow"
        let destination = destinations.first?.label ?? "no confirmed output destination"
        return "<p class=\"sub\">Today’s leading surface is <strong>\(html(today))</strong>. Across seven days, <strong>\(html(week))</strong> leads, the most common inferred work is <strong>\(html(useCase))</strong>, and the top confirmed output destination is <strong>\(html(destination))</strong>.</p>"
    }

    private static func sessionRows(_ sessions: [LLMUsageSession]) -> String {
        guard !sessions.isEmpty else { return "<p class=\"sub\">No recent local Codex or Claude sessions found.</p>" }
        return "<div class=\"list\">" + sessions.prefix(8).map {
            let title = $0.title.isEmpty ? ($0.projectName.isEmpty ? "Untitled session" : $0.projectName) : $0.title
            return "<div><strong>\(html(short(title)))</strong><span>\(html($0.provider)) · \(html($0.projectName)) · \(compactTokenCount($0.tokens)) tokens</span></div>"
        }.joined() + "</div>"
    }

    private static func compactTokenCount(_ tokens: UInt64) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    private static func pageHeading(_ title: String, _ description: String) -> String {
        "<header class=\"page-head\"><span class=\"page-kicker\">MaxxBar Hub</span><h1>\(html(title))</h1><p>\(html(description))</p></header>"
    }

    private static func momentRows(_ moments: [MaxxMomentRecord]) -> String {
        let recent = moments.sorted { $0.ts > $1.ts }.prefix(8)
        guard !recent.isEmpty else { return "<p class=\"sub\">No Maxx Moments captured in the last seven days.</p>" }
        return "<div class=\"moments\">" + recent.map { moment in
            let context = moment.surface ?? moment.tool ?? moment.site ?? moment.app
            return "<div class=\"moment\"><strong>\(html(moment.sentiment ?? "Moment"))</strong><div><strong>\(html(moment.note))</strong><span>\(html(context))</span></div><span>\(html(hubDate(moment.ts)))</span></div>"
        }.joined() + "</div>"
    }

    private static func limitPanels(_ snapshot: LLMUsageSnapshot) -> String {
        guard !snapshot.limits.isEmpty else { return panel("Live Limits", "<p class=\"sub\">\(html(snapshot.error ?? "Codex usage unavailable"))</p>") }
        let limits = snapshot.limits.map { limit in
            let rows = [limit.shortWindow, limit.weeklyWindow].compactMap { $0 }.map(usageWindowRow).joined()
            return panel(limit.name + " Limits", rows)
        }.joined()
        let credits = snapshot.resetCreditCount.map { count in
            let expirations = snapshot.resetCreditExpirations.map { "\($0.count) · \(hubDate($0.expiresAt))" }.joined(separator: " · ")
            return card("Reset credits", "\(count)", expirations.isEmpty ? "expiration detail unavailable" : expirations)
        } ?? ""
        let statuses = snapshot.providerErrors.isEmpty ? "" : panel(
            "Provider Status",
            "<div class=\"list\">" + snapshot.providerErrors.sorted { $0.key < $1.key }.map { "<div><strong>\(html($0.key))</strong><span>\(html($0.value))</span></div>" }.joined() + "</div>"
        )
        return "<div class=\"grid\">\(card("Plan", html(snapshot.planType ?? "Unknown"), html(snapshot.email ?? "local account")))\(card("Last updated", html(snapshot.lastUpdated.map(hubDate) ?? "—"), "live usage API"))\(credits)</div>\(limits)\(statuses)"
    }

    private static func usageWindowRow(_ window: LLMUsageWindow) -> String {
        let remaining = min(max(window.remainingPercent, 0), 100)
        let reset = window.resetAt.map { "Resets \(hubDate($0))" } ?? "Reset unavailable"
        return "<div class=\"metric-row\"><div class=\"window-label\"><strong>\(html(window.label))</strong><small>\(html(reset))</small></div><div class=\"meter-wrap\"><div class=\"meter\"><span style=\"width:\(remaining)%\"></span></div><small>\(window.usedPercent)% used</small></div><strong class=\"num\">\(remaining)% left</strong></div>"
    }

    private static func quotaChart(_ history: [LLMQuotaHistorySample], fallback snapshot: LLMUsageSnapshot) -> String {
        var samples = Array(history.suffix(200))
        if samples.isEmpty, let limit = snapshot.limits.first(where: { $0.name == "Codex" }) ?? snapshot.limits.first {
            samples = [LLMQuotaHistorySample(sampledAt: snapshot.lastUpdated ?? Date(), primaryRemainingPercent: limit.shortWindow?.remainingPercent, weeklyRemainingPercent: limit.weeklyWindow?.remainingPercent, planType: snapshot.planType)]
        }
        guard let first = samples.first, let last = samples.last else { return "<p class=\"sub\">No quota history captured yet.</p>" }
        let span = max(last.sampledAt.timeIntervalSince(first.sampledAt), 1)
        func points(_ keyPath: KeyPath<LLMQuotaHistorySample, Int?>) -> String {
            samples.compactMap { sample -> String? in
                guard let value = sample[keyPath: keyPath] else { return nil }
                let x = 20 + 860 * sample.sampledAt.timeIntervalSince(first.sampledAt) / span
                let y = 10 + 100 * (1 - Double(min(max(value, 0), 100)) / 100)
                return "\(String(format: "%.1f", x)),\(String(format: "%.1f", y))"
            }.joined(separator: " ")
        }
        let primary = points(\.primaryRemainingPercent)
        let weekly = points(\.weeklyRemainingPercent)
        return "<svg class=\"quota-chart\" viewBox=\"0 0 900 130\" role=\"img\" aria-label=\"Codex remaining quota history\"><path class=\"chart-grid\" d=\"M20 10H880 M20 60H880 M20 110H880\"></path><polyline class=\"quota-primary\" points=\"\(primary)\"></polyline><polyline class=\"quota-weekly\" points=\"\(weekly)\"></polyline></svg><div class=\"legend\"><span><i class=\"dot\" style=\"background:var(--accent)\"></i>5h remaining</span><span><i class=\"dot\" style=\"background:#8bb4ff\"></i>Weekly remaining</span><span>\(html(hubDate(first.sampledAt))) → \(html(hubDate(last.sampledAt)))</span></div>"
    }

    private static func sessionTimeline(_ snapshot: LLMUsageSnapshot) -> String {
        let sessions = allSessions(snapshot)
        let end = Date()
        let start = end.addingTimeInterval(-86_400)
        let rows = sessions.compactMap { session -> (LLMUsageSession, Date, Date)? in
            let sessionEnd = session.updatedAt ?? session.createdAt ?? end
            let sessionStart = session.createdAt ?? sessionEnd.addingTimeInterval(-900)
            guard sessionStart <= end && sessionEnd >= start else { return nil }
            return (session, max(sessionStart, start), min(sessionEnd, end))
        }.sorted { $0.2 > $1.2 }.prefix(20)
        guard !rows.isEmpty else { return "<p class=\"sub\">No local sessions in the last 24 hours.</p>" }
        return "<div class=\"timeline\">" + rows.map { session, clippedStart, clippedEnd in
            let left = max(0, clippedStart.timeIntervalSince(start) / 86_400 * 100)
            let width = max(0.35, clippedEnd.timeIntervalSince(clippedStart) / 86_400 * 100)
            let tokens = session.tokenUsage?.totalTokens ?? session.tokens
            return """
            <details class="timeline-session">
              <summary class="timeline-row"><div class="timeline-label"><strong>\(html(short(cleanSessionTitle(session.title))))</strong><small>\(html(session.provider)) · \(html(session.projectName)) · \(compactTokenCount(tokens)) · click for detail</small></div><div class="timeline-track"><span class="timeline-bar" style="left:\(String(format: "%.2f", left))%;width:\(String(format: "%.2f", width))%"></span></div><span class="num">\(html(hubDate(clippedEnd)))</span></summary>
              \(sessionDetailBody(session))
            </details>
            """
        }.joined() + "</div>"
    }

    private static func sessionAccordions(_ snapshot: LLMUsageSnapshot) -> String {
        let sessions = allSessions(snapshot)
        guard !sessions.isEmpty else { return "<p class=\"sub\">No local Codex or Claude sessions found.</p>" }
        return "<div class=\"session-list\">" + sessions.map { session in
            let tokens = session.tokenUsage?.totalTokens ?? session.tokens
            return """
            <details class="session">
              <summary><div><strong>\(html(cleanSessionTitle(session.title)))</strong><small>\(html(session.provider)) · \(html(session.projectName)) · \(html(session.modelName)) · \(html(session.updatedAt.map(hubDate) ?? "time unavailable"))</small></div><strong class="num">\(compactTokenCount(tokens))</strong></summary>
              \(sessionDetailBody(session))
            </details>
            """
        }.joined() + "</div>"
    }

    private static func sessionDetailBody(_ session: LLMUsageSession) -> String {
        let usage = session.tokenUsage
        let tokens = usage?.totalTokens ?? session.tokens
        let preview = sanitizedSessionPreview(session.preview)
        let contextLink = session.rolloutPath.isEmpty ? "" : "<div><dt>Context</dt><dd><a href=\"\(html(URL(fileURLWithPath: session.rolloutPath).absoluteString))\">Open local file</a></dd></div>"
        return """
        <div class="session-body"><dl class="detail-grid">
          <div><dt>Provider</dt><dd>\(html(session.provider))</dd></div><div><dt>Project</dt><dd>\(html(session.projectName))</dd></div><div><dt>Model</dt><dd>\(html(session.modelName))</dd></div><div><dt>Session ID</dt><dd>\(html(session.id))</dd></div>
          <div><dt>Total tokens</dt><dd>\(compactTokenCount(tokens))</dd></div><div><dt>Input</dt><dd>\(compactTokenCount(usage?.inputTokens ?? 0))</dd></div><div><dt>Cached input</dt><dd>\(compactTokenCount(usage?.cachedInputTokens ?? 0))</dd></div>
          <div><dt>Fresh input</dt><dd>\(compactTokenCount(usage?.nonCachedInputTokens ?? 0))</dd></div><div><dt>Output</dt><dd>\(compactTokenCount(usage?.outputTokens ?? 0))</dd></div><div><dt>Reasoning</dt><dd>\(compactTokenCount(usage?.reasoningOutputTokens ?? 0))</dd></div>
          <div><dt>Cache hit</dt><dd>\(usage.map { "\($0.cacheHitPercent)%" } ?? "—")</dd></div><div><dt>Turns</dt><dd>\(usage.map { "\($0.turnCount)" } ?? "—")</dd></div><div><dt>API estimate</dt><dd>\(usage.map { hubDollars($0.estimatedCost(for: session.modelName)) } ?? "—")</dd></div>
          <div><dt>Estimated rate</dt><dd>\(html(usage?.pricingLabel(for: session.modelName) ?? "—"))</dd></div><div><dt>Started</dt><dd>\(html(session.createdAt.map(hubDate) ?? "—"))</dd></div><div><dt>Updated</dt><dd>\(html(session.updatedAt.map(hubDate) ?? "—"))</dd></div>\(contextLink)
        </dl>\(preview.map { "<p class=\"preview\">\(html($0))</p>" } ?? "")</div>
        """
    }

    private static func advancedSummary(_ snapshot: LLMUsageSnapshot) -> String {
        "<div class=\"grid\">\(card("Plan", html(snapshot.planType ?? "Unknown"), html(snapshot.email ?? "account unavailable")))\(card("Limit groups", "\(snapshot.limits.count)", "live API"))\(card("Local windows", "\(snapshot.localWindows.count)", "token summaries"))\(card("Recent sessions", "\(snapshot.recentSessions.count)", "\(snapshot.topWeeklySessions.count) highest"))\(card("Reset credits", snapshot.resetCreditCount.map(String.init) ?? "—", html(snapshot.creditsBalance ?? "balance unavailable")))</div>"
    }

    private static func localWindowTable(_ windows: [LLMLocalUsageWindow]) -> String {
        guard !windows.isEmpty else { return "<p class=\"sub\">No local usage windows available.</p>" }
        return "<table class=\"data-table\"><thead><tr><th>Window</th><th class=\"num\">Tokens</th><th class=\"num\">Threads</th></tr></thead><tbody>" + windows.map { "<tr><td>\(html($0.label))</td><td class=\"num\">\(compactTokenCount($0.tokens))</td><td class=\"num\">\($0.threads)</td></tr>" }.joined() + "</tbody></table>"
    }

    private static func costEstimateTable(_ estimates: [LLMTokenCostEstimate]) -> String {
        guard !estimates.isEmpty else { return "<p class=\"sub\">No local token cost estimates available.</p>" }
        return "<table class=\"data-table\"><thead><tr><th>Window</th><th class=\"num\">Sessions</th><th class=\"num\">Fresh input</th><th class=\"num\">Cached input</th><th class=\"num\">Output</th><th class=\"num\">Cache</th><th class=\"num\">API est.</th></tr></thead><tbody>" + estimates.map { "<tr><td>\(html($0.label))</td><td class=\"num\">\($0.sessionCount)</td><td class=\"num\">\(compactTokenCount($0.freshInputTokens))</td><td class=\"num\">\(compactTokenCount($0.cachedInputTokens))</td><td class=\"num\">\(compactTokenCount($0.outputTokens))</td><td class=\"num\">\($0.cacheHitPercent)%</td><td class=\"num\">\(hubDollars($0.estimatedCost))</td></tr>" }.joined() + "</tbody></table>"
    }

    private static func availableDetail(_ snapshot: LLMUsageSnapshot) -> String {
        let windows = snapshot.localWindows.map(\.label).joined(separator: ", ")
        let rows = [
            ("Live limits", "\(snapshot.limits.count) limit groups"),
            ("Local windows", windows.isEmpty ? "None" : windows),
            ("Session totals", "Title, model, project, tokens, cache, cost, timing, and IDs"),
            ("Prompt detail", "Stored preview only"),
            ("Per-prompt tokens", "Not stored locally"),
            ("Last update", snapshot.lastUpdated.map(hubDate) ?? "Unavailable"),
            ("Error", snapshot.error ?? "None")
        ]
        return "<div class=\"list\">" + rows.map { "<div><strong>\(html($0.0))</strong><span>\(html($0.1))</span></div>" }.joined() + "</div>"
    }

    private static func allSessions(_ snapshot: LLMUsageSnapshot) -> [LLMUsageSession] {
        var seen = Set<String>()
        return (snapshot.recentSessions + snapshot.topWeeklySessions)
            .filter { seen.insert("\($0.provider):\($0.id)").inserted }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
    }

    private static func cleanSessionTitle(_ title: String) -> String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.localizedCaseInsensitiveContains("Codex agent history") || cleaned.localizedCaseInsensitiveContains("approval request") { return "Approval review" }
        return cleaned.isEmpty ? "Untitled session" : cleaned
    }

    private static func sanitizedSessionPreview(_ preview: String) -> String? {
        let cleaned = preview.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "No prompt preview stored" else { return nil }
        let lower = cleaned.lowercased()
        if lower.contains("codex agent history") || lower.contains("approval request") || lower.contains("transcript start") || lower.contains("planned action json") { return nil }
        return cleaned.count <= 500 ? cleaned : String(cleaned.prefix(497)) + "..."
    }

    private static func hubDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func hubDollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func pathVisual(_ paths: [AIWorkflowPath]) -> String {
        guard !paths.isEmpty else { return panel("AI Paths", "<p class=\"sub\">No ChatGPT/Codex/Claude paths found yet.</p>") }

        let total = max(paths.reduce(0) { $0 + $1.count }, 1)
        var beforeCounts: [String: Int] = [:]
        var surfaceCounts: [String: Int] = [:]
        var afterCounts: [String: Int] = [:]
        var leftLinks: [String: (source: String, target: String, count: Int)] = [:]
        var rightLinks: [String: (source: String, target: String, count: Int)] = [:]

        for path in paths {
            beforeCounts[path.before, default: 0] += path.count
            surfaceCounts[path.surface, default: 0] += path.count
            afterCounts[path.after, default: 0] += path.count

            let leftKey = "\(path.before)|\(path.surface)"
            let rightKey = "\(path.surface)|\(path.after)"
            var left = leftLinks[leftKey] ?? (path.before, path.surface, 0)
            left.count += path.count
            leftLinks[leftKey] = left
            var right = rightLinks[rightKey] ?? (path.surface, path.after, 0)
            right.count += path.count
            rightLinks[rightKey] = right
        }

        struct NodePosition {
            let x: Double
            let y: Double
            let height: Double
        }

        struct Stage {
            let title: String
            let counts: [String: Int]
            let x: Double
        }

        func topLabels(_ counts: [String: Int]) -> [String] {
            Array(counts.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }.prefix(6).map(\.key))
        }

        func percent(_ count: Int) -> String {
            "\(Int((Double(count) / Double(total) * 100).rounded()))%"
        }

        func faviconDomain(for label: String) -> String? {
            let lower = label.lowercased()
            if lower.contains(".") && !lower.contains(" ") {
                return lower
            }
            if lower.contains("gmail") {
                return "mail.google.com"
            }
            if lower.contains("chatgpt") || lower.contains("openai") {
                return "chatgpt.com"
            }
            if lower.contains("github") {
                return "github.com"
            }
            if lower.contains("etrade") {
                return "etrade.com"
            }
            return nil
        }

        func icon(for label: String) -> (initials: String, color: String, href: String?) {
            let lower = label.lowercased()
            let color: String
            if lower.contains("gmail") { color = "#ea4335" }
            else if lower.contains("github") { color = "#f5f7fb" }
            else if lower.contains("safari") { color = "#38bdf8" }
            else if lower.contains("codex") || lower.contains("chatgpt") { color = "#34d399" }
            else if lower.contains("maxx") { color = "#38bdf8" }
            else { color = "#a78bfa" }
            let initials = label
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first }
                .map { String($0).uppercased() }
                .joined()
            let href = faviconDomain(for: label).map { "https://www.google.com/s2/favicons?domain=\($0)&sz=64" }
            return (initials.isEmpty ? "AI" : initials, color, href)
        }

        let stages = [
            Stage(title: "Before", counts: beforeCounts, x: 26),
            Stage(title: "AI surface", counts: surfaceCounts, x: 372),
            Stage(title: "After", counts: afterCounts, x: 718)
        ]

        let nodeWidth = 120.0
        let top = 58.0
        let availableHeight = 252.0
        var positions: [String: NodePosition] = [:]
        var stageMarkup = ""

        for stage in stages {
            let labels = topLabels(stage.counts)
            let rawHeights = labels.map { max(24.0, Double(stage.counts[$0] ?? 0) / Double(total) * 190.0) }
            let gap = 14.0
            let needed = rawHeights.reduce(0, +) + max(0.0, Double(labels.count - 1)) * gap
            let scale = needed > 0 ? min(1.0, availableHeight / needed) : 1.0
            var y = top

            stageMarkup += #"<text class="ai-sankey-stage" x="\#(stage.x)" y="24">\#(html(stage.title))</text>"#
            for (index, label) in labels.enumerated() {
                let count = stage.counts[label] ?? 0
                let height = max(20.0, rawHeights[index] * scale)
                positions["\(stage.title)|\(label)"] = NodePosition(x: stage.x, y: y, height: height)
                let iconData = icon(for: label)
                let iconX = stage.x + nodeWidth + 8
                let iconY = y + 4
                let labelX = iconX + 26
                let iconMarkup: String
                if let href = iconData.href {
                    iconMarkup = """
                    <rect width="18" height="18" rx="5" fill="\(iconData.color)" opacity=".18"></rect>
                    <image href="\(html(href))" x="2" y="2" width="14" height="14" preserveAspectRatio="xMidYMid meet"></image>
                    <text x="9" y="12.5" text-anchor="middle" fill="\(iconData.color)" opacity=".28">\(html(iconData.initials))</text>
                    """
                } else {
                    iconMarkup = """
                    <rect width="18" height="18" rx="5" fill="\(iconData.color)" opacity=".22"></rect>
                    <text x="9" y="12.5" text-anchor="middle" fill="\(iconData.color)">\(html(iconData.initials))</text>
                    """
                }
                stageMarkup += """
                <rect class="ai-sankey-node" x="\(format(stage.x))" y="\(format(y))" width="\(format(nodeWidth))" height="\(format(height))" rx="4"><title>\(html(label)) · \(count)x · \(percent(count))</title></rect>
                <g class="ai-sankey-icon" transform="translate(\(format(iconX)),\(format(iconY)))">\(iconMarkup)</g>
                <text class="ai-sankey-label" x="\(format(labelX))" y="\(format(y + 12))">\(html(short(label)))</text>
                <text class="ai-sankey-count" x="\(format(labelX))" y="\(format(y + 28))">\(count) (\(percent(count)))</text>
                """
                y += height + gap
            }
        }

        func linkMarkup(_ links: [String: (source: String, target: String, count: Int)], fromStage: String, toStage: String) -> String {
            links.values.sorted { lhs, rhs in
                lhs.count == rhs.count ? "\(lhs.source)|\(lhs.target)" < "\(rhs.source)|\(rhs.target)" : lhs.count > rhs.count
            }.prefix(18).compactMap { link in
                guard let start = positions["\(fromStage)|\(link.source)"],
                      let end = positions["\(toStage)|\(link.target)"] else {
                    return nil
                }
                let sx = start.x + nodeWidth
                let sy = start.y + start.height / 2
                let ex = end.x
                let ey = end.y + end.height / 2
                let width = max(3.0, min(30.0, Double(link.count) / Double(total) * 36.0))
                return #"<path class="ai-sankey-link" d="M \#(format(sx)) \#(format(sy)) C \#(format(sx + 82)) \#(format(sy)), \#(format(ex - 82)) \#(format(ey)), \#(format(ex)) \#(format(ey))" stroke-width="\#(format(width))"><title>\#(html(link.source)) → \#(html(link.target)) · \#(link.count)x · \#(percent(link.count))</title></path>"#
            }.joined()
        }

        let links = linkMarkup(leftLinks, fromStage: "Before", toStage: "AI surface")
            + linkMarkup(rightLinks, fromStage: "AI surface", toStage: "After")

        let topRows = paths.prefix(6).map { path -> String in
            return """
            <div><strong>\(html(path.before))</strong><span>→</span><strong>\(html(path.surface))</strong><span>→</span><strong>\(html(path.after))</strong><em>\(percent(path.count)) · \(path.count)x · \(html(path.useCase))</em></div>
            """
        }.joined()

        return """
        <section class="panel">
          <div class="ai-path-head">
            <div>
              <h2>AI Paths</h2>
              <p>Most common before → AI surface → after workflows.</p>
            </div>
            <strong>\(total) paths</strong>
          </div>
          <div class="ai-sankey-wrap">
            <svg class="ai-sankey" viewBox="0 0 940 340" role="img" aria-label="Before AI after path flow">
              \(links)
              \(stageMarkup)
            </svg>
          </div>
          <div class="ai-path-top">\(topRows)</div>
        </section>
        """
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func short(_ value: String) -> String {
        value.count <= 24 ? value : String(value.prefix(21)) + "..."
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    static func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
