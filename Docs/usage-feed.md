# Usage feed for other apps

MaxxBar publishes a small JSON summary of its LLM usage for other local apps (Tracework first):

```
~/Library/Application Support/MaxxBar/usage-feed.json
```

Read this file instead of MaxxBar's internal files. Its fields keep their names and meanings within a `schemaVersion`. MaxxBar's older files (`llm-quota-history.json`, `llm-5h-usage-windows.jsonl` and the rest) keep working unchanged, but they are not a contract.

## When it is written

- After each usage refresh, and after "Check now" on the Claude card.
- Only when the content changed. A new `checkedAt` alone counts as a change once it has moved 5 minutes, so a reader can trust the age to within 5 minutes.
- Atomically (write to a temporary file, then rename), so a reader never sees half a file.
- Never with nothing in it: before the first reading after launch, the previous file stays.

## Versioning

`schema` is always `"maxxbar.usage-feed"`. `schemaVersion` is `1`. New fields can appear in version 1 at any time, so ignore fields you do not know. Renaming or removing a field, or changing what one means, raises `schemaVersion`.

## Fields

| Field | Meaning |
| --- | --- |
| `generatedAt` | When the content last changed (ISO 8601, UTC). |
| `appVersion` | MaxxBar version that wrote the file. |
| `timeZone` | Time zone used for `daily[].date` and hour boundaries, for example `America/Los_Angeles`. |
| `costBasis` | Plain-language note: costs are estimates at public API list prices, not what a subscription bills. |
| `providers[]` | One entry per provider MaxxBar has a quota reading for (`Claude`, `Codex`). Per-model Claude weekly limits are their own entry with only `weekly`, for example `Claude Fable`. A provider hidden with the eye toggle is not read, so it is missing. |
| `providers[].plan` | Plan name, for example `Max 5x` or `prolite`. Can be missing. |
| `providers[].source` | Where the quota reading came from. Claude: `statusline` (Claude Code's own `rate_limits`), `endpoint` (a live usage request) or `cache` (the last saved response). Codex: `endpoint`. |
| `providers[].checkedAt` | When the quota reading was taken. Reading age is now minus this. |
| `providers[].fiveHour`, `providers[].weekly` | `remainingPercent`, `usedPercent` (0 to 100), `resetsAt` (ISO 8601, can be missing) and `windowSeconds` (18000 or 604800). Either can be missing. |
| `providers[].fiveHour.basis`, `providers[].weekly.basis` | `measured` when the numbers are a real reading, `estimated` when they are the last real reading plus the tokens counted locally since (Claude only, between readings). Missing in files written before this field was added, which means measured. |
| `providers[].fiveHour.measuredRemainingPercent`, `.measuredUsedPercent` (and the same on `weekly`) | Only on an estimated window: the real reading the estimate builds on, taken at `checkedAt`. |
| `providers[].error` | The last error for that provider, if any. The numbers may then be from an older reading; check `checkedAt`. |
| `daily[]` | Token and cost totals per local day and provider, for the last 7 days, oldest first. `date` is `yyyy-MM-dd`. Days with no use are left out. |
| `hourly[]` | The same totals per clock hour (`hourStart`, ISO 8601), for the last 7 days, oldest first. Use these to total usage for any time range, such as a work session. |
| `closedWindows[]` | Quota windows that have closed in the last 30 days, oldest first, with what was left unused: `provider`, `kind` (`fiveHour`, `weekly` for all models, or `weeklyModel` for one model's weekly limit such as Fable, named in `model`), `resetAt`, `usedPercent` and `leftPercent` at the close, `lowConfidence` (the last reading was more than 30 minutes before the reset), `backfilled` (reconstructed from older quota history) and `plan`. Empty until MaxxBar's window ledger has rows. A 5h window that was never used has no row. |
| `totals` | `tokens` (prompt plus output), `inputTokens` (whole prompt, including cache reads and writes), `cachedInputTokens` (cache reads), `cacheWriteInputTokens`, `outputTokens`, `requests` and `estimatedCostUSD` (rounded to 4 decimals). |

Token totals come from local transcripts (`~/.claude/projects`) and Codex rollouts, so they cover only this Mac. Quota percentages cover the whole account.

The file holds no email address, prompt text, project name or file path.

## Example

```json
{
  "appVersion" : "1.0",
  "costBasis" : "Estimated at public API list prices. Subscription plans are not billed this way.",
  "daily" : [
    {
      "date" : "2026-11-16",
      "totals" : {
        "cacheWriteInputTokens" : 410233,
        "cachedInputTokens" : 18220431,
        "estimatedCostUSD" : 14.2113,
        "inputTokens" : 18901220,
        "outputTokens" : 120931,
        "provider" : "Claude",
        "requests" : 512,
        "tokens" : 19022151
      }
    }
  ],
  "generatedAt" : "2026-11-17T04:30:12Z",
  "hourly" : [
    {
      "hourStart" : "2026-11-17T03:00:00Z",
      "totals" : { "provider" : "Claude", "requests" : 40, "tokens" : 2100331, "...": "same fields as above" }
    }
  ],
  "providers" : [
    {
      "checkedAt" : "2026-11-17T04:28:55Z",
      "fiveHour" : { "remainingPercent" : 72, "resetsAt" : "2026-11-17T06:00:00Z", "usedPercent" : 28, "windowSeconds" : 18000 },
      "plan" : "Max 5x",
      "provider" : "Claude",
      "source" : "endpoint",
      "weekly" : { "remainingPercent" : 64, "resetsAt" : "2026-11-20T17:00:00Z", "usedPercent" : 36, "windowSeconds" : 604800 }
    }
  ],
  "closedWindows" : [
    { "backfilled" : false, "kind" : "fiveHour", "leftPercent" : 84, "lowConfidence" : false, "plan" : "Max 5x", "provider" : "Claude", "resetAt" : "2026-11-14T21:20:00Z", "usedPercent" : 16 }
  ],
  "schema" : "maxxbar.usage-feed",
  "schemaVersion" : 1,
  "timeZone" : "America/Los_Angeles"
}
```

## Quota over time

The feed holds only the current quota. For how quota moved during a past time range, read `llm-quota-history.json` (an array of samples with `sampledAt`, `claudeFiveHourRemainingPercent`, `claudeWeeklyRemainingPercent`, `claudePlanType` and, for Codex, `primaryRemainingPercent` and `weeklyRemainingPercent`). Those names are kept stable for Tracework.
