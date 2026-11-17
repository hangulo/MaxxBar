import Foundation

func rates(_ model: String, prompt: UInt64? = nil) -> LLMTokenPricing { LLMTokenPricing.rates(for: model, promptTokens: prompt) }
func row(_ p: LLMTokenPricing) -> [Double] {
    [p.freshInputDollarsPerMillion, p.cacheWrite5mDollarsPerMillion, p.cacheWrite1hDollarsPerMillion,
     p.cachedInputDollarsPerMillion, p.outputDollarsPerMillion]
}

assert(LLMTokenPricing.asOf == "2026-11-16" && LLMTokenPricing.checkedLabel == "rates checked 2026-11-16")

// Claude rows: input / cache write 5m / cache write 1h / cache read / output.
let claudeRows: [(String, [Double])] = [
    ("claude-fable-5-2", [8, 10, 16, 0.20, 40]), ("claude-mythos-5-2", [8, 10, 16, 0.20, 40]),
    ("claude-fable-5-1", [10, 12.5, 20, 0.25, 50]), ("claude-mythos-5-1", [10, 12.5, 20, 0.25, 50]),
    ("claude-fable-5", [10, 12.5, 20, 1.00, 50]), ("claude-mythos-5", [10, 12.5, 20, 1.00, 50]),
    ("claude-opus-5-5", [4, 5, 8, 0.20, 20]),
    ("claude-opus-5", [5, 6.25, 10, 0.50, 25]), ("claude-opus-4-8", [5, 6.25, 10, 0.50, 25]),
    ("claude-opus-4-7", [5, 6.25, 10, 0.50, 25]), ("claude-opus-4-6", [5, 6.25, 10, 0.50, 25]),
    ("claude-opus-4-5", [5, 6.25, 10, 0.50, 25]),
    ("claude-opus-4-1", [15, 18.75, 30, 1.50, 75]), ("claude-opus-4", [15, 18.75, 30, 1.50, 75]),
    ("claude-sonnet-5-5", [2, 2.5, 4, 0.10, 10]), ("claude-sonnet-5", [2, 2.5, 4, 0.20, 10]),
    ("claude-sonnet-4-6", [3, 3.75, 6, 0.30, 15]), ("claude-sonnet-4-5", [3, 3.75, 6, 0.30, 15]),
    ("claude-sonnet-4", [3, 3.75, 6, 0.30, 15]),
    ("claude-haiku-5-5", [0.10, 0.125, 0.20, 0.01, 0.50]),
    ("claude-haiku-4-5", [1, 1.25, 2, 0.10, 5])
]
for (model, expected) in claudeRows {
    let found = rates(model)
    assert(row(found) == expected && found.isKnown, "\(model): \(row(found))")
    // Suffixes: a context marker, a date, or both.
    assert(row(rates(model + "[1m]")) == expected, "\(model)[1m]")
    assert(row(rates(model + "-20261101")) == expected, "\(model) dated")
    assert(row(rates(model + "-20261101[1m]")) == expected, "\(model) dated [1m]")
}
// Longest prefix: a newer point release never falls back to its parent's row.
assert(rates("claude-fable-5-2").cachedInputDollarsPerMillion == 0.20 && rates("claude-fable-5").cachedInputDollarsPerMillion == 1.00)
assert(rates("claude-opus-5-5[1m]").freshInputDollarsPerMillion == 4 && rates("claude-opus-5[1m]").freshInputDollarsPerMillion == 5)
assert(rates("claude-sonnet-5-5-20261101").cachedInputDollarsPerMillion == 0.10)
assert(rates("claude-haiku-5-5[1m]").outputDollarsPerMillion == 0.50 && rates("claude-haiku-4-5-20251001").outputDollarsPerMillion == 5)
assert(rates("claude-opus-4-20250514").freshInputDollarsPerMillion == 15)
// Display names and provider-prefixed IDs.
assert(rates("Claude Opus 4.8").freshInputDollarsPerMillion == 5 && rates("Fable 5.1").cachedInputDollarsPerMillion == 0.25)
assert(rates("us.anthropic.claude-sonnet-4-5-20250929-v1:0").outputDollarsPerMillion == 15)
// Cache read is stored per model, not derived as a tenth of input.
assert(rates("claude-fable-5").cachedInputDollarsPerMillion == 1.00, "Fable 5 reads at $1, not 0.1x of $10")
assert(rates("claude-sonnet-5").cachedInputDollarsPerMillion == 0.20 && rates("claude-sonnet-5-5").cachedInputDollarsPerMillion == 0.10)
let fable5Cost = rates("claude-fable-5").breakdown(
    inputTokens: 3_000_000, cachedInputTokens: 1_000_000, cacheWriteInputTokens: 1_000_000,
    cacheWrite1hInputTokens: 400_000, outputTokens: 1_000_000
)
assert(abs(fable5Cost.freshInput - 10) < 1e-9 && abs(fable5Cost.cacheRead - 1.00) < 1e-9)
assert(abs(fable5Cost.cacheWrite - (0.6 * 12.5 + 0.4 * 20)) < 1e-9 && abs(fable5Cost.output - 50) < 1e-9)

