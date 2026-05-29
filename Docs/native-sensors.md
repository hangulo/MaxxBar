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

## Proposed Architecture

1. Keep the menu bar app unprivileged.
2. Add a small helper process for sensor collection.
3. Install the helper with explicit user approval.
4. Communicate from the app to the helper over a narrow local IPC API.
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

## Acceptance Criteria

- App continues to show CPU temp, GPU temp, and fan status after iStat Menus is uninstalled.
- Sensor refresh does not block opening the popover.
- Missing sensors degrade to `-` without crashing.
- Helper has the smallest possible surface area and only returns read-only sensor snapshots.
