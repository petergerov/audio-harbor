#!/bin/bash
# Renders the iPad App Store screenshots from raw-ipad/ and screenshots-ipad.txt into
# ipad-2064x2752/. Run from anywhere: marketing/app-store/build-ipad.sh
#
#   --capture   first rebuild raw-ipad/: builds the Debug app for an iPad Pro 13-inch (M5)
#               simulator and launches each scene with `-remoteScreenshot <scene>`, which shows
#               made-up fixture data (RemoteScreenshotFixture.swift) instead of a real Mac.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"

if [[ "${1:-}" == "--capture" ]]; then
  SIM_NAME="iPad Pro 13-inch (M5)"
  SIM=$(xcrun simctl list devices available | grep -m1 -F "$SIM_NAME (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [[ -n "$SIM" ]] || { echo "No $SIM_NAME simulator installed." >&2; exit 1; }
  DD="$(mktemp -d)/dd"
  xcodebuild -project "$ROOT/AudioHarbor.xcodeproj" -scheme AudioHarbor -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" build -quiet
  xcrun simctl boot "$SIM" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM" -b >/dev/null
  xcrun simctl ui "$SIM" appearance dark
  xcrun simctl status_bar "$SIM" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
  xcrun simctl install "$SIM" "$DD/Build/Products/Debug-iphonesimulator/AudioHarbor.app"
  mkdir -p raw-ipad
  for scene in now browse nearby pairing; do
    xcrun simctl terminate "$SIM" com.gerov.audioharbor.player 2>/dev/null || true
    xcrun simctl launch "$SIM" com.gerov.audioharbor.player -remoteScreenshot "$scene" >/dev/null
    sleep 4
    xcrun simctl io "$SIM" screenshot "raw-ipad/$scene.png" >/dev/null 2>&1
    echo "raw-ipad/$scene.png"
  done
  xcrun simctl status_bar "$SIM" clear
fi

BIN="$(mktemp -d)/compose-ipad"
swiftc -O -o "$BIN" compose-iphone.swift
mkdir -p ipad-2064x2752

index=0
while IFS='|' read -r raw eyebrow headline; do
  [[ -z "$raw" || "$raw" == \#* ]] && continue
  index=$((index + 1))
  "$BIN" "raw-ipad/$raw" "$eyebrow" "$headline" "ipad-2064x2752/$(printf '%02d' "$index")-$raw" 2064 2752
done < screenshots-ipad.txt
