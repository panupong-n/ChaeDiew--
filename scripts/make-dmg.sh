#!/bin/bash
# Builds the macOS installer: dist/Tenix-ChaeDiew-<version>.dmg (drag the app onto Applications).
# Run from anywhere. Set SIGN_IDENTITY to a Developer ID so macOS keeps Screen Recording permission across updates.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
./scripts/make-app.sh

STAGE="$(mktemp -d)/Tenix-ChaeDiew"
mkdir -p "$STAGE"
cp -R Tenix-ChaeDiew.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read me.txt" <<TXT
Tenix-ChaeDiew ${VERSION}
Powered by Panupong Nijjaboon

Install: drag Tenix-ChaeDiew onto Applications, open it, and allow
System Settings > Privacy & Security > Screen Recording (and Accessibility for auto-scrolling capture).
A 14-day trial starts on first launch. To activate: paste your license key under Preferences > License. That's all.
TXT

mkdir -p dist
OUT="dist/Tenix-ChaeDiew-${VERSION}.dmg"
rm -f "$OUT"
hdiutil create -volname "Tenix-ChaeDiew" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$(dirname "$STAGE")"
echo "Built $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
