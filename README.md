# MenuBarStats

A macOS menu bar stats app inspired by iStat Menus. The current focus is a fast, always-available memory pressure monitor with expandable panels for memory, sensors, CPU/GPU, and network data.

## Current Features

- Menu bar memory pressure percentage.
- Memory popover with pressure, memory breakdown, top processes, paging, swap, and history.
- Grouped and raw process memory views with app icons.
- CPU/GPU panel with user/system history, per-core efficiency/performance load rings, grouped CPU processes, load averages, and uptime.
- Sensors panel with public battery/system input telemetry, temporary iStat history fallback, and a native helper cache path.
- Network panel with interface throughput, IP address, and traffic history.
- Pop-out window mode and quit control.

## Known Limits

Some iStat-style data requires privileged or private telemetry that this app does not currently collect:

- CPU/GPU die temperatures.
- Fan RPM and fan controller state.
- GPU usage, GPU memory, FPS, and GPU frequency.
- SSD, Wi-Fi, palm-rest, airflow, and other detailed thermal sensors.
- Per-process network attribution.

The app marks those values as unavailable rather than inventing data. A first native helper target is included, but the detailed Apple Silicon temperature/fan collector is still being hardened because those sensors sit behind private Apple telemetry interfaces.

## Build

```sh
swift build
```

## Build The App Bundle

```sh
Scripts/build-app.sh
```

The app bundle is written to `Dist/MenuBarStats.app`.

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

## Data Audit

See `Docs/data-audit.md` for notes comparing the app's readings against Activity Monitor and local iStat Menus history.
