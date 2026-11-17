import Foundation

struct UsageReportRequest {
    let at: Date
    let sessionID: String
    let model: String
    let cost: LLMCostBreakdown
    let tokens: UInt64
}

struct UsageReportSession {
    let title: String
    let project: String
}

/// The full page usage report: one self-contained HTML file (inline CSS, JS and data, no network requests)
/// in Application Support/MaxxBar/report/usage-report.html.
enum UsageReport {
    /// Rows before this day were backfilled from transcripts and quota history that MaxxBar did not see live.
    static let verifiedFrom = "2026-10-14"

    static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MaxxBar/report/usage-report.html")
    }

    struct Payload: Encodable {
        struct Plan: Encodable {
            let plan: String
            let monthlyUSD: Double
            let from: Date?
        }

        struct SessionDay: Encodable {
            let id: String
            /// Fresh input, cache write, cache read, output, in dollars.
            let c: [Double]
            let n: Int
            let m: [String: Double]
        }

        struct Day: Encodable {
            let d: String
            let c: [Double]
            let n: Int
            let t: UInt64
            let m: [String: Double]
            let s: [SessionDay]
        }

        struct Window: Encodable {
            let k: String
            let m: String?
            let r: Date
            let at: Date
            let left: Int
            let used: Int
            let low: Bool
            let inferred: Bool
            let age: Int
            let plan: String?
            let backfilled: Bool
            let weeklyUsed: Int?
            /// API value of the requests made inside the window.
            let v: Double
        }

        struct Live: Encodable {
            var at: Date?
            var fiveLeft: Int?
            var fiveReset: Date?
            var weekLeft: Int?
            var weekReset: Date?
            var models: [String: Int] = [:]
            var modelResets: [String: Date] = [:]
            var plan: String?
        }

        let generatedAt: Date
        let pricingAsOf: String
        let verifiedFrom: String
        let plans: [Plan]
        let days: [Day]
        let sessions: [String: [String: String]]
        let windows: [Window]
        /// Hourly quota readings for the last 35 days: time, weekly left, 5h left, per-model weekly left.
        let series: [[String: Double]]
        let live: Live
    }

    static func payload(
        requests: [UsageReportRequest],
        sessions: [String: UsageReportSession],
        ledger: [QuotaWindowRecord],
        history: [LLMQuotaHistorySample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Payload {
        func round(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
        func split(_ cost: LLMCostBreakdown) -> [Double] { [cost.freshInput, cost.cacheWrite, cost.cacheRead, cost.output] }
        func add(_ a: [Double], _ b: [Double]) -> [Double] { zip(a, b).map(+) }

        struct DayAccumulator {
            var c = [0.0, 0, 0, 0]
            var n = 0
            var t: UInt64 = 0
            var m: [String: Double] = [:]
            var s: [String: (c: [Double], n: Int, m: [String: Double])] = [:]
        }
        var days: [String: DayAccumulator] = [:]
        for request in requests {
            let key = APICostLedger.dayKey(request.at, calendar: calendar)
            let cost = split(request.cost)
            var day = days[key, default: DayAccumulator()]
            day.c = add(day.c, cost)
            day.n += 1
            day.t += request.tokens
            day.m[request.model, default: 0] += request.cost.total
            var session = day.s[request.sessionID, default: ([0, 0, 0, 0], 0, [:])]
            session.c = add(session.c, cost)
            session.n += 1
            session.m[request.model, default: 0] += request.cost.total
            day.s[request.sessionID] = session
            days[key] = day
        }
        let dayRows = days.keys.sorted().map { key -> Payload.Day in
            let day = days[key]!
            return Payload.Day(
                d: key, c: day.c.map(round), n: day.n, t: day.t, m: day.m.mapValues(round),
                s: day.s.map { Payload.SessionDay(id: $0.key, c: $0.value.c.map(round), n: $0.value.n, m: $0.value.m.mapValues(round)) }
                    .sorted { $0.c.reduce(0, +) > $1.c.reduce(0, +) }
            )
        }
        let usedSessions = Set(dayRows.flatMap { $0.s.map(\.id) })
        let sessionNames = sessions.filter { usedSessions.contains($0.key) }
            .mapValues { ["t": $0.title, "p": $0.project] }

        let sortedRequests = requests.sorted { $0.at < $1.at }
        func value(from start: Date, to end: Date) -> Double {
            sortedRequests.lazy.filter { $0.at > start && $0.at <= end }.reduce(0) { $0 + $1.cost.total }
        }
        let windows = ledger.sorted { $0.windowResetAt < $1.windowResetAt }.map { record -> Payload.Window in
            let length: TimeInterval = record.kind == .fiveHour ? 5 * 3_600 : QuotaWindowLedger.week
            return Payload.Window(
                k: record.kind.rawValue, m: record.model, r: record.windowResetAt, at: record.lastSampleAt,
                left: record.leftPercent, used: record.lastUsedPercent, low: record.lowConfidence,
                inferred: record.resetInferred, age: record.sampleAgeAtResetSeconds, plan: record.plan,
                backfilled: record.backfilled, weeklyUsed: record.weeklyAllUsedPercentAtClose,
                v: round(value(from: record.windowResetAt.addingTimeInterval(-length), to: record.windowResetAt))
            )
        }

        let claudeSamples = history.filter {
            $0.claudeWeeklyRemainingPercent != nil || $0.claudeFiveHourRemainingPercent != nil
        }.sorted { $0.sampledAt < $1.sampledAt }
        var series: [[String: Double]] = []
        var lastHour: Int?
        for sample in claudeSamples where now.timeIntervalSince(sample.sampledAt) <= 35 * 86_400 {
            let hour = Int(sample.sampledAt.timeIntervalSince1970 / 3_600)
            var row: [String: Double] = ["t": (sample.sampledAt.timeIntervalSince1970 * 1_000).rounded()]
            if let value = sample.claudeWeeklyRemainingPercent { row["w"] = Double(value) }
            if let value = sample.claudeFiveHourRemainingPercent { row["f"] = Double(value) }
            for (model, value) in sample.claudeModelWeeklyRemaining ?? [:] { row["m:" + model] = Double(value) }
            if hour == lastHour, !series.isEmpty { series[series.count - 1] = row } else { series.append(row) }
            lastHour = hour
        }
        var live = Payload.Live()
        if let last = claudeSamples.last {
            live.at = last.sampledAt
            live.fiveLeft = last.claudeFiveHourRemainingPercent
            live.fiveReset = last.claudeFiveHourResetAt
            live.weekLeft = last.claudeWeeklyRemainingPercent
            live.weekReset = last.claudeWeeklyResetAt
            live.models = last.claudeModelWeeklyRemaining ?? [:]
            live.modelResets = last.claudeModelWeeklyResetAt ?? [:]
            live.plan = ClaudePlanTimeline.normalized(last.claudePlanType) ?? ClaudePlanTimeline.entry(at: last.sampledAt).plan
        }

        return Payload(
            generatedAt: now,
            pricingAsOf: LLMTokenPricing.asOf,
            verifiedFrom: verifiedFrom,
            plans: ClaudePlanTimeline.entries.map {
                Payload.Plan(plan: $0.plan, monthlyUSD: $0.monthlyUSD, from: $0.from == .distantPast ? nil : $0.from)
            },
            days: dayRows,
            sessions: sessionNames,
            windows: windows,
            series: series,
            live: live
        )
    }

    static func html(for payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // Keep the data from closing the script element early.
        let safe = json.replacingOccurrences(of: "</", with: "<\\/")
        return template.replacingOccurrences(of: "__REPORT_DATA__", with: safe)
    }

    /// Reads every transcript (slow the first time), writes the report and returns its URL.
    static func write(ledger: [QuotaWindowRecord], history: [LLMQuotaHistorySample], to target: URL = url) -> URL? {
        let scan = LLMUsageReader.usageReportRequests()
        let page = html(for: payload(requests: scan.requests, sessions: scan.sessions, ledger: ledger, history: history))
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try page.write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            return nil
        }
    }

    /// A page that reloads itself until the real report replaces it.
    static func writePlaceholder(to target: URL = url) -> URL? {
        let page = """
        <!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="2">
        <title>Claude usage report</title>
        <style>:root{color-scheme:light dark}body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;display:grid;
        place-items:center;height:90vh;margin:0;background:#f6f7f9;color:#5d6573}
        @media (prefers-color-scheme: dark){body{background:#0e1013;color:#9aa2b1}}</style></head>
        <body><p>Building the report from your local transcripts. This page reloads when it is ready.</p></body></html>
        """
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try page.write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            return nil
        }
    }

    // swiftlint:disable line_length
    private static let template = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claude usage report</title>
<style>
:root{color-scheme:light dark;--bg:#f5f6f8;--card:#ffffff;--ink:#12151a;--sub:#5f6775;--faint:#8b93a1;--line:#e2e5ea;--grid:#eef0f3;--coral:#d9774f;--coral2:#efb9a2;--unused:#6f7a8c;--unusedBg:#e4e8ee;--cr:#9aa5b8;--cw:#4b78f0;--o:#d9774f;--fi:#169a7e;--hatch:rgba(18,21,26,.22);--hover:#f0f2f5;--sel:#12151a}
@media (prefers-color-scheme: dark){:root{--bg:#0d0f12;--card:#15181d;--ink:#eceef2;--sub:#a0a8b6;--faint:#6f7787;--line:#252a31;--grid:#1d2127;--coral:#e98a62;--coral2:#7a4632;--unused:#97a1b2;--unusedBg:#262b33;--cr:#69758a;--cw:#6f95ff;--o:#e98a62;--fi:#2fb894;--hatch:rgba(255,255,255,.25);--hover:#1c2026;--sel:#eceef2}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",Arial,sans-serif;font-variant-numeric:tabular-nums;-webkit-font-smoothing:antialiased}
main{max-width:1140px;margin:0 auto;padding:36px 22px 72px}
header{display:flex;flex-wrap:wrap;align-items:flex-end;justify-content:space-between;gap:16px}
h1{font-size:28px;letter-spacing:-.02em;margin:0;font-weight:680}
h2{font-size:17px;margin:0;font-weight:650;letter-spacing:-.01em}
.sub{color:var(--sub)}
.faint{color:var(--faint);font-size:12px}
.seg{display:inline-flex;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:3px}
.seg button{border:0;background:transparent;color:var(--sub);font:inherit;font-weight:560;padding:6px 14px;border-radius:7px;cursor:pointer}
.seg button.on{background:var(--ink);color:var(--card)}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:20px 22px;margin-top:18px}
.head{display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:8px;margin-bottom:14px}
.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin-top:22px}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px 18px}
.kpi .label{color:var(--sub);font-size:12.5px;font-weight:560}
.kpi .value{font-size:30px;font-weight:680;letter-spacing:-.02em;margin-top:4px}
.kpi .note{color:var(--faint);font-size:12px;margin-top:4px}
.kpi.hero .value{color:var(--coral)}
.grid2{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1fr);gap:22px}
.legend{display:flex;flex-wrap:wrap;gap:14px;font-size:12px;color:var(--sub)}
.legend i{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px;vertical-align:-1px}
svg{display:block;width:100%;overflow:visible}
svg text{fill:var(--faint);font-size:11px}
.bar{cursor:pointer}
.bar:hover rect{opacity:.85}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;color:var(--faint);font-weight:560;font-size:12px;padding:6px 8px;border-bottom:1px solid var(--line)}
td{padding:7px 8px;border-bottom:1px solid var(--grid)}
td.num,th.num{text-align:right}
tr.click{cursor:pointer}
tr.click:hover td{background:var(--hover)}
tr.open td{background:var(--hover)}
.pill{display:inline-block;font-size:11px;font-weight:600;padding:1px 7px;border-radius:999px;border:1px solid var(--line);color:var(--sub);margin-left:6px}
.pill.low{border-style:dashed}
.detail{padding:10px 4px 6px;color:var(--sub);font-size:12.5px}
.splitbar{display:flex;height:8px;border-radius:4px;overflow:hidden;background:var(--grid);margin:6px 0 8px;max-width:420px}
.empty{color:var(--faint);padding:18px 0;font-size:13px}
#tip{position:fixed;pointer-events:none;background:var(--ink);color:var(--card);font-size:12px;line-height:1.4;padding:8px 10px;border-radius:8px;max-width:280px;opacity:0;transition:opacity .08s;z-index:10}
.mix{display:grid;grid-template-columns:150px 1fr 90px;gap:8px 12px;align-items:center;font-size:13px}
.mix .track{height:10px;background:var(--grid);border-radius:5px;overflow:hidden}
.mix .fill{height:100%;background:var(--coral);border-radius:5px}
footer{margin-top:26px;color:var(--faint);font-size:12px;line-height:1.6}
.back{font:inherit;font-size:12.5px;border:1px solid var(--line);background:transparent;color:var(--sub);border-radius:7px;padding:3px 10px;cursor:pointer}
@media (max-width:820px){.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.grid2{grid-template-columns:1fr}.mix{grid-template-columns:110px 1fr 70px}}
</style>
</head>
<body>
<main>
<header>
  <div>
    <h1>Claude usage report</h1>
    <div class="sub" id="subtitle"></div>
  </div>
  <div class="seg" id="period">
    <button data-p="today">Today</button><button data-p="7d" class="on">7 days</button><button data-p="month">Month</button><button data-p="all">All</button>
  </div>