// Haiku 5.5 prices each request by its whole prompt: up to 100K is the base tier, above it the long tier.
assert(row(rates("claude-haiku-5-5", prompt: 100_000)) == [0.10, 0.125, 0.20, 0.01, 0.50])
assert(row(rates("claude-haiku-5-5", prompt: 100_001)) == [0.50, 0.625, 1.00, 0.05, 2.50])
assert(row(rates("claude-haiku-5-5[1m]", prompt: 400_000)) == [0.50, 0.625, 1.00, 0.05, 2.50])
assert(row(rates("claude-haiku-4-5", prompt: 400_000)) == [1, 1.25, 2, 0.10, 5], "no tier on Haiku 4.5")
assert(row(rates("claude-opus-4-8", prompt: 900_000)) == [5, 6.25, 10, 0.50, 25], "no long context surcharge on Claude 4.6+")
// Buckets price each call at its own tier.
var bucket = LLMUsageBucket(provider: "Claude", hourStart: Date())
bucket.add(LLMTokenCall(timestamp: nil, inputTokens: 50_000, cachedInputTokens: 0, outputTokens: 0), modelName: "claude-haiku-5-5")
bucket.add(LLMTokenCall(timestamp: nil, inputTokens: 200_000, cachedInputTokens: 0, outputTokens: 0), modelName: "claude-haiku-5-5")
assert(abs(bucket.estimatedCostUSD - (0.05 * 0.10 + 0.2 * 0.50)) < 1e-9, "\(bucket.estimatedCostUSD)")

// OpenAI rows: input / cached input / output up to 272K input; over 272K for the 5.6 family and 5.5.
let openAIRows: [(String, [Double])] = [
    ("gpt-5.6-sol", [4.00, 0.40, 20.00]), ("gpt-5.6-terra", [2.00, 0.20, 12.00]), ("gpt-5.6-luna", [0.20, 0.02, 1.20]),
    ("gpt-5.5", [5.00, 0.50, 30.00]), ("gpt-5.4", [2.50, 0.25, 15.00]), ("gpt-5.4-mini", [0.75, 0.075, 4.50]),
    ("gpt-5.4-nano", [0.20, 0.02, 1.25]), ("gpt-5.3-codex", [1.75, 0.175, 14.00]), ("gpt-5.2", [1.75, 0.175, 14.00]),
    ("gpt-5.1", [1.25, 0.125, 10.00]), ("gpt-5", [1.25, 0.125, 10.00]), ("gpt-5-mini", [0.25, 0.025, 2.00]),
    ("gpt-5-nano", [0.05, 0.005, 0.40])
]
func openAIRow(_ p: LLMTokenPricing) -> [Double] { [p.freshInputDollarsPerMillion, p.cachedInputDollarsPerMillion, p.outputDollarsPerMillion] }
for (model, expected) in openAIRows {
    assert(openAIRow(rates(model)) == expected && rates(model).isKnown, "\(model): \(openAIRow(rates(model)))")
    assert(openAIRow(rates(model, prompt: 272_000)) == expected, "\(model) at 272K is still the base tier")
}
assert(openAIRow(rates("gpt-5.6-sol", prompt: 272_001)) == [8, 0.80, 30])
assert(openAIRow(rates("gpt-5.6-terra", prompt: 300_000)) == [4, 0.40, 18])
assert(openAIRow(rates("gpt-5.6-luna", prompt: 1_000_000)) == [0.40, 0.04, 1.80])
assert(openAIRow(rates("gpt-5.5", prompt: 500_000)) == [10, 1.00, 45])
assert(openAIRow(rates("gpt-5.4", prompt: 500_000)) == [2.50, 0.25, 15.00], "others keep one tier")
// gpt-5 must not swallow gpt-5.4 or a future gpt-5.7; a longer variant name keeps its parent row.
assert(openAIRow(rates("gpt-5.4-mini-2026-03-01")) == [0.75, 0.075, 4.50])
assert(rates("gpt-5.7").isKnown == false)
assert(openAIRow(rates("gpt-5.1-codex-max")) == [1.25, 0.125, 10.00])

// Unknown models are labelled as estimates.
let unknown = rates("claude-opus-6")
assert(!unknown.isKnown && unknown.label.contains("no known price"))
assert(!rates("claude-fable-5-3").isKnown, "a newer Fable is unknown, not Fable 5")
assert(!rates("some-local-model").isKnown && rates("some-local-model").label.contains("no known price"))

print("API pricing checks passed")
