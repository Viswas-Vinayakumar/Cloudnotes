#!/bin/bash
# Builds a double-clickable CloudNotes.app from the Swift package.
# Usage:  ./scripts/build-app.sh
# Result: build/CloudNotes.app  (drag it into /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Building release binary…"
swift build -c release

APP="build/CloudNotes.app"
BIN="$(swift build -c release --show-bin-path)/CloudNotes"

echo "▸ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CloudNotes"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>CloudNotes</string>
  <key>CFBundleDisplayName</key>     <string>CloudNotes</string>
  <key>CFBundleIdentifier</key>      <string>com.viswas.cloudnotes</string>
  <key>CFBundleVersion</key>         <string>1.0</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundleExecutable</key>      <string>CloudNotes</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <key>NSHighResolutionCapable</key> <true/>
  <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc code signing (so Gatekeeper lets it run locally)…"
codesign --force --deep --sign - "$APP"

echo "✓ Done → $APP"
echo "  Drag it to /Applications, then double-click to launch."