</header>

<section class="kpis" id="kpis"></section>

<section class="card">
  <div class="head"><h2>Unused credits</h2><span class="faint" id="unusedNote"></span></div>
  <div class="grid2">
    <div>
      <div class="head"><span class="sub">Weekly allowance at each reset</span>
        <span class="legend"><span><i style="background:var(--coral)"></i>Used</span><span><i style="background:var(--unused)"></i>Expired unused</span><span><i style="background:repeating-linear-gradient(45deg,var(--unused) 0 2px,transparent 2px 5px)"></i>Low confidence</span></span></div>
      <svg id="weeks" height="230"></svg>
      <div class="faint">The weekly allowance is the real expiry. Click a week to see its 5 hour windows.</div>
    </div>
    <div>
      <div class="head"><span class="sub">Per-model weekly limits</span><span class="faint" id="modelNote"></span></div>
      <svg id="modelLine" height="170"></svg>
      <div id="modelSummary" class="faint"></div>
    </div>
  </div>
  <div style="margin-top:22px">
    <div class="head"><span class="sub" id="gridTitle">5 hour windows, left in window at reset</span><span id="gridBack"></span></div>
    <svg id="fiveGrid" height="120"></svg>
    <div class="faint">A 5 hour window left idle only matters if the weekly allowance also expires with credit left.</div>
    <div id="windowTable" style="margin-top:12px"></div>
  </div>
