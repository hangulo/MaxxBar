# MenuBarStats

A macOS menu bar system monitor with a compact menu bar readout and popover panels for LLM usage, memory, and CPU/GPU activity.

## Screenshots

### LLM Usage

![LLM usage panel](Artifacts/screenshot-llm.png)

The LLM panel shows live Codex 5H and weekly limits, local token estimates,
and a persisted drawdown timeline. The drawdown summary highlights how long the
most recent run took to reach exhaustion, the threshold-crossing samples, the
reset sample, and the plan type logged for that run.

### Memory

![Memory panel](Artifacts/screenshot-memory.png)

### CPU/GPU

![CPU/GPU panel](Artifacts/screenshot-cpugpu.png)

## Current Features

- Two-line menu bar status for Codex usage and memory pressure.
- LLM usage panel with Codex limits, persistent local quota history, drawdown milestones, cache-token detail, token/session totals, top token users, and context actions for local Codex sessions.
- Memory popover with pressure, memory breakdown, top processes, paging, swap, history, and lighter-weight numeric values for scanability.
- Grouped and raw process memory views with app icons.
- CPU/GPU panel with user/system history, per-core efficiency/performance load rings, grouped CPU processes, thermal summary, detailed temperatures, and uptime.
- Pop-out window mode with resize support and quit control.

## Known Limits

Some low-level hardware data requires privileged or private telemetry that this app does not currently collect directly:

- CPU/GPU die temperatures.
- Fan RPM and fan controller state.
- GPU usage, GPU memory, FPS, and GPU frequency.
- SSD, Wi-Fi, palm-rest, airflow, and other detailed thermal sensors.
- Per-process network attribution.

The app marks unavailable values clearly rather than inventing data. A native helper target is included for privileged sensor collection work.

## Build

```sh
swift build
```

## Build The App Bundle

```sh
Scripts/build-app.sh
```

The app bundle is written to `Dist/MenuBarStats.app`. The renderer used for the
README screenshots can write any panel to a PNG:

```sh
.build/debug/MenuBarStats --render-popover Artifacts/screenshot-llm.png llm
.build/debug/MenuBarStats --render-popover Artifacts/screenshot-memory.png memory
.build/debug/MenuBarStats --render-popover Artifacts/screenshot-cpugpu.png cpugpu
```

## Install On This Mac

```sh
Scripts/install-app.sh
```

The install script builds a fresh local app bundle, copies it to
`~/Applications/MenuBarStats.app`, signs it ad hoc, and recreates the Desktop
shortcut so it points at the local install instead of an iCloud-hosted build
artifact from another laptop.

## Sensor Helper

Build and install the privileged helper:

```sh
Scripts/install-sensor-helper.sh
```

The helper runs as `com.hector.MenuBarStatsSensorHelper` and writes a local snapshot to:

```text
/Library/Application Support/MenuBarStats/sensors.json
```

Remove it with:

```sh
Scripts/uninstall-sensor-helper.sh
```

## Useful Verification Commands

```sh
swift run MenuBarStats -- --sample
swift run MenuBarStats -- --render-popover Artifacts/popover-demo.png
Dist/MenuBarStats.app/Contents/MacOS/MenuBarStats --verify-popover-action
Dist/MenuBarStats.app/Contents/MacOS/MenuBarStats --verify-popout-action
```

## Data Notes

See `Docs/data-audit.md` for implementation notes about source paths, validation, and remaining telemetry gaps.

LLM quota history is stored in:

```text
~/Library/Application Support/MenuBarStats/llm-quota-history.json
```

Each sample records the sampled time, 5H remaining percentage, weekly remaining
percentage, and current plan type when the Codex usage API reports one. The LLM
panel derives the most recent drawdown timeline from these samples, including
the last full point, threshold crossings, exhaustion, reset, elapsed time, and
the plan logged for that run. Exact crossing times are bounded by the sampling
interval.
