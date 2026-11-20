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

# The installed app is an optimized build; set CONFIGURATION=debug to install a debug build.
APP_DIR="$STAGING_APP" CONFIGURATION="${CONFIGURATION:-release}" "$ROOT_DIR/Scripts/build-app.sh"

rm -rf "$INSTALL_APP"
ditto "$STAGING_APP" "$INSTALL_APP"
xattr -cr "$INSTALL_APP" 2>/dev/null || true
codesign --force --sign - \
    --requirements '=designated => identifier "com.hector.MaxxBar"' \
    "$INSTALL_APP" >/dev/null 2>&1 || true

# The Desktop syncs through iCloud on the development Macs. Deleting and recreating the
# shortcut on every install races that sync and leaves numbered copies ("MaxxBar 2.app"),
# so keep any existing shortcut that already points at the install.
desktop_has_link() {
    for item in "$HOME/Desktop/$APP_NAME"*; do
        [ -L "$item" ] && [ "$(readlink "$item")" = "$INSTALL_APP" ] && return 0
    done
    return 1
}

if ! desktop_has_link; then
    if [ -e "$DESKTOP_LINK" ] && [ ! -L "$DESKTOP_LINK" ]; then
        echo "Desktop path exists and is not a shortcut: $DESKTOP_LINK" >&2
        exit 1
    fi
    rm -f "$DESKTOP_LINK"
    ln -s "$INSTALL_APP" "$DESKTOP_LINK"
fi

codesign --verify --deep --strict "$INSTALL_APP"
echo "$INSTALL_APP"