</section>

<section class="card">
  <div class="head"><h2>Daily value at API prices</h2>
    <span class="legend"><span><i style="background:var(--cr)"></i>Cache read</span><span><i style="background:var(--cw)"></i>Cache write</span><span><i style="background:var(--o)"></i>Output</span><span><i style="background:var(--fi)"></i>Fresh input</span></span></div>
  <svg id="daily" height="240"></svg>
  <div id="dayDetail" style="margin-top:12px"></div>
</section>

<section class="card">
  <div class="head"><h2>Model mix</h2><span class="faint" id="mixNote"></span></div>
  <div id="mix"></div>
</section>

<footer id="footer"></footer>
</main>
<div id="tip"></div>
<script>
const D = __REPORT_DATA__;
const $ = id => document.getElementById(id);
const NS = "http://www.w3.org/2000/svg";
const COST = [["Fresh input","--fi"],["Cache write","--cw"],["Cache read","--cr"],["Output","--o"]];
const DRAW_ORDER = [2,1,3,0];
let period = "7d", selectedDay = null, selectedWeek = null, openSession = null;
try { period = localStorage.getItem("usage-report-period") || period; } catch (e) {}

const money = v => v == null ? "n/a" : (Math.abs(v) >= 1000 ? "$" + Math.round(v).toLocaleString() : "$" + v.toFixed(2));
const pct = v => v == null ? "n/a" : Math.round(v) + "%";
const dayKey = d => d.getFullYear() + "-" + String(d.getMonth()+1).padStart(2,"0") + "-" + String(d.getDate()).padStart(2,"0");
const parseDay = k => { const [y,m,d] = k.split("-").map(Number); return new Date(y, m-1, d); };
const fmtDay = k => parseDay(k).toLocaleDateString(undefined, {month:"short", day:"numeric"});
const fmtTime = t => new Date(t).toLocaleString(undefined, {weekday:"short", month:"short", day:"numeric", hour:"numeric", minute:"2-digit"});
const ago = s => s < 3600 ? Math.round(s/60) + " min" : s < 172800 ? (s/3600).toFixed(1) + " h" : (s/86400).toFixed(1) + " days";
const sum = a => a.reduce((x,y) => x+y, 0);
const css = v => getComputedStyle(document.documentElement).getPropertyValue(v).trim();
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]));
function modelName(m) {
  const s = String(m).replace(/^claude-/, "").replace(/-\d{8}$/, "").replace(/\[.*\]$/, "");
  const parts = s.split("-"); const name = parts.shift() || s;
  return name.charAt(0).toUpperCase() + name.slice(1) + (parts.length ? " " + parts.join(".") : "");
}
function el(tag, attrs, parent) {
  const n = document.createElementNS(NS, tag);
  for (const k in attrs) n.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(n);
  return n;
}
function clear(svg) { while (svg.firstChild) svg.removeChild(svg.firstChild); return svg.clientWidth || 600; }
function hatchDefs(svg) {
  const defs = el("defs", {}, svg);
  const p = el("pattern", {id: svg.id + "-hatch", width: 6, height: 6, patternUnits: "userSpaceOnUse", patternTransform: "rotate(45)"}, defs);
  el("rect", {width: 6, height: 6, fill: "transparent"}, p);
  el("line", {x1: 0, y1: 0, x2: 0, y2: 6, stroke: css("--hatch"), "stroke-width": 2.5}, p);
  return "url(#" + svg.id + "-hatch)";
}
const tip = $("tip");
function showTip(e, html) { tip.innerHTML = html; tip.style.opacity = 1; moveTip(e); }
function moveTip(e) { const x = Math.min(e.clientX + 14, innerWidth - tip.offsetWidth - 8); tip.style.left = x + "px"; tip.style.top = (e.clientY + 14) + "px"; }
function hideTip() { tip.style.opacity = 0; }
function hover(node, html) {
  node.addEventListener("mouseenter", e => showTip(e, html()));
  node.addEventListener("mousemove", moveTip);
  node.addEventListener("mouseleave", hideTip);
}

