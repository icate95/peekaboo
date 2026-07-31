#!/bin/bash
# Costruisce Peekaboo.app.
#
# Il bundle non e' un vezzo: senza di esso le notifiche di sistema non
# funzionano, l'avvio automatico e' fragile e il permesso Automazione viene
# attribuito al terminale invece che a Peekaboo.
set -euo pipefail
cd "$(dirname "$0")"

APP="Peekaboo.app"
BUNDLE_ID="com.peekaboo.ghost"
VERSION="1.0.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "compilo…"
swiftc -O Peekaboo.swift -o "$APP/Contents/MacOS/Peekaboo"

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
  <!-- niente icona nel Dock: vive nella barra in alto -->
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT</string>
  <!-- spiega perche' chiede di controllare il terminale -->
  <key>NSAppleEventsUsageDescription</key>
  <string>Peekaboo porta in primo piano la finestra del terminale della sessione che scegli.</string>
</dict>
</plist>
PLIST

# Firma ad-hoc: basta per l'uso locale e rende stabile l'identita' del bundle,
# cosi' i permessi concessi non vengono richiesti di nuovo a ogni ricompilazione.
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  echo "nota: firma ad-hoc non riuscita, l'app funziona lo stesso"

echo "✓ $APP pronta"
