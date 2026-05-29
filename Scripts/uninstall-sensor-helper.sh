#!/bin/sh
set -eu

HELPER_ID="com.hector.MenuBarStatsSensorHelper"
HELPER_BINARY="/Library/PrivilegedHelperTools/$HELPER_ID"
PLIST="/Library/LaunchDaemons/$HELPER_ID.plist"

sudo launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
sudo rm -f "$PLIST" "$HELPER_BINARY"

echo "Uninstalled $HELPER_ID"