const byDay = Object.fromEntries(D.days.map(d => [d.d, d]));
const today = new Date(D.generatedAt);
const todayKey = dayKey(today);
const firstKey = D.days.length ? D.days[0].d : todayKey;
const dayValue = d => d ? sum(d.c) : 0;
function planOn(key) {
  const noon = parseDay(key); noon.setHours(12);
  let plan = D.plans[0];
  for (const p of D.plans) if (!p.from || new Date(p.from) <= noon) plan = p;
  return plan;
}
const planPerDay = key => planOn(key).monthlyUSD * 12 / 365;
function range(p) {
  const end = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  let start = new Date(end);
  if (p === "7d") start.setDate(start.getDate() - 6);
  if (p === "month") start = new Date(end.getFullYear(), end.getMonth(), 1);
  if (p === "all") start = parseDay(firstKey < todayKey ? firstKey : todayKey);
  const keys = [];
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) keys.push(dayKey(d));
  return keys;
}
const weeks = D.windows.filter(w => w.k === "weekly");
const fives = D.windows.filter(w => w.k === "fiveHour");
const modelWeeks = D.windows.filter(w => w.k === "weeklyModel");
// A reading more than half a day before the reset says little about what was left.
const unknown = w => w.age > 43200;
const unusedValue = w => (!unknown(w) && w.used >= 10 && w.v > 0) ? w.v * w.left / w.used : null;

