#!/bin/bash
# Renders AppIcon.appiconset and the homepage icons from the PNG masters in design/icons.
# Run from the repository root: design/icons/tools/build-appicon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SET="AudioHarbor/Resources/Assets.xcassets/AppIcon.appiconset"
WEB="docs/images/web"
BIN="$(mktemp -d)/render-png"

FULL="design/icons/icon.png"           # tile with the AUDIO HARBOR wordmark — from 64 px
SMALL="design/icons/icon_no_text.png"  # symbol only — the wordmark is unreadable at 16 / 32 px

swiftc -O -o "$BIN" design/icons/tools/render-png.swift

"$BIN" "$FULL"  "$SET/AppIcon-1024.png" 1024 bleed
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

# Homepage: symbol only (favicon, nav, footer, touch icon, link preview).
"$BIN" "$SMALL" "$WEB/icon-128.png"     128 web
"$BIN" "$SMALL" "$WEB/icon-180.png"     180 web
"$BIN" "$SMALL" "docs/AppIcon.png"     1024 web

echo "AppIcon.appiconset und Homepage-Icons neu gerendert."
