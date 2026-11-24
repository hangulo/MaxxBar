#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-fivehour.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/FiveHourLeftPoints.swift" \
    "$ROOT_DIR/Tests/FiveHourLeftPointsTests/main.swift" \
    -o "$TEST_DIR/fivehour-tests"
"$TEST_DIR/fivehour-tests"
