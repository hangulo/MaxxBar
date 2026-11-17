#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MaxxBar"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="${APP_DIR:-$ROOT_DIR/Dist.noindex/$APP_NAME.app}"
APP_VERSION="${APP_VERSION:-0.3.0}"
BUILD_VERSION="${BUILD_VERSION:-$(date +%m%d.%H%M)}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
if [ "$CONFIGURATION" = "release" ]; then
    swift build -c release
    BUILD_DIR=".build/release"
else
    swift build
    BUILD_DIR=".build/debug"
fi

mkdir -p "$(dirname "$APP_DIR")"
touch "$(dirname "$APP_DIR")/.metadata_never_index" 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
if [ -f "$ROOT_DIR/Assets/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -x "$BUILD_DIR/MaxxBarSensorHelper" ]; then
    cp "$BUILD_DIR/MaxxBarSensorHelper" "$RESOURCES_DIR/MaxxBarSensorHelper"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MaxxBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.hector.MaxxBar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MaxxBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>MaxxBar observes Command-C and Command-V shortcuts to record source and destination metadata. Clipboard contents and typed text are never stored.</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --sign - \
    --requirements '=designated => identifier "com.hector.MaxxBar"' \
    "$APP_DIR" >/dev/null 2>&1 || true
echo "$APP_DIR"
