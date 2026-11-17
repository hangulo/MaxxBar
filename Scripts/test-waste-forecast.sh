#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-waste-forecast.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/LLMUsageTypes.swift" \
    "$ROOT_DIR/Sources/MaxxBar/APICostLedger.swift" \
    "$ROOT_DIR/Sources/MaxxBar/QuotaWindowLedger.swift" \
    "$ROOT_DIR/Sources/MaxxBar/QuotaWasteForecast.swift" \
    "$ROOT_DIR/Tests/QuotaWasteForecastTests/main.swift" \
    -o "$TEST_DIR/waste-forecast-tests"
"$TEST_DIR/waste-forecast-tests"
