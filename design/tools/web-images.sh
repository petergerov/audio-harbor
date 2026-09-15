#!/bin/bash
# Build the web-sized images the homepage actually serves.
#
# The source captures are 2672px wide. index.html shows the hero at 420px
# and each gallery card at 280px, so shipping the originals sent roughly six
# times more pixels than any display could use -- about 10MB for one page.
#
# 1200px covers the hero at just under 3x, which is generous for Retina, and
# WebP at q88 keeps UI text crisp. Result is around 85KB per image.
#
# The originals stay in docs/images: they are the source for
# design/tools/appstore-sizes.sh and should not be downscaled in place.
#
# Requires cwebp (brew install webp).
#
# Usage: design/tools/web-images.sh [source-dir] [output-dir]

set -euo pipefail

SRC="${1:-docs/images}"
OUT="${2:-docs/images/web}"
WIDTH=1200
QUALITY=88

command -v cwebp >/dev/null || { echo "cwebp not found -- brew install webp" >&2; exit 1; }

mkdir -p "$OUT"

shopt -s nullglob
total_before=0
total_after=0

for src in "$SRC"/*.png; do
  base=$(basename "$src" .png)
  dst="$OUT/$base.webp"

  sw=$(sips -g pixelWidth "$src" | awk '/pixelWidth/{print $2}')
  # Never upscale: a capture narrower than the target is copied at its size.
  if [ "$sw" -gt "$WIDTH" ]; then
    cwebp -quiet -q "$QUALITY" -resize "$WIDTH" 0 "$src" -o "$dst"
  else
    cwebp -quiet -q "$QUALITY" "$src" -o "$dst"
  fi

  before=$(stat -f%z "$src")
  after=$(stat -f%z "$dst")
  total_before=$(( total_before + before ))
  total_after=$(( total_after + after ))

  printf "%-24s %6sKB -> %5sKB\n" "$base" "$(( before / 1024 ))" "$(( after / 1024 ))"
done

if [ "$total_before" -eq 0 ]; then
  echo "No PNGs in $SRC" >&2
  exit 1
fi

echo
printf "total %sKB -> %sKB (%s%% of original)\n" \
  "$(( total_before / 1024 ))" "$(( total_after / 1024 ))" \
  "$(( total_after * 100 / total_before ))"
