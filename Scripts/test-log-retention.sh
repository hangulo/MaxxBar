#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-retention.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/LogRetention.swift" \
    "$ROOT_DIR/Tests/LogRetentionTests/main.swift" \
    -o "$TEST_DIR/retention-tests"
"$TEST_DIR/retention-tests"