function renderKpis() {
  const keys = range(period), first = keys[0], last = keys[keys.length - 1];
  const value = sum(keys.map(k => dayValue(byDay[k])));
  const plan = sum(keys.map(planPerDay));
  const inRange = w => { const k = dayKey(new Date(w.r)); return k >= first && k <= last; };
  const closed = weeks.filter(inRange).filter(w => !unknown(w));
  const est = closed.map(unusedValue).filter(v => v != null);
  const five = fives.filter(inRange);
  const label = {today: "today", "7d": "the last 7 days", month: "this month", all: "all recorded days"}[period];
  const unusedHtml = closed.length
    ? `<div class="value">${pct(sum(closed.map(w => w.left)) / closed.length)}</div><div class="note">weekly allowance left at ${closed.length} reset${closed.length > 1 ? "s" : ""}${est.length ? ", about " + money(sum(est)) + " at API prices" : ""}</div>`
    : `<div class="value">${D.live.weekLeft != null ? pct(D.live.weekLeft) : "n/a"}</div><div class="note">no weekly reset in ${label}; left this week so far${D.live.weekReset ? ", resets " + fmtTime(D.live.weekReset) : ""}</div>`;
  $("kpis").innerHTML = `
    <div class="kpi"><div class="label">Value at API prices</div><div class="value">${money(value)}</div><div class="note">${sum(keys.map(k => byDay[k]?.n || 0)).toLocaleString()} requests in ${label}</div></div>
    <div class="kpi"><div class="label">Plan cost</div><div class="value">${money(plan)}</div><div class="note">prorated per day: ${[...new Set(keys.map(k => planOn(k).plan))].join(", ")}</div></div>
    <div class="kpi hero"><div class="label">Saved</div><div class="value">${money(value - plan)}</div><div class="note">${plan > 0 ? (value / plan).toFixed(1) + "x the plan cost" : ""}</div></div>
    <div class="kpi"><div class="label">Credits left unused</div>${unusedHtml}${five.length ? `<div class="note">5h: ${pct(sum(five.map(w => w.left)) / five.length)} average left in window over ${five.length} windows</div>` : ""}</div>`;
}

function renderWeeks() {
  const svg = $("weeks"), W = clear(svg), H = 230, top = 16, bottom = 34, left = 30;
  const hatch = hatchDefs(svg);
  const items = weeks.map(w => ({w, live: false}));
  if (D.live.weekLeft != null && D.live.weekReset) items.push({w: {r: D.live.weekReset, left: D.live.weekLeft, used: 100 - D.live.weekLeft, low: false, age: 0, v: null}, live: true});
  if (!items.length) { el("text", {x: 0, y: 30}, svg).textContent = "No weekly windows recorded yet."; return; }
  const plotH = H - top - bottom, slot = (W - left) / items.length, bw = Math.min(46, slot * .62);
  [0, 50, 100].forEach(v => {
    const y = top + plotH * (1 - v/100);
    el("line", {x1: left, x2: W, y1: y, y2: y, stroke: css("--grid")}, svg);
    el("text", {x: left - 6, y: y + 4, "text-anchor": "end"}, svg).textContent = v + "%";
  });
  items.forEach(({w, live}, i) => {
    const x = left + slot * i + (slot - bw) / 2;
    const g = el("g", {class: "bar"}, svg);
    const usedH = plotH * w.used / 100, leftH = plotH - usedH;
    const unk = !live && unknown(w);
    const sel = selectedWeek && selectedWeek.r === w.r;
    if (live) {
      el("rect", {x, y: top, width: bw, height: leftH, rx: 4, fill: "none", stroke: css("--unused"), "stroke-dasharray": "3 3"}, g);
    } else {
      el("rect", {x, y: top, width: bw, height: leftH, rx: 4, fill: unk ? css("--unusedBg") : css("--unused"), opacity: unk ? 1 : .55}, g);
      if (w.low || unk) el("rect", {x, y: top, width: bw, height: leftH, rx: 4, fill: hatch}, g);
    }
    el("rect", {x, y: top + leftH, width: bw, height: Math.max(usedH, 0), rx: 4, fill: css("--coral")}, g);
    if (sel) el("rect", {x: x - 3, y: top - 3, width: bw + 6, height: plotH + 6, rx: 6, fill: "none", stroke: css("--sel"), "stroke-width": 1.5}, g);
    const t = el("text", {x: x + bw/2, y: top + leftH - 5, "text-anchor": "middle", style: "font-weight:600;fill:" + css("--sub")}, g);
    t.textContent = unk ? "?" : w.left + "%";
    const d = new Date(w.r);
    el("text", {x: x + bw/2, y: H - 16, "text-anchor": "middle"}, g).textContent = d.toLocaleDateString(undefined, {month: "short", day: "numeric"});
    el("text", {x: x + bw/2, y: H - 3, "text-anchor": "middle"}, g).textContent = live ? "so far" : (dayKey(d) < D.verifiedFrom ? "backfilled" : "");
    hover(g, () => live
      ? `<b>This week so far</b><br>${w.left}% left, resets ${fmtTime(w.r)}`
      : `<b>Week ending ${fmtTime(w.r)}</b><br>${unk ? "Unknown: last reading " + ago(w.age) + " before the reset" : w.left + "% expired unused, " + w.used + "% used"}<br>Value used: ${money(w.v)}${unusedValue(w) != null ? "<br>Unused, at the same rate: about " + money(unusedValue(w)) : ""}<br>Plan: ${esc(w.plan || "")}${w.low ? "<br>Low confidence: last reading " + ago(w.age) + " before the reset" : ""}${w.inferred ? "<br>Reset time inferred from the weekly schedule" : ""}${w.backfilled ? "<br>Backfilled from quota history" : ""}`);
    g.addEventListener("click", () => { selectedWeek = live ? {r: w.r, live: true} : w; renderWeeks(); renderGrid(); });
  });
  const known = weeks.filter(w => !unknown(w));
  $("unusedNote").textContent = known.length ? `${known.length} weekly resets recorded, ${pct(sum(known.map(w => w.left)) / known.length)} left on average` : "";
}

