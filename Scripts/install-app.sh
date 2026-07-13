#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MaxxBar"
STAGING_DIR="${TMPDIR:-/tmp}/$APP_NAME-install"
STAGING_APP="$STAGING_DIR/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_APP="$INSTALL_DIR/$APP_NAME.app"
DESKTOP_LINK="$HOME/Desktop/$APP_NAME.app"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$INSTALL_DIR"

APP_DIR="$STAGING_APP" "$ROOT_DIR/Scripts/build-app.sh"

rm -rf "$INSTALL_APP"
ditto "$STAGING_APP" "$INSTALL_APP"
xattr -cr "$INSTALL_APP" 2>/dev/null || true
codesign --force --sign - \
    --requirements '=designated => identifier "com.hector.MaxxBar"' \
    "$INSTALL_APP" >/dev/null 2>&1 || true

if [ -e "$DESKTOP_LINK" ] && [ ! -L "$DESKTOP_LINK" ]; then
    echo "Desktop path exists and is not a shortcut: $DESKTOP_LINK" >&2
    exit 1
fi

if [ -L "$DESKTOP_LINK" ]; then
    rm -f "$DESKTOP_LINK"
fi
ln -s "$INSTALL_APP" "$DESKTOP_LINK"

codesign --verify --deep --strict "$INSTALL_APP"
echo "$INSTALL_APP"
