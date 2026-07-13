# MaxxBar Data Audit

Audit time: May 28, 2026, around 20:35 Pacific.

## Summary

The memory totals and memory process list are broadly aligned with Activity Monitor. CPU total user/system percentages also come from a valid macOS source, but per-process CPU can be displayed on two different scales. GPU, CPU die temperature, fan speed, and per-process network data are not available from the public APIs currently used by this app.

## Live Comparison

| Area | App source | Reference checked | Result |
| --- | --- | --- | --- |
| Memory pressure | `memory_pressure -Q` equivalent | Activity Monitor memory pressure | Good match |
| App/wired/compressed/free memory | `host_statistics64` plus physical memory | Activity Monitor memory tab | Good match within sampling/rounding |
| Swap | `sysctl vm.swapusage` | Activity Monitor swap usage | Good match |
| Memory processes | `ps rss` grouped by app bundle | Activity Monitor/top process rows | Good match for Activity Monitor-style footprint rows |
| CPU user/system | `host_statistics(HOST_CPU_LOAD_INFO)` deltas | Activity Monitor CPU total | Valid, but timing/smoothing differs |
| CPU processes | `ps %CPU`, grouped by app bundle | Activity Monitor process display | Valid source, now exposes both raw and normalized scales |
| CPU frequency | `sysctl hw.cpufrequency` | System telemetry | Often unavailable on Apple Silicon |
| CPU/GPU temperature | none/public API unavailable | Native helper | Requires helper/private telemetry |
| GPU usage/memory/FPS | none/public API unavailable | Native helper | Requires helper/private telemetry |
| Network throughput | `getifaddrs` interface counters | Activity Monitor data/sec | Interface total only, not per-process |
| Per-process network | not implemented | Activity Monitor network view | Gap; needs `nettop`, NStat, or another collector |

## CPU Scale Finding

The app's current sample reported:

```text
cpuUser=7%
cpuSystem=8%
cpuProcesses=Codex=2.6%,WindowServer=1.3%,MaxxBar=1.3%,Google Chrome=0.9%,Activity Monitor=0.6%
cpuProcessesRaw=Codex=35.8%,WindowServer=18.3%,MaxxBar=17.7%,Google Chrome=12.0%,Activity Monitor=9.0%
```

Both process lists come from the same `ps %CPU` sample. The `cpuProcesses` values divide raw CPU by the 14 logical CPUs to show a share of the whole machine. The `cpuProcessesRaw` values are closer to Activity Monitor's process scale, where grouped helper processes can add up to large numbers and individual processes can exceed 100% on multicore systems.

## LLM Usage Sources

Codex sessions are read from `~/.codex/state_5.sqlite` and their local rollout files. Claude sessions are read from JSONL transcripts under `~/.claude/projects` and `~/Library/Application Support/Claude/local-agent-mode-sessions`. Claude assistant records are deduplicated by request ID before input, cache creation/read, and output tokens are totaled, because one response can be written as multiple transcript records.

Live Codex limits come from the existing Codex bearer credential and ChatGPT usage endpoint. Live Claude limits come from an existing Claude Code OAuth credential and Anthropic's OAuth usage endpoint. Neither credential is persisted by MaxxBar. Claude Desktop/Cowork can produce local transcripts without exposing a Claude Code OAuth credential, so session capture and live-limit availability are reported independently.

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

## Remaining Accuracy Gaps

1. Extend the privileged/helper telemetry path if CPU die temperature, fan RPM, CPU frequency, and GPU utilization need broader coverage.
2. Add true per-process network attribution before showing a process network list.
3. Keep CPU process scale visible in the UI because whole-machine share and Activity Monitor-style raw percentages answer different questions.
4. Public IP and ping should either be implemented with explicit network calls or left as unavailable.
