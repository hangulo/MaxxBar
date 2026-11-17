#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-api-pricing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/LLMUsageTypes.swift" \
    "$ROOT_DIR/Sources/MaxxBar/ClaudeQuotaEstimator.swift" \
    "$ROOT_DIR/Sources/MaxxBar/APICostLedger.swift" \
    "$ROOT_DIR/Tests/APIPricingTests/main.swift" \
    -o "$TEST_DIR/api-pricing-tests"
"$TEST_DIR/api-pricing-tests"
