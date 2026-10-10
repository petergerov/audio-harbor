#!/bin/bash
# Builds dist/Devialet-Test.zip for the person who runs the test next to the renderer:
# the guided test as one universal binary (Apple silicon + Intel, macOS 12+), plus the guide.
#
#   ./make-tester-package.sh [Anleitung.pdf]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64 --product upnp-spike
binary=$(swift build -c release --arch arm64 --arch x86_64 --product upnp-spike --show-bin-path)/upnp-spike

rm -rf dist/Devialet-Test dist/Devialet-Test.zip
mkdir -p dist/Devialet-Test
cp "$binary" dist/Devialet-Test/devialet-test
chmod +x dist/Devialet-Test/devialet-test
if [ $# -ge 1 ]; then
    cp "$1" dist/Devialet-Test/Anleitung.pdf
fi
(cd dist && ditto -c -k --keepParent Devialet-Test Devialet-Test.zip)

lipo -info dist/Devialet-Test/devialet-test
ls -lh dist/Devialet-Test.zip
