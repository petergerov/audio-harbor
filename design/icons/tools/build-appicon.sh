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
FAV="design/icons/Icon_favorite.png"   # favicon + touch icon; light corners, cut out by render-favicon

swiftc -O -o "$BIN" design/icons/tools/render-png.swift
swiftc -O -o "$BIN-favicon" design/icons/tools/render-favicon.swift

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

# Homepage: symbol only (nav, footer, link preview).
"$BIN" "$SMALL" "$WEB/icon-128.png"     128 web

# Favicon and touch icon.
"$BIN-favicon" "$FAV" 32 "$WEB/favicon-32.png" 64 "$WEB/favicon-64.png" 180 "$WEB/icon-180.png"
"$BIN" "$SMALL" "docs/AppIcon.png"     1024 web

echo "AppIcon.appiconset und Homepage-Icons neu gerendert."
