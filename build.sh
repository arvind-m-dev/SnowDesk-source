#!/bin/bash
# Builds SnowDesk.app (ad-hoc signed) next to this script.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SnowDesk"

APP="SnowDesk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnowDesk"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SnowDesk</string>
    <key>CFBundleDisplayName</key><string>SnowDesk</string>
    <key>CFBundleIdentifier</key><string>local.snowdesk.app</string>
    <key>CFBundleExecutable</key><string>SnowDesk</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>SnowDesk listens for the beat of your music so the Christmas lights can flash along. Nothing is recorded or sent anywhere.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"
