#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
mkdir -p "$DIST"
APP="$(bash "$ROOT/scripts/build.sh")"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/groundsurf-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ditto -c -k --keepParent "$APP" "$DIST/GroundSurf-$VERSION-universal.zip"
ditto "$APP" "$STAGE/GroundSurf.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/Install.txt" "$STAGE/Read Me.txt"
hdiutil create -volname GroundSurf -srcfolder "$STAGE" -ov -format UDZO "$DIST/GroundSurf-$VERSION-universal.dmg"
(cd "$DIST" && shasum -a 256 "GroundSurf-$VERSION-universal.zip" "GroundSurf-$VERSION-universal.dmg" > SHA256SUMS)
printf 'Release artifacts: %s\n' "$DIST"