function renderModelLine() {
  const svg = $("modelLine"), W = clear(svg), H = 170, top = 10, bottom = 22, left = 30;
  const models = [...new Set([...Object.keys(D.live.models || {}), ...modelWeeks.map(w => w.m)])];
  const pts = D.series.filter(r => r.w != null);
  if (!pts.length) { el("text", {x: 0, y: 30}, svg).textContent = "No quota readings yet."; return; }
  const t0 = Math.max(pts[0].t, Date.now() - 21 * 86400000), t1 = Math.max(pts[pts.length - 1].t, t0 + 1);
  const X = t => left + (W - left) * (t - t0) / (t1 - t0), Y = v => top + (H - top - bottom) * (1 - v / 100);
  [0, 50, 100].forEach(v => { el("line", {x1: left, x2: W, y1: Y(v), y2: Y(v), stroke: css("--grid")}, svg); el("text", {x: left - 6, y: Y(v) + 4, "text-anchor": "end"}, svg).textContent = v + "%"; });
  const line = (key, color, dash) => {
    const p = pts.filter(r => r[key] != null && r.t >= t0);
    if (p.length < 1) return;
    el("path", {d: p.map((r, i) => (i ? "L" : "M") + X(r.t).toFixed(1) + " " + Y(r[key]).toFixed(1)).join(" "), fill: "none", stroke: color, "stroke-width": 1.8, "stroke-dasharray": dash || ""}, svg);
  };
  line("w", css("--unused"), "4 3");
  models.forEach(m => line("m:" + m, css("--coral")));
  for (let d = new Date(t0); d <= t1; d.setDate(d.getDate() + 7)) el("text", {x: X(+d), y: H - 4, "text-anchor": "middle"}, svg).textContent = d.toLocaleDateString(undefined, {month: "short", day: "numeric"});
  modelWeeks.forEach(w => { const c = el("circle", {cx: X(+new Date(w.r)), cy: Y(w.left), r: 4, fill: css("--coral")}, svg); hover(c, () => `<b>${esc(w.m)} weekly reset</b><br>${fmtTime(w.r)}<br>${w.left}% left${w.low ? " (low confidence)" : ""}`); });
  $("modelNote").innerHTML = `<span class="legend"><span><i style="background:var(--coral)"></i>${esc(models.join(", ") || "Per model")} left</span><span><i style="background:var(--unused)"></i>All models left</span></span>`;
  const live = models.map(m => D.live.models[m] != null ? `${esc(m)}: ${D.live.models[m]}% left now${D.live.modelResets[m] ? ", resets " + fmtTime(D.live.modelResets[m]) : ""}` : "").filter(Boolean);
  const closed = modelWeeks.length ? `${modelWeeks.length} ${esc(models[0] || "")} weekly reset${modelWeeks.length > 1 ? "s" : ""} recorded.` : "Per-model weekly resets are recorded from this version on.";
  $("modelSummary").innerHTML = [live.join(" · "), closed].filter(Boolean).join("<br>");
}

