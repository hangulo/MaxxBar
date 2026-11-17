#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-forecast.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/RunwayForecast.swift" \
    "$ROOT_DIR/Tests/RunwayForecastTests/main.swift" \
    -o "$TEST_DIR/forecast-tests"
"$TEST_DIR/forecast-tests"
