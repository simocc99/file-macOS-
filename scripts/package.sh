#!/bin/bash
# Compila Clementine e crea Clementine.app (universale, firma ad-hoc) + Clementine.zip
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Clementine"

APP="dist/Clementine.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Clementine"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Clementine</string>
  <key>CFBundleDisplayName</key><string>Clementine</string>
  <key>CFBundleIdentifier</key><string>com.simocc99.clementine</string>
  <key>CFBundleExecutable</key><string>Clementine</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
(cd dist && zip -qr Clementine.zip Clementine.app)
echo "Creato dist/Clementine.zip"
