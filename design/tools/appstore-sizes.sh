#!/bin/bash
# Render App Store screenshot sizes from the source captures.
#
# Apple accepts 1280x800, 1440x900, 2560x1600 and 2880x1800 for macOS -- all
# 16:10. The captures are not 16:10, so scaling them to fit would stretch the
# window. Each image is scaled to fit inside the target and centred on an
# opaque canvas instead, which keeps the UI at its true proportions.
#
# Usage: design/tools/appstore-sizes.sh [source-dir] [output-dir]

set -euo pipefail

SRC="${1:-docs/images}"
OUT="${2:-design/screenshots/appstore}"
PAD="000000"   # the captures already sit on black

SIZES=(1280x800 1440x900 2560x1600 2880x1800)

shopt -s nullglob
sources=("$SRC"/*.png)
if [ ${#sources[@]} -eq 0 ]; then
  echo "No PNGs in $SRC" >&2
  exit 1
fi

for size in "${SIZES[@]}"; do
  tw="${size%x*}"
  th="${size#*x}"
  mkdir -p "$OUT/$size"

  for src in "${sources[@]}"; do
    base=$(basename "$src")
    dst="$OUT/$size/$base"

    sw=$(sips -g pixelWidth  "$src" | awk '/pixelWidth/{print $2}')
    sh=$(sips -g pixelHeight "$src" | awk '/pixelHeight/{print $2}')

    # Fit inside the target: constrain by whichever side runs out first.
    # Integer compare of sw/sh against tw/th without floating point.
    if [ $(( sw * th )) -gt $(( tw * sh )) ]; then
      sips --resampleWidth "$tw" "$src" --out "$dst" >/dev/null
    else
      sips --resampleHeight "$th" "$src" --out "$dst" >/dev/null
    fi

    # Centre on an opaque canvas at exactly the target size.
    sips -p "$th" "$tw" --padColor "$PAD" "$dst" >/dev/null 2>&1

    got=$(sips -g pixelWidth -g pixelHeight "$dst" | awk '/pixelWidth|pixelHeight/{printf "%s", $2"x"} END{print ""}' | sed 's/x$//')
    if [ "$got" != "${tw}x${th}" ]; then
      echo "FAIL $size/$base -> $got" >&2
      exit 1
    fi
  done
  echo "$size: ${#sources[@]} files"
done

echo
echo "Written to $OUT"
