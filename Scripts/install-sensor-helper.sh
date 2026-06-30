#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_ID="com.hector.MaxxBarSensorHelper"
HELPER_BINARY="/Library/PrivilegedHelperTools/$HELPER_ID"
PLIST="/Library/LaunchDaemons/$HELPER_ID.plist"
OUTPUT_DIR="/Library/Application Support/MaxxBar"
OUTPUT_FILE="$OUTPUT_DIR/sensors.json"

cd "$ROOT_DIR"
swift build -c release --product MaxxBarSensorHelper

sudo mkdir -p /Library/PrivilegedHelperTools "$OUTPUT_DIR"
sudo cp ".build/release/MaxxBarSensorHelper" "$HELPER_BINARY"
sudo chown root:wheel "$HELPER_BINARY"
sudo chmod 755 "$HELPER_BINARY"

TMP_PLIST="$(mktemp)"
cat > "$TMP_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$HELPER_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HELPER_BINARY</string>
        <string>--daemon</string>
        <string>--output</string>
        <string>$OUTPUT_FILE</string>
        <string>--interval</string>
        <string>3</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/MaxxBarSensorHelper.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/MaxxBarSensorHelper.err</string>
</dict>
</plist>
PLIST

sudo cp "$TMP_PLIST" "$PLIST"
rm -f "$TMP_PLIST"
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"

sudo launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
sudo launchctl bootstrap system "$PLIST"
sudo launchctl kickstart -k "system/$HELPER_ID"

echo "Installed $HELPER_ID"
echo "Sensor cache: $OUTPUT_FILE"
