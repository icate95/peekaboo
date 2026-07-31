#!/bin/bash
# Builds Peekaboo.app.
#
# The bundle is not a flourish: without it system notifications don't work,
# launch-at-login is fragile, and the Automation permission gets attributed to
# the terminal instead of to Peekaboo.
set -euo pipefail
cd "$(dirname "$0")"

APP="Peekaboo.app"
BUNDLE_ID="com.peekaboo.ghost"
VERSION="1.0.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "compiling…"
swiftc -O Peekaboo.swift -o "$APP/Contents/MacOS/Peekaboo"

# The server and the UI go inside the bundle, so Peekaboo.app starts on its own
# from a double click, with no run.sh, and can be moved into Applications.
cp server.py "$APP/Contents/Resources/"
cp -R ui "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Peekaboo</string>
  <key>CFBundleDisplayName</key><string>Peekaboo</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>Peekaboo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <!-- no Dock icon: it lives in the menu bar -->
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT</string>
  <!-- explains why it asks to control the terminal -->
  <key>NSAppleEventsUsageDescription</key>
  <string>Peekaboo brings the terminal window of the session you pick to the front.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for local use, and it keeps the bundle identity
# stable so granted permissions aren't asked for again on every rebuild.
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  echo "note: ad-hoc signing failed, the app still works"

echo "✓ $APP ready"
