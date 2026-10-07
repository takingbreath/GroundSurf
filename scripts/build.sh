#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${GROUNDSURF_BUILD_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/groundsurf-build.XXXXXX")}"
APP="$BUILD_DIR/GroundSurf.app"
python3 "$ROOT/Sources/assemble.py"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Sources/landscape.html" "$ROOT/Sources/GroundSurf.icns" "$ROOT/Sources/LICENSE-original.txt" "$APP/Contents/Resources/"
cp "$ROOT/Sources/Info.plist" "$APP/Contents/"
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos13.0" "$ROOT/Sources/main.swift" -o "$BUILD_DIR/GroundSurf-$arch" -framework Cocoa -framework WebKit
done
xcrun lipo -create "$BUILD_DIR/GroundSurf-arm64" "$BUILD_DIR/GroundSurf-x86_64" -output "$APP/Contents/MacOS/GroundSurf"
xattr -cr "$APP"
codesign --force --options runtime --sign "${GROUNDSURF_SIGNING_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
