#!/bin/bash
# App Store screenshots for the Mac listing.
#
# Apple accepts 1280x800, 1440x900, 2560x1600 or 2880x1800 for macOS. This
# captures a 1280x800 point window, which a Retina display renders at
# 2560x1600 pixels, then writes a downscaled 1280x800 copy as well. One full
# set at either size satisfies the listing; shipping both costs nothing.
#
# Needs two permissions in System Settings > Privacy & Security, granted to
# whichever app runs this (Terminal, iTerm, Claude Code):
#   - Screen Recording, or screencapture returns a black or empty image
#   - Accessibility, or the window cannot be resized to an exact size
#
# Usage: design/tools/capture-screenshots.sh [output-dir]

set -euo pipefail

OUT="${1:-design/screenshots}"
APP_NAME="AudioHarbor"
W=1280
H=800
ORIGIN_X=40
ORIGIN_Y=60

APP_PATH=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/AudioHarbor-*/Build/Products/Release/AudioHarbor.app 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "No Release build found. Run:" >&2
  echo "  xcodebuild -project AudioHarbor.xcodeproj -scheme AudioHarbor -configuration Release -destination 'platform=macOS' build" >&2
  exit 1
fi

mkdir -p "$OUT"

# The five shots from APP_STORE_SUBMISSION.md section 5, in listing order.
SHOTS=(
  "01-catalogue|Catalogue — albums, quiet, a real library with artwork"
  "02-deck|Deck / Now Playing with the VU meters moving"
  "03-settings-output|Settings — Shared / Exclusive / DoP explained"
  "04-plugin-rack|Plugin rack on Shared, at least one insert loaded"
  "05-unlock|Paywall or Settings showing trial state and Restore"
)

echo "App:    $APP_PATH"
echo "Output: $OUT"
echo

open -a "$APP_PATH"
sleep 2

resize_window() {
  osascript <<EOF 2>/dev/null || { echo "Could not resize the window. Grant Accessibility permission and retry." >&2; exit 1; }
tell application "System Events"
  tell process "$APP_NAME"
    set frontmost to true
    set position of window 1 to {$ORIGIN_X, $ORIGIN_Y}
    set size of window 1 to {$W, $H}
  end tell
end tell
EOF
}

for entry in "${SHOTS[@]}"; do
  name="${entry%%|*}"
  desc="${entry#*|}"
  echo "── $name"
  echo "   $desc"
  read -r -p "   Put the app in that state, then press Return (s to skip): " answer
  [ "$answer" = "s" ] && { echo "   skipped"; echo; continue; }

  resize_window
  sleep 0.6

  retina="$OUT/${name}@2x.png"
  screencapture -x -R "${ORIGIN_X},${ORIGIN_Y},${W},${H}" "$retina"

  px=$(sips -g pixelWidth "$retina" | awk '/pixelWidth/{print $2}')
  py=$(sips -g pixelHeight "$retina" | awk '/pixelHeight/{print $2}')

  # A non-Retina display captures at 1280x800; upscaling would look soft, so
  # only resample when the capture really came back at 2x.
  if [ "$px" = "2560" ] && [ "$py" = "1600" ]; then
    sips -z 800 1280 "$retina" --out "$OUT/${name}.png" >/dev/null
    echo "   $px x $py  ->  also wrote ${name}.png at 1280x800"
  else
    echo "   $px x $py"
    if [ "$px" != "1280" ] || [ "$py" != "800" ]; then
      echo "   WARNING: not an App Store size. Expected 2560x1600 or 1280x800." >&2
    fi
  fi
  echo
done

echo "Done. Files in $OUT:"
ls -1 "$OUT" 2>/dev/null || true
echo
echo "Before uploading, check each shot for:"
echo "  - no personal filenames or paths you would rather not publish"
echo "  - no placeholder or debug UI"
echo "  - the price shown matches the IAP you configured in App Store Connect"