function renderGrid() {
  const svg = $("fiveGrid"), W = clear(svg), left = 64, rowH = 24, top = 18;
  const hatch = hatchDefs(svg);
  let list = fives, title = "5 hour windows, left in window at reset";
  if (selectedWeek) {
    const end = +new Date(selectedWeek.r), start = end - 7 * 86400000;
    list = fives.filter(w => +new Date(w.r) > start && +new Date(w.r) <= end + (selectedWeek.live ? 7 * 86400000 : 0));
    title = `5 hour windows in the week ending ${fmtTime(selectedWeek.r)}`;
    $("gridBack").innerHTML = `<button class="back" id="allWeeks">Show all</button>`;
    $("allWeeks").onclick = () => { selectedWeek = null; renderWeeks(); renderGrid(); };
  } else { $("gridBack").innerHTML = ""; }
  $("gridTitle").textContent = title;
  const dayKeys = [...new Set(list.map(w => dayKey(new Date(w.r))))].sort().reverse();
  svg.setAttribute("height", Math.max(70, top + dayKeys.length * rowH + 10));
  if (!dayKeys.length) { el("text", {x: 0, y: 34}, svg).textContent = "No closed 5 hour windows with usage in this range."; renderWindowTable(list); return; }
  const X = h => left + (W - left) * h / 24;
  [0, 6, 12, 18, 24].forEach(h => { el("line", {x1: X(h), x2: X(h), y1: top - 4, y2: top + dayKeys.length * rowH, stroke: css("--grid")}, svg); el("text", {x: X(h), y: 11, "text-anchor": "middle"}, svg).textContent = h === 0 || h === 24 ? "12a" : h === 12 ? "12p" : (h % 12) + (h < 12 ? "a" : "p"); });
  dayKeys.forEach((k, i) => el("text", {x: 0, y: top + i * rowH + 16}, svg).textContent = fmtDay(k));
  list.forEach(w => {
    const r = new Date(w.r), s = new Date(+r - 5 * 3600000);
    const segments = [];
    const rk = dayKey(r), rh = r.getHours() + r.getMinutes() / 60;
    if (dayKey(s) === rk) segments.push([rk, rh - 5, rh]); else { segments.push([rk, 0, rh]); segments.push([dayKey(s), s.getHours() + s.getMinutes() / 60, 24]); }
    segments.forEach(([k, a, b]) => {
      const row = dayKeys.indexOf(k); if (row < 0) return;
      const g = el("g", {class: "bar"}, svg);
      const y = top + row * rowH + 2, x = X(a), width = Math.max(X(b) - X(a) - 2, 2);
      el("rect", {x, y, width, height: rowH - 5, rx: 4, fill: css("--unused"), opacity: (.12 + .78 * w.left / 100).toFixed(2)}, g);
      if (w.low) el("rect", {x, y, width, height: rowH - 5, rx: 4, fill: hatch}, g);
      if (width > 34) { const t = el("text", {x: x + width / 2, y: y + 13, "text-anchor": "middle", style: "font-weight:600;fill:" + (w.left > 55 ? css("--card") : css("--ink"))}, g); t.textContent = w.left + "%"; }
      hover(g, () => `<b>Reset ${fmtTime(w.r)}</b><br>${w.left}% left in window, ${w.used}% used<br>Value in window: ${money(w.v)}<br>Last reading ${ago(w.age)} before the reset${w.low ? " (low confidence)" : ""}${w.weeklyUsed != null ? "<br>Weekly allowance used at the time: " + w.weeklyUsed + "%" : ""}`);
      g.addEventListener("click", () => { selectedWindow = w; renderWindowTable(list); });
    });
  });
  renderWindowTable(list);
}
let selectedWindow = null;
function renderWindowTable(list) {
  const rows = [...list, ...(selectedWeek ? [] : [])].sort((a, b) => new Date(b.r) - new Date(a.r)).slice(0, selectedWeek ? 60 : 12);
  if (!rows.length) { $("windowTable").innerHTML = ""; return; }
  $("windowTable").innerHTML = `<table><thead><tr><th>Window reset</th><th class="num">Left in window</th><th class="num">Used</th><th class="num">Value in window</th><th class="num">Last reading before reset</th><th>Notes</th></tr></thead><tbody>${rows.map(w => `<tr${selectedWindow === w ? ' class="open"' : ""}><td>${fmtTime(w.r)}</td><td class="num">${w.left}%</td><td class="num">${w.used}%</td><td class="num">${money(w.v)}</td><td class="num">${ago(w.age)}</td><td>${w.low ? '<span class="pill low">low confidence</span>' : ""}${w.backfilled ? '<span class="pill">backfilled</span>' : ""}</td></tr>`).join("")}</tbody></table>`;
}

