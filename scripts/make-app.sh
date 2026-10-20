#!/bin/bash
# Builds Tenix-ChaeDiew.app next to this repo's root.
# Set SIGN_IDENTITY to a stable code-signing identity (e.g. "Developer ID Application: ...")
# so macOS keeps the Screen Recording permission across rebuilds; ad-hoc ("-") resets it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ChaeDiew"

APP="Tenix-ChaeDiew.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tenix-ChaeDiew"

# App icon from the brand SVGs (regenerate with: swiftc -O scripts/make-brand-assets.swift -o /tmp/mba && /tmp/mba)
if [ ! -f brand/build/AppIcon.icns ]; then
  swiftc -O scripts/make-brand-assets.swift -o /tmp/make-brand-assets && /tmp/make-brand-assets
fi
cp brand/build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Tenix-ChaeDiew</string>
  <key>CFBundleDisplayName</key><string>Tenix-ChaeDiew</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID:-com.tenix.chaediew}</string>
  <key>CFBundleExecutable</key><string>Tenix-ChaeDiew</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Powered by Panupong Nijjaboon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Tenix-ChaeDiew</string>
    <key>CFBundleURLSchemes</key><array><string>chaediew</string></array>
  </dict></array>
</dict></plist>
PLIST

# A stable identity keeps the Keychain "Always Allow" valid across rebuilds; ad-hoc ("-") changes the signature every build and macOS asks again.
if [ -z "${SIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning | grep -q "TENIX-Echo Local Signing"; then SIGN_IDENTITY="TENIX-Echo Local Signing"; fi
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $(pwd)/$APP"
