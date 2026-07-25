# MaxxBar

MaxxBar is a macOS menu bar companion for Codex and Claude runway, local AI usage insight, and machine context. It brings quota, token, memory, and workflow signals into one quiet daily surface, then points the product at a sharper question: how much AI runway is left, what local sessions are driving it, and where AI output is moving in your work.

Current release: `v0.2.0`. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the ongoing release history.

## Screenshots

<p>
  <img src="Artifacts/screenshot-llm.png" alt="Runway panel" width="270">
  <img src="Artifacts/screenshot-insights.png" alt="Insights panel" width="270">
  <img src="Artifacts/screenshot-memory.png" alt="Memory panel" width="270">
</p>

## What It Does

- Shows a two-line menu bar status for 5H runway, weekly reset day, and AI activity captured today.
- Opens a Runway-first popover with live Codex and Claude limits when authenticated, reset credits, local quota history, drawdown insight, cache-token detail, combined token/session totals, and recent session timelines.
- Provides an Insights tab with detected provider accounts/plans, today’s time and session share, a seven-day model mix and token distribution, output destinations, copy/paste flow metadata, before/after workflow paths, and recent Codex and Claude session context.
- Generates a separate MaxxBar Hub with Tracework-aligned navigation for Overview, AI Insights, Runway, and Sessions.
- Tracks Cmd+C/Cmd+V output flows as metadata only: app/site/title context, never clipboard contents or typed text.
- Keeps Memory visible with pressure, memory breakdown, top processes, swap, and grouped/raw process views.
- Includes deeper CPU/GPU, sensor, and network panels for advanced/debug builds.
- Installs a local app bundle and recreates the Desktop shortcut so the launcher points at the latest local build.

## Popover Tabs

- Runway: live Codex and Claude limits, resets, local drawdown, and a combined session timeline.
- Insights: models used, token-share distribution, AI usage patterns, output destinations, and AI workflow paths.
- Memory: pressure, memory mix, top apps/processes, and swap.

Drag the lower-right grip to resize the popover; MaxxBar stores the last width and height locally and restores them at the next open or launch. The bottom action bar opens the MaxxBar Hub, starts Deep Trace in Tracework when available, opens the popover as a window, relaunches the app, or quits. Dense chart/help titles use a short hover delay and can be clicked to pin the explanation; bottom action icons and the compact version label show immediate labels.

## Build

```sh
swift build
```

## Build The App Bundle

```sh
Scripts/build-app.sh
```

The app bundle is written to `Dist.noindex/MaxxBar.app` by default. Set `APP_VERSION` or `BUILD_VERSION` to override bundle metadata:

```sh
APP_VERSION=0.2.0 BUILD_VERSION=0710.1200 Scripts/build-app.sh
```

## Install On This Mac

```sh
Scripts/install-app.sh
```

The install script builds a fresh local app bundle, copies it to `~/Applications/MaxxBar.app`, signs it ad hoc, and recreates the Desktop shortcut so it points at the local install instead of an iCloud-hosted build artifact from another laptop.

## Useful Verification Commands

```sh
swift run MaxxBar -- --sample
swift run MaxxBar -- --render-popover Artifacts/screenshot-llm.png runway
swift run MaxxBar -- --render-popover Artifacts/screenshot-insights.png insights
swift run MaxxBar -- --render-popover Artifacts/screenshot-memory.png memory
swift run MaxxBar -- --write-ai-report
Dist.noindex/MaxxBar.app/Contents/MacOS/MaxxBar --verify-popover-action
Dist.noindex/MaxxBar.app/Contents/MacOS/MaxxBar --verify-popout-action
```

## Data And Privacy

See `Docs/data-audit.md` for implementation notes about source paths, validation, and remaining telemetry gaps.

### Codex Authentication And Live Usage

To show live Codex quota and reset information, MaxxBar reads the existing Codex access token from `~/.codex/auth.json` and sends it as a bearer token only to `https://chatgpt.com/backend-api/wham/usage`. MaxxBar does not copy the token into its own data files, include it in reports, or send it to any other service.

This ChatGPT usage endpoint is undocumented and is not a stable, officially supported public API. It may change or stop working without notice. MaxxBar is an independent project and is not affiliated with or endorsed by OpenAI. Users should install and run MaxxBar only if they are comfortable allowing a local application to read their existing Codex credential for this request. If the credential or endpoint is unavailable, live quota information is disabled while locally derived session and token information may remain available.

### Claude Sessions And Live Usage

MaxxBar discovers local Claude Code and Claude Desktop/Cowork transcripts under `~/.claude/projects` and Claude's local-agent session directory. It reads session metadata and the token-usage fields Claude already stores locally: provider, title, project, model, timestamps, input, cache creation/read, and output totals. Prompt previews are limited to the locally stored first user message; MaxxBar does not upload transcript content.

The Insights account label comes from Claude’s local `~/.claude.json` profile metadata (email, display name, organization, and seat tier). Codex account email and plan come from the live usage response described above. These labels remain inside MaxxBar’s local UI and reports.

For live five-hour and weekly Claude runway, MaxxBar uses the existing Claude Code OAuth credential from `~/.claude/.credentials.json` or the `Claude Code-credentials` macOS Keychain item and sends it only to `https://api.anthropic.com/api/oauth/usage`. The token is not copied into MaxxBar data or reports. This endpoint is used by Claude Code but is not a stable public API. Claude Desktop/Cowork authentication alone may not expose a Claude Code OAuth credential; in that state MaxxBar still captures local Claude sessions and shows a provider-status note until Claude Code is signed in.

Local files are stored under:

```text
~/Library/Application Support/MaxxBar/llm-quota-history.json
~/Library/Application Support/MaxxBar/ai-activity.jsonl
~/Library/Application Support/MaxxBar/ai-transfers.jsonl
~/Library/Application Support/MaxxBar/maxxbar-hub.html
```

The AI logs are local-only metadata. Copy/paste events include app/site/title context and a static `no_clipboard_content` privacy marker, never clipboard contents. MaxxBar does not store OCR output, typed text, or cloud uploads.

## Known Limits

Some low-level hardware data requires privileged or private telemetry that this app does not currently collect directly, including CPU/GPU die temperatures, fan RPM, GPU frequency, SSD thermals, and per-process network attribution. The app marks unavailable values clearly rather than inventing data. A native helper target remains available for privileged sensor collection work.
