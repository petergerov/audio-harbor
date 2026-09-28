#!/bin/bash
# Renders the Mac App Store screenshots from raw/ and screenshots.txt into
# mac-2560x1600/ and mac-1280x800/. Run from anywhere: marketing/app-store/build.sh
set -euo pipefail

cd "$(dirname "$0")"
BIN="$(mktemp -d)/compose"
swiftc -O -o "$BIN" compose.swift
mkdir -p mac-2560x1600 mac-1280x800

index=0
while IFS='|' read -r raw eyebrow headline; do
  [[ -z "$raw" || "$raw" == \#* ]] && continue
  index=$((index + 1))
  name="$(printf '%02d' "$index")-${raw#*.}"
  "$BIN" "raw/$raw" "$eyebrow" "$headline" "mac-2560x1600/$name" "mac-1280x800/$name"
done < screenshots.txt
