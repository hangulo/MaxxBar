# Release Notes

## v0.3.0 - 2026-11-16

Everything merged after the 14 Nov Claude work, in PRs #16, #17 and #18.

Cleanup and energy ([#16](https://github.com/hangulo/MaxxBar/pull/16)):

- Removed Moments, the hidden Clipboard tab and its clipboard poller and image store, the Network panel, and other code nothing on screen reached (about 2,500 lines). `clipboard-metadata.jsonl` is still written on Command-C and Command-V, now without rereading the file.
- Opens at login by default, with a toggle in the eye menu.
- The menu bar shows when a window runs out, in amber, when the current burn rate empties it before its reset.
- The refresh timer runs once a minute while the popover is closed.
- Parsed Claude transcript totals are cached on disk, so launches only read new lines.
- Logs keep 30 days; older lines move to an `archive` folder instead of being deleted.

Usage feed ([#17](https://github.com/hangulo/MaxxBar/pull/17)):

- MaxxBar writes `usage-feed.json` (schema `maxxbar.usage-feed`, version 1): per provider quota, plan, reading source and age, plus token and estimated cost totals per day and per hour for the last 7 days. No email, prompt text, project names or paths. Documented in `Docs/usage-feed.md`.

Unused quota, performance and API value ([#18](https://github.com/hangulo/MaxxBar/pull/18)):

- Records what was left unused when each Claude window resets (5 hour, weekly, and per-model weekly such as Fable) in `llm-window-ledger.jsonl`, backfilled from saved history, with a fresh reading two minutes before each known reset. A Left at reset card on Runway summarizes it.
- New full page usage report (`report/usage-report.html`, no network requests): value at API prices, prorated plan cost, unused weekly allowance, a grid of 5 hour windows, daily value by token type with drill-down to sessions, and model mix.
- The CPU/GPU tab is back, built for local model work: thermal state with a plain explanation, power draw, CPU and GPU temperatures, fan speeds, per-core load, real GPU utilization, and top processes. The heavier reads only run while the tab is open.
- New API Value card on Insights: what usage would have cost at API list prices today, this week, over the last 7 days, and this month, next to the plan price, kept per day in `api-cost-ledger.json`. Requests copied into resumed or forked transcripts are counted once.
- Added Fable 5.1, Opus 5.5, Sonnet 5.5 and Haiku 5.5 API prices, and per-model weekly limits from the usage endpoint.

Repository: stale screenshots of removed tabs were deleted, the README screenshots were regenerated from the current build, and the version is now 0.3.0.

## 2026-11-14 ([#15](https://github.com/hangulo/MaxxBar/pull/15))

Claude as a first-class provider:

- Quota history records Claude 5h, the Claude plan, the source of each Claude reading, and reset times for every window. Older history files still load.
- The Claude plan is read from the rate limit tier in `~/.claude.json` (for example Max 5x), which also fills the plan on the Insights account row.
- The drawdown insight follows your primary provider (Claude when shown, otherwise Codex). A plan change starts a new segment instead of counting as a reset, and a new pace line shows the burn rate since the last reset or plan change and whether the week lasts until its reset.
- The weekly drawdown graph only draws the providers you show.
- A provider hidden with the eye menu is no longer polled or scanned. Toggling refreshes right away.
- Activity records store Claude quota in their own fields instead of the Codex ones.

Energy and data quality:

- Sampling and polling pause while the screen is locked or the Mac or display is asleep, with one refresh on return.
- Lock screen samples are no longer logged and are left out of sessions and workflow paths.
- Launch skips Claude transcripts older than 8 days, and a growing transcript is parsed from where the last pass stopped instead of from the start.
- Activity logs are read backwards to the 7 day cutoff instead of loaded whole.
- The Claude credential is cached until its expiry instead of launching `security` every 30 seconds; `~/.claude.json` is parsed once per change; the usage cache file is only rewritten when it changed; the 5h usage log only appends when the window changed.
- `Scripts/install-app.sh` installs an optimized release build.
- The detached window is titled MaxxBar.

## 2026-11-10

- Cut idle energy use while the popover is closed: transcript parse cache, quota-only refresh while closed, activity sampled every 60 seconds, clipboard poller off (copies come from Cmd+C), Clipboard tab removed from the tab bar.
- Added Claude and Codex visibility toggles (the eye menu in the popover).
- Desktop sessions named "Local session", "Untitled" or "New session" use their summary or sidecar title instead.

## 2026-10-21

- Live Claude limits from the Claude Code OAuth credential, with a Haiku keep-alive that lets Claude Code refresh its own sign-in, 429 backoff, and a saved last-good reading.
- Optional Claude Code status line tap (`Scripts/install-claude-statusline-tap.sh`) so live Claude limits need no extra requests.
- Direct CPU/GPU temperature and fan readings through a read-only AppleSMC connection.
- Clipboard queue and flow insights with short-lived local image previews.

## v0.2.0 - 2026-07-10

- Added a resizable menu-bar popover that remembers its last width and height.
- Added a Clipboard tab with a live current-item marker, historical event queue, content-type metadata, and Claude/Codex flow debugging insights.
- Added temporary local image history with lightweight thumbnails, click-to-open full-size PNGs, 24-hour retention, and 100-image / 250-MB caps.
- Expanded clipboard-write detection beyond Cmd+C to pasteboard changes from menus, Copy buttons, and screenshot-to-clipboard; text and other non-image payloads remain unread and unstored.
- Added detected Codex/Claude account and plan rows with today’s provider-attributed time and session share.
- Strengthened weekly drawdown rendering with a continuous line and interactive point hover for timestamp and remaining percentage.
- Tightened copy/paste flow attribution to recent 15-minute pairs and removed Claude-to-Claude and Codex-to-Codex self-flows from destinations.
- Added seven-day model context and model-usage distribution to Insights in both the menu bar popover and MaxxBar Hub, with Codex/Claude filtering and token-share percentages.
- Added Claude parity across Runway and Sessions: local Claude Code/Desktop/Cowork transcript discovery, per-session model and token/cache totals, combined local windows, provider labels, and live five-hour/weekly Claude limits when Claude Code OAuth is available.
- Added explicit provider status so Claude sessions remain visible when Desktop authentication is present but a Claude Code OAuth credential is not.
- Promoted MaxxBar from a compact runway utility into a fuller AI workflow companion.
- Added the MaxxBar Hub with Overview, AI Insights, Runway, and Sessions destinations.
- Added AI output destination tracking for Cmd+C/Cmd+V flows without reading text clipboard contents.
- Added a shared AI taxonomy for tools, surfaces, sites, and broad use cases.
- Added Start Deep Trace handoff into the Tracework Hub.
- Updated the menu bar to show 5H runway, weekly reset day, and compact AI activity context.
- Moved global Hub, Deep Trace, pop-out, relaunch, and quit controls into the bottom action bar.
- Changed dense popover help to use delayed hover with click-to-pin, while bottom icon/version labels appear immediately.
- Removed the Moments surface from the primary menu bar app so Runway, Insights, and Memory stay primary.
- Refined Memory typography and bar alignment.
- Updated the app bundle default version to `0.2.0`.

## v0.1.0 - 2026-06-30

- Created the first MaxxBar AI usage app from the menu bar stats foundation.
- Added Runway and Insights as the primary popover destinations.
- Added live Codex quota windows, weekly reset weekday, local drawdown history, session detail, and session hover cards.
- Added AI paths reporting, before/after workflow context, and compact AI flow visualizations.
- Added Moments capture for sentiment, notes, optional screenshots, and recent moment history.
- Tightened runway and insights layout, warning contrast, and critical menu bar usage indicators.
- Simplified the Memory panel for faster scanning.

## Pre-0.1 Foundation - 2026-05-28 to 2026-06-26

- Added and expanded Codex LLM usage detail.
- Added LLM usage graphs, session detail, drawdown history, and context-folder actions.
- Persisted local LLM quota history.
- Highlighted low Codex usage states in the menu bar.
