# MaxxBar Data Audit

Audit time: May 28, 2026, around 20:35 Pacific.

## Summary

The memory totals and memory process list are broadly aligned with Activity Monitor and iStat Menus. CPU total user/system percentages are also coming from a valid macOS source, but per-process CPU can be displayed on two different scales. GPU, CPU die temperature, fan speed, and per-process network data are not available from the public APIs currently used by this app, so the UI should not present those as iStat-equivalent.

## Live Comparison

| Area | App source | Reference checked | Result |
| --- | --- | --- | --- |
| Memory pressure | `memory_pressure -Q` equivalent | iStat history `memory.pressure` around 23% | Good match |
| App/wired/compressed/free memory | `host_statistics64` plus physical memory | Activity Monitor memory tab and iStat history | Good match within sampling/rounding |
| Swap | `sysctl vm.swapusage` | Activity Monitor and iStat `swap` history | Good match |
| Memory processes | `ps rss` grouped by app bundle | Activity Monitor/top process rows | Good match for Activity Monitor-style footprint rows |
| CPU user/system | `host_statistics(HOST_CPU_LOAD_INFO)` deltas | Activity Monitor CPU total and iStat CPU history | Valid, but timing/smoothing differs |
| CPU processes | `ps %CPU`, grouped by app bundle | Activity Monitor and iStat process display | Valid source, now exposes both raw and normalized scales |
| CPU frequency | `sysctl hw.cpufrequency` | iStat CPU/GPU menu | Often unavailable on Apple Silicon, not iStat-equivalent |
| CPU/GPU temperature | none/public API unavailable | iStat sensors | Requires helper/private telemetry |
| GPU usage/memory/FPS | none/public API unavailable | iStat GPU history | Requires helper/private telemetry |
| Network throughput | `getifaddrs` interface counters | Activity Monitor data/sec | Interface total only, not per-process |
| Per-process network | not implemented | iStat/network process view | Gap; needs `nettop`, NStat, or another collector |

## CPU Scale Finding

The app's current sample reported:

```text
cpuUser=7%
cpuSystem=8%
cpuProcesses=Codex=2.6%,WindowServer=1.3%,MaxxBar=1.3%,Google Chrome=0.9%,Activity Monitor=0.6%
cpuProcessesRaw=Codex=35.8%,WindowServer=18.3%,MaxxBar=17.7%,Google Chrome=12.0%,Activity Monitor=9.0%
```

Both process lists come from the same `ps %CPU` sample. The `cpuProcesses` values divide raw CPU by the 14 logical CPUs on this Mac, which is closer to an iStat-style share of the whole machine. The `cpuProcessesRaw` values are closer to Activity Monitor's process scale, where grouped helper processes can add up to large numbers and individual processes can exceed 100% on multicore systems.

## LLM Quota History

Codex quota samples are persisted locally at:

```text
~/Library/Application Support/MaxxBar/llm-quota-history.json
```

Each sample stores the sampled time, 5H remaining percentage, weekly remaining
percentage, and the plan type reported by the usage API when available. The UI
derives the latest drawdown segment from those samples: the last full point,
threshold crossings at 50%, 20%, and 5%, exhaustion, reset, elapsed time, and
the plan logged for that segment.

The history file is a sampled log, not a continuous event stream. Threshold and
exhaustion times are therefore observed sample times; the true crossing may have
happened between samples.

## iStat Data Available Locally

iStat Menus stores history in:

```text
/Users/hector/Library/Application Support/iStat Menus 7/history/history.db
```

Recent 5-second rows showed CPU user/system, memory pressure, memory categories, and GPU processor/memory history. Sensor and network keys are stored but not directly labelable from the public schema seen here.

## Remaining Accuracy Gaps

1. Add a privileged/helper telemetry path if CPU die temperature, fan RPM, CPU frequency, and GPU utilization need to match iStat.
2. Add true per-process network attribution before showing a process network list.
3. Keep CPU process scale visible in the UI because iStat-style percentages and Activity Monitor-style raw percentages are both defensible but answer different questions.
4. Public IP and ping should either be implemented with explicit network calls or left as unavailable.
