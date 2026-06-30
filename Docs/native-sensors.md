# Native Sensor Collection Plan

The app should not depend on iStat Menus being installed. The current iStat history reader is a temporary bridge that helps validate labels and values while developing our own collector.

## Target Data

Top-priority values:

- CPU temperature.
- GPU temperature.
- Fan state and RPM.

Secondary values:

- Airflow temperature.
- Battery temperature.
- CPU efficiency-core temperature.
- CPU performance-core temperature.
- Graphics temperature.
- Palm-rest temperature.
- SSD temperature.
- Wi-Fi temperature.
- CPU/GPU frequency and power.

## Findings So Far

- Battery temperature and system input power are available from public I/O Registry battery telemetry.
- `powermetrics` exposes useful CPU/GPU power, frequency, and thermal information, but it must be invoked as superuser.
- Detailed thermal/fan sensors appear behind private Apple services such as `AppleSMCKeysEndpoint`, `AppleSMCClient`, `AppleARMPMUTempSensor`, and related telemetry services.
- iStat Menus stores recent numeric sensor history locally, but its sensor labels are stored as hashes and resolved inside iStat's own helper/app logic.

## Current Helper Architecture

The repo now includes a standalone `MaxxBarSensorHelper` executable target. It can print a single JSON snapshot, write one snapshot, or run continuously as a LaunchDaemon:

```sh
.build/release/MaxxBarSensorHelper
.build/release/MaxxBarSensorHelper --write /tmp/maxxbar-sensors.json
.build/release/MaxxBarSensorHelper --daemon --output "/Library/Application Support/MaxxBar/sensors.json" --interval 3
```

Install scripts:

- `Scripts/install-sensor-helper.sh` builds the helper, copies it to `/Library/PrivilegedHelperTools/com.hector.MaxxBarSensorHelper`, installs a LaunchDaemon, and starts it.
- `Scripts/uninstall-sensor-helper.sh` unloads and removes the helper.

The menu bar app reads `/Library/Application Support/MaxxBar/sensors.json` first. If the cache is missing or stale, it falls back to the temporary iStat history bridge and public battery telemetry.

## Proposed Architecture

1. Keep the menu bar app unprivileged.
2. Add a small helper process for sensor collection.
3. Install the helper with explicit user approval.
4. Communicate from the app to the helper through a narrow read-only JSON cache, then move to local IPC only if needed.
5. Return structured sensor snapshots:

```swift
struct NativeSensorSnapshot: Codable {
    var cpuTemperatureCelsius: Double?
    var gpuTemperatureCelsius: Double?
    var fans: [Fan]
    var temperatures: [TemperatureSensor]
    var cpuFrequencyGHz: Double?
    var gpuFrequencyGHz: Double?
    var cpuPowerWatts: Double?
    var gpuPowerWatts: Double?
}
```

## Implementation Options To Prototype

- Direct Apple SMC/PMU access through IOKit user clients.
- A privileged collector that samples `powermetrics` and parses plist/text output.
- A hybrid collector: direct IOKit for fans/temps, `powermetrics` for frequency/power.

## Open Collector Work

The helper shell is in place, but the native collector still needs the private Apple Silicon sensor source. The current HID probe did not expose readable temperatures on this machine, and `powermetrics` requires root privileges. Next candidates to prototype are the local `libSMC` symbols in the macOS SDK and the `AppleSMCKeysEndpoint` / `AppleARMPMUTempSensor` IOKit user clients.

## Acceptance Criteria

- App continues to show CPU temp, GPU temp, and fan status after iStat Menus is uninstalled.
- Sensor refresh does not block opening the popover.
- Missing sensors degrade to `-` without crashing.
- Helper has the smallest possible surface area and only returns read-only sensor snapshots.
