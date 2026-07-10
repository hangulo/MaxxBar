# MaxxBar

MaxxBar is a macOS menu bar companion for Codex runway, local AI usage insight, and machine context. It keeps the useful quota, token, memory, and process foundations from Menu Bar Stats, then points the product at a sharper question: how much AI runway is left, what local sessions are driving it, and where AI output is moving in your work.

Current release: `v0.2.0`. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the ongoing release history.

## Screenshots

<p>
  <img src="Artifacts/screenshot-llm.png" alt="Runway panel" width="270">
  <img src="Artifacts/screenshot-insights.png" alt="Insights panel" width="270">
  <img src="Artifacts/screenshot-memory.png" alt="Memory panel" width="270">
</p>

## What It Does

- Shows a two-line menu bar status for 5H runway, weekly reset day, and AI activity captured today.
- Opens a Runway-first popover with live Codex limits, reset credits, local quota history, drawdown insight, cache-token detail, token/session totals, and recent session timelines.
- Provides an Insights tab with AI sessions, output destinations, copy/paste flow metadata, before/after workflow paths, and recent Codex session context.
- Generates a separate MaxxBar Hub with Tracework-aligned navigation for Overview, AI Insights, Runway, Sessions, and Advanced diagnostics.
- Tracks Cmd+C/Cmd+V output flows as metadata only: app/site/title context, never clipboard contents or typed text.
- Captures optional Maxx Moments with sentiment, note, local screenshot, current app/site, detected AI surface, quota, and system state.
- Keeps Memory visible with pressure, memory breakdown, top processes, swap, and grouped/raw process views.
- Includes deeper CPU/GPU, sensor, and network panels for advanced/debug builds.
- Installs a local app bundle and recreates the Desktop shortcut so the launcher points at the latest local build.

## Popover Tabs

- Runway: live Codex limits, resets, local drawdown, and session timeline.
- Insights: AI usage patterns, output destinations, and AI workflow paths.
- Memory: pressure, memory mix, top apps/processes, and swap.
- Moments: quick capture for notable AI workflow moments.

The bottom action bar opens the MaxxBar Hub, starts Deep Trace in Tracework when available, opens the popover as a window, relaunches the app, or quits. Dense chart/help titles use a short hover delay and can be clicked to pin the explanation; bottom action icons and the compact version label show immediate labels.

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

Local files are stored under:

```text
~/Library/Application Support/MaxxBar/llm-quota-history.json
~/Library/Application Support/MaxxBar/ai-activity.jsonl
~/Library/Application Support/MaxxBar/ai-transfers.jsonl
~/Library/Application Support/MaxxBar/maxx-moments.jsonl
~/Library/Application Support/MaxxBar/maxx-moment-screenshots/
~/Library/Application Support/MaxxBar/maxxbar-hub.html
```

The AI logs are local-only metadata. Copy/paste events include app/site/title context and a static `no_clipboard_content` privacy marker, never clipboard contents. Screenshots are stored only when included in a Maxx Moment. MaxxBar does not store OCR output, typed text, or cloud uploads.

## Known Limits

Some low-level hardware data requires privileged or private telemetry that this app does not currently collect directly, including CPU/GPU die temperatures, fan RPM, GPU frequency, SSD thermals, and per-process network attribution. The app marks unavailable values clearly rather than inventing data. A native helper target remains available for privileged sensor collection work.
