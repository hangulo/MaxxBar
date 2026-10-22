#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-polling.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/ClaudeUsagePollingState.swift" \
    "$ROOT_DIR/Sources/MaxxBar/ClaudeStatusLineLimits.swift" \
    "$ROOT_DIR/Tests/ClaudeUsagePollingTests/main.swift" \
    -o "$TEST_DIR/polling-tests"
"$TEST_DIR/polling-tests"
