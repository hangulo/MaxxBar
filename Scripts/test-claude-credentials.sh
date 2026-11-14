#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maxxbar-credentials.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sources/MaxxBar/ClaudeCredentialManager.swift" \
    "$ROOT_DIR/Tests/ClaudeCredentialTests/main.swift" \
    -o "$TEST_DIR/credential-tests"
"$TEST_DIR/credential-tests"
