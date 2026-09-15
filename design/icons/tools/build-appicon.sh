#!/bin/bash
# Renders AppIcon.appiconset from the SVG masters in design/icons.
# Run from the repository root: design/icons/tools/build-appicon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SET="AudioHarbor/Resources/Assets.xcassets/AppIcon.appiconset"
BIN="$(mktemp -d)/render"

FULL="design/icons/icon-6-typenschild.svg"        # the full nameplate
SMALL="design/icons/icon-6-typenschild-klein.svg"  # AH monogram — two lines collapse below 64 px
IOS="design/icons/icon-6-typenschild-ios.svg"      # square: iOS masks the corners itself

swiftc -O -o "$BIN" design/icons/tools/render.swift

"$BIN" "$IOS"   "$SET/AppIcon-1024.png" 1024 bleed
"$BIN" "$SMALL" "$SET/mac-16.png"        16 mac
"$BIN" "$SMALL" "$SET/mac-16@2x.png"     32 mac
"$BIN" "$SMALL" "$SET/mac-32.png"        32 mac
"$BIN" "$FULL"  "$SET/mac-32@2x.png"     64 mac
"$BIN" "$FULL"  "$SET/mac-128.png"      128 mac
"$BIN" "$FULL"  "$SET/mac-128@2x.png"   256 mac
"$BIN" "$FULL"  "$SET/mac-256.png"      256 mac
"$BIN" "$FULL"  "$SET/mac-256@2x.png"   512 mac
"$BIN" "$FULL"  "$SET/mac-512.png"      512 mac
"$BIN" "$FULL"  "$SET/mac-512@2x.png"  1024 mac

echo "AppIcon.appiconset neu gerendert."