function renderDaily() {
  const keys = range(period === "today" ? "7d" : period);
  const svg = $("daily"), W = clear(svg), H = 240, top = 12, bottom = 26, left = 46;
  const hatch = hatchDefs(svg);
  const max = Math.max(1, ...keys.map(k => dayValue(byDay[k])));
  const nice = Math.pow(10, Math.floor(Math.log10(max))); const cap = Math.ceil(max / nice) * nice;
  const plotH = H - top - bottom, slot = (W - left) / keys.length, bw = Math.max(2, Math.min(28, slot * .7));
  [0, .5, 1].forEach(f => { const y = top + plotH * (1 - f); el("line", {x1: left, x2: W, y1: y, y2: y, stroke: css("--grid")}, svg); el("text", {x: left - 6, y: y + 4, "text-anchor": "end"}, svg).textContent = money(cap * f).replace(".00", ""); });
  const step = Math.ceil(keys.length / Math.max(1, Math.floor((W - left) / 64)));
  keys.forEach((k, i) => {
    const d = byDay[k], x = left + slot * i + (slot - bw) / 2;
    const g = el("g", {class: "bar"}, svg);
    el("rect", {x: left + slot * i, y: top, width: slot, height: plotH, fill: "transparent"}, g);
    let y = top + plotH;
    if (d) DRAW_ORDER.forEach(ci => { const h = plotH * d.c[ci] / cap; y -= h; el("rect", {x, y, width: bw, height: Math.max(h, 0), fill: css(COST[ci][1])}, g); });
    if (d && k < D.verifiedFrom) el("rect", {x, y, width: bw, height: top + plotH - y, fill: hatch}, g);
    if (selectedDay === k) el("rect", {x: x - 2, y: Math.min(y, top + plotH - 4) - 2, width: bw + 4, height: top + plotH - Math.min(y, top + plotH - 4) + 4, fill: "none", stroke: css("--sel"), "stroke-width": 1.5, rx: 3}, g);
    if (i % step === 0) el("text", {x: x + bw / 2, y: H - 8, "text-anchor": "middle"}, g).textContent = fmtDay(k);
    hover(g, () => d ? `<b>${fmtDay(k)}</b>${k < D.verifiedFrom ? " (backfilled, partly unverifiable)" : ""}<br>${money(sum(d.c))} at API prices, plan ${money(planPerDay(k))}<br>${COST.map((c, ci) => c[0] + ": " + money(d.c[ci])).join("<br>")}<br>${d.n.toLocaleString()} requests, ${d.s.length} sessions` : `<b>${fmtDay(k)}</b><br>No Claude Code usage`);
    g.addEventListener("click", () => { selectedDay = selectedDay === k ? null : k; openSession = null; renderDaily(); });
  });
  renderDayDetail();
}
function splitBar(c) {
  const total = sum(c) || 1;
  return `<div class="splitbar">${DRAW_ORDER.map(ci => `<span style="width:${(100 * c[ci] / total).toFixed(2)}%;background:var(${COST[ci][1]})"></span>`).join("")}</div>`;
}
function renderDayDetail() {
  const box = $("dayDetail");
  if (!selectedDay) { box.innerHTML = `<div class="faint">Click a day to list its sessions.</div>`; return; }
  const d = byDay[selectedDay];
  if (!d) { box.innerHTML = `<div class="empty">No Claude Code usage on ${fmtDay(selectedDay)}.</div>`; return; }
  box.innerHTML = `<div class="head"><span><b>${fmtDay(selectedDay)}</b> <span class="sub">${money(sum(d.c))} across ${d.s.length} sessions</span>${selectedDay < D.verifiedFrom ? '<span class="pill">backfilled, partly unverifiable</span>' : ""}</span></div>
  <table><thead><tr><th>Session</th><th>Project</th><th class="num">Requests</th><th class="num">Value</th></tr></thead><tbody>${d.s.map(s => {
    const info = D.sessions[s.id] || {}; const open = openSession === s.id;
    const row = `<tr class="click${open ? " open" : ""}" data-s="${esc(s.id)}"><td>${esc(info.t || "Claude session")}</td><td class="sub">${esc(info.p || "")}</td><td class="num">${s.n}</td><td class="num">${money(sum(s.c))}</td></tr>`;
    if (!open) return row;
    const models = Object.entries(s.m).sort((a, b) => b[1] - a[1]);
    return row + `<tr class="open"><td colspan="4"><div class="detail">${splitBar(s.c)}${COST.map((c, ci) => `<span style="margin-right:14px"><i style="display:inline-block;width:8px;height:8px;border-radius:2px;background:var(${c[1]});margin-right:5px"></i>${c[0]} ${money(s.c[ci])}</span>`).join("")}<div style="margin-top:8px">${models.map(([m, v]) => `${esc(modelName(m))}: ${money(v)}`).join(" · ")}</div></div></td></tr>`;
  }).join("")}</tbody></table>`;
  box.querySelectorAll("tr.click").forEach(tr => tr.onclick = () => { openSession = openSession === tr.dataset.s ? null : tr.dataset.s; renderDayDetail(); });
}

function renderMix() {
  const keys = range(period), totals = {};
  keys.forEach(k => Object.entries(byDay[k]?.m || {}).forEach(([m, v]) => { const n = modelName(m); totals[n] = (totals[n] || 0) + v; }));
  const rows = Object.entries(totals).filter(r => r[1] > 0.005).sort((a, b) => b[1] - a[1]);
  const total = sum(rows.map(r => r[1]));
  $("mixNote").textContent = total ? money(total) + " in the selected period" : "";
  $("mix").innerHTML = rows.length ? `<div class="mix">${rows.map(([m, v]) => `<div>${esc(m)}</div><div class="track"><div class="fill" style="width:${(100 * v / rows[0][1]).toFixed(1)}%"></div></div><div class="num" style="text-align:right">${money(v)} <span class="faint">${Math.round(100 * v / total)}%</span></div>`).join("")}</div>` : `<div class="empty">No usage in this period.</div>`;
}

function renderAll() {
  document.querySelectorAll("#period button").forEach(b => b.classList.toggle("on", b.dataset.p === period));
  renderKpis(); renderWeeks(); renderModelLine(); renderGrid(); renderDaily(); renderMix();
}
document.querySelectorAll("#period button").forEach(b => b.onclick = () => { period = b.dataset.p; try { localStorage.setItem("usage-report-period", period); } catch (e) {} renderAll(); });
$("subtitle").textContent = `Generated ${fmtTime(D.generatedAt)}${D.live.plan ? " · " + D.live.plan + " plan" : ""} · ${D.days.length} days of Claude Code usage since ${fmtDay(firstKey)}`;
$("footer").innerHTML = `Value is each request priced at its model's public API list rate (price table checked ${esc(D.pricingAsOf)}): an estimate of value, not a bill. Plan cost is the monthly price prorated per day: ${D.plans.map(p => esc(p.plan) + " $" + p.monthlyUSD + "/month" + (p.from ? " from " + new Date(p.from).toLocaleDateString(undefined, {month: "short", day: "numeric", year: "numeric"}) : "")).join(", ")}.<br>
Only Claude Code and Claude desktop agent transcripts on this Mac are counted; Claude app chat is not. Days and windows before ${fmtDay(D.verifiedFrom)} are backfilled and partly unverifiable (hatched). Weekly reset times before mid November are inferred from the weekly schedule. "Unused at API prices" scales a week's used value by what was left, so it is a rough estimate.`;
renderAll();
addEventListener("resize", () => { clearTimeout(window.__r); window.__r = setTimeout(renderAll, 120); });
</script>
</body>
</html>
"""#
    // swiftlint:enable line_length
}
