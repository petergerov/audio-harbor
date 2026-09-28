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
APP_SMALL="design/icons/icon_no_text_2d.png" # the same tile, symbol only — wordmark unreadable at 16 / 32 px
SMALL="design/icons/icon_no_text.png"  # homepage link preview
FAV="design/icons/Icon_favorite.png"   # favicon + touch icon; light corners, cut out by render-favicon
LOGO="design/icons/logo_homepage.png"  # symbol + wordmark on a dark ground: app sidebar and homepage nav / footer

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

# Logo, background removed and cropped: app sidebar (40 pt) and homepage nav / footer (28 px).
BRAND="AudioHarbor/Resources/Assets.xcassets/BrandLogo.imageset"
"$BIN-logo" "$LOGO" 40 "$BRAND/brand-logo.png" 80 "$BRAND/brand-logo@2x.png" 120 "$BRAND/brand-logo@3x.png"
"$BIN-logo" "$LOGO" 28 "$WEB/logo-28.png" 56 "$WEB/logo-56.png" 84 "$WEB/logo-84.png"
# WebP beside each PNG, about half the size (the pages fall back to PNG without it).
if command -v cwebp > /dev/null; then
  for SIZE in 28 56 84; do
    cwebp -quiet -q 90 -alpha_q 100 -m 6 "$WEB/logo-$SIZE.png" -o "$WEB/logo-$SIZE.webp"
  done
else
  echo "cwebp not found (brew install webp) — logo WebP files not updated."
fi

# Link preview: symbol only.
"$BIN" "$SMALL" "docs/AppIcon.png"     1024 web

echo "AppIcon.appiconset, BrandLogo, Homepage-Logo und -Icons neu gerendert."
