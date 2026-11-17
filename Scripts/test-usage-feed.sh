#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-usage-feed.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/LLMUsageTypes.swift" \
    "$ROOT_DIR/Sources/MaxxBar/UsageFeed.swift" \
    "$ROOT_DIR/Tests/UsageFeedTests/main.swift" \
    -o "$TEST_DIR/usage-feed-tests"
"$TEST_DIR/usage-feed-tests"
