#!/bin/bash
# Renders AppIcon.appiconset and the homepage icons from the PNG masters in design/icons.
# Run from the repository root: design/icons/tools/build-appicon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SET="AudioHarbor/Resources/Assets.xcassets/AppIcon.appiconset"
WEB="docs/images/web"
BIN="$(mktemp -d)/render-png"

FULL="design/icons/Icon_favorite.png"  # app icon: tile with the AUDIO HARBOR wordmark — from 64 px
APP_SMALL="design/icons/icon_no_text_2d.png" # the same tile, symbol only — app icon at 16 / 32 px, homepage nav / footer
SMALL="design/icons/icon_no_text.png"  # homepage link preview
FAV="design/icons/Icon_favorite.png"   # favicon + touch icon; light corners, cut out by render-favicon
LOGO="design/icons/logo_homepage.png"  # symbol + wordmark on a dark ground: app sidebar

swiftc -O -o "$BIN" design/icons/tools/render-png.swift
swiftc -O -o "$BIN-favicon" design/icons/tools/render-favicon.swift
swiftc -O -o "$BIN-logo" design/icons/tools/render-logo.swift

"$BIN" "$FULL"  "$SET/AppIcon-1024.png" 1024 bleed
"$BIN" "$APP_SMALL" "$SET/mac-16.png"    16 mac
"$BIN" "$APP_SMALL" "$SET/mac-16@2x.png" 32 mac
"$BIN" "$APP_SMALL" "$SET/mac-32.png"    32 mac
"$BIN" "$FULL"  "$SET/mac-32@2x.png"     64 mac
"$BIN" "$FULL"  "$SET/mac-128.png"      128 mac
"$BIN" "$FULL"  "$SET/mac-128@2x.png"   256 mac
"$BIN" "$FULL"  "$SET/mac-256.png"      256 mac
"$BIN" "$FULL"  "$SET/mac-256@2x.png"   512 mac
"$BIN" "$FULL"  "$SET/mac-512.png"      512 mac
"$BIN" "$FULL"  "$SET/mac-512@2x.png"  1024 mac

# Favicon and touch icon.
"$BIN-favicon" "$FAV" 32 "$WEB/favicon-32.png" 64 "$WEB/favicon-64.png" 180 "$WEB/icon-180.png"

# App sidebar (40 pt): background removed, cropped — it sits on the app's own dark chassis.
BRAND="AudioHarbor/Resources/Assets.xcassets/BrandLogo.imageset"
"$BIN-logo" "$LOGO" 40 "$BRAND/brand-logo.png" 80 "$BRAND/brand-logo@2x.png" 120 "$BRAND/brand-logo@3x.png"
# Homepage nav / footer: the flat symbol tile (40 px), "AUDIO HARBOR" is set as text beside it.
"$BIN" "$APP_SMALL" "$WEB/mark-40.png"   40 web
"$BIN" "$APP_SMALL" "$WEB/mark-80.png"   80 web
"$BIN" "$APP_SMALL" "$WEB/mark-120.png" 120 web
# WebP beside each PNG, much smaller (the pages fall back to PNG without it).
if command -v cwebp > /dev/null; then
  for SIZE in 40 80 120; do
    cwebp -quiet -q 90 -alpha_q 100 -m 6 "$WEB/mark-$SIZE.png" -o "$WEB/mark-$SIZE.webp"
  done
else
  echo "cwebp not found (brew install webp) — homepage mark WebP files not updated."
fi

# Link preview: symbol only.
"$BIN" "$SMALL" "docs/AppIcon.png"     1024 web

echo "AppIcon.appiconset, BrandLogo, Homepage-Logo und -Icons neu gerendert."
