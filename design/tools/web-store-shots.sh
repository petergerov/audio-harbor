#!/bin/bash
# Web copies of the App Store screenshots for the homepage (docs/index.html).
#
#   marketing/app-store/mac-1280x800/*.png       -> docs/images/web/store/mac-*.webp
#   marketing/app-store/iphone-1320x2868/*.png   -> docs/images/web/store/iphone-*.webp
#   marketing/app-store/raw/1.deck.png           -> docs/images/web/store/hero-deck.webp
#
# Each gets a card size (what the page shows, about 2x its CSS width for Retina) and a lightbox
# size in store/lb/, fetched only on click. WebP at q86 keeps the UI text and headlines crisp.
# Re-run after marketing/app-store/build.sh or build-iphone.sh.
#
# Requires cwebp (brew install webp). Usage: design/tools/web-store-shots.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
OUT=docs/images/web/store
QUALITY=86
command -v cwebp >/dev/null || { echo "cwebp not found -- brew install webp" >&2; exit 1; }
mkdir -p "$OUT/lb"

# webp <src> <dst> <width>: never upscales.
webp() {
  local sw
  sw=$(sips -g pixelWidth "$1" | awk '/pixelWidth/{print $2}')
  if [ "$sw" -gt "$3" ]; then
    cwebp -quiet -q "$QUALITY" -resize "$3" 0 "$1" -o "$2"
  else
    cwebp -quiet -q "$QUALITY" "$1" -o "$2"
  fi
  printf "%-40s %5sKB\n" "$2" "$(( $(stat -f%z "$2") / 1024 ))"
}

# Mac: 420px cards, the 1280 original in the lightbox.
for src in marketing/app-store/mac-1280x800/*.png; do
  base="mac-$(basename "$src" .png)"
  webp "$src" "$OUT/$base.webp" 840
  webp "$src" "$OUT/lb/$base.webp" 1280
done

# iPhone: 220px cards, 1000px tall-enough lightbox.
for src in marketing/app-store/iphone-1320x2868/*.png; do
  base="iphone-$(basename "$src" .png)"
  webp "$src" "$OUT/$base.webp" 480
  webp "$src" "$OUT/lb/$base.webp" 1000
done

# Hero: the plain window capture behind the first Mac shot (the device frame is drawn in CSS).
webp marketing/app-store/raw/1.deck.png "$OUT/hero-deck.webp" 1200
webp marketing/app-store/raw/1.deck.png "$OUT/lb/hero-deck.webp" 2000
