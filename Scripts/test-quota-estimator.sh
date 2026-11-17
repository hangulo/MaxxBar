#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-quota-estimator.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/LLMUsageTypes.swift" \
    "$ROOT_DIR/Sources/MaxxBar/ClaudeQuotaEstimator.swift" \
    "$ROOT_DIR/Sources/MaxxBar/APICostLedger.swift" \
    "$ROOT_DIR/Tests/ClaudeQuotaEstimatorTests/main.swift" \
    -o "$TEST_DIR/quota-estimator-tests"
"$TEST_DIR/quota-estimator-tests"
