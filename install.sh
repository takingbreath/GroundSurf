#!/bin/bash
# GroundSurf 1.3.0 preview. Downloaded code and artifacts can be reviewed on GitHub.
# The ZIP checksum is pinned to this release. No sudo or developer tools required.
set -euo pipefail
fail() { printf 'GroundSurf: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail "This installer supports macOS only."
[[ "$(id -u)" -ne 0 ]] || fail "Run as your own user, without sudo."
major="$(sw_vers -productVersion | cut -d . -f 1)"
[[ "$major" -ge 13 ]] || fail "macOS 13 or later is required."
case "$(uname -m)" in arm64|x86_64) ;; *) fail "Unsupported processor." ;; esac
DEST="${GROUNDSURF_INSTALL_DIR:-$HOME/Applications}"
[[ "$DEST" == /* ]] || fail "Install directory must be an absolute path."
TARGET="$DEST/GroundSurf.app"
[[ ! -L "$TARGET" ]] || fail "Existing target is a symlink; choose another install directory."
if [[ -e "$TARGET" ]]; then
  [[ -d "$TARGET" ]] || fail "Existing target is not an app directory."
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$existing_id" == local.groundsurf.wallpaper ]] || fail "Existing app has a different identity."
  if pgrep -x GroundSurf >/dev/null; then fail "Quit GroundSurf before updating it."; fi
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/groundsurf-download.XXXXXX")"
STAGE=""
cleanup() { rm -rf "$TMP"; [[ -z "$STAGE" ]] || rm -rf "$STAGE"; }
trap cleanup EXIT
URL="https://github.com/takingbreath/GroundSurf/releases/download/v1.3.0/GroundSurf-1.3.0-universal.zip"
EXPECTED="88b805bfd2b284a07f7c2b8063726f7d28c729077b2ecf44faf867efe95b8589"
printf 'Downloading GroundSurf 1.3.0 (universal Mac preview)...\n'
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --retry 3 "$URL" -o "$TMP/GroundSurf.zip"
ACTUAL="$(shasum -a 256 "$TMP/GroundSurf.zip" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || fail "Download checksum mismatch; nothing was installed."
ditto -x -k "$TMP/GroundSurf.zip" "$TMP/unpacked"
APP="$TMP/unpacked/GroundSurf.app"
[[ -d "$APP" ]] || fail "Release does not contain GroundSurf.app."
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" == local.groundsurf.wallpaper ]] || fail "Unexpected app identity."
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == 1.3.0 ]] || fail "Unexpected app version."
codesign --verify --deep --strict "$APP"
mkdir -p "$DEST"
STAGE="$(mktemp -d "$DEST/.groundsurf-install.XXXXXX")"
ditto "$APP" "$STAGE/GroundSurf.app"
# Preserve macOS's first-launch assessment for this internet download.
xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");GroundSurf Installer;$(uuidgen)" "$STAGE/GroundSurf.app"
codesign --verify --deep --strict "$STAGE/GroundSurf.app"
BACKUP=""
if [[ -e "$TARGET" ]]; then
  BACKUP="$DEST/GroundSurf.previous.$(date +%Y%m%d-%H%M%S).app"
  [[ ! -e "$BACKUP" ]] || fail "Backup path exists; please retry later."
  mv "$TARGET" "$BACKUP"
fi
if ! mv "$STAGE/GroundSurf.app" "$TARGET"; then
  [[ -z "$BACKUP" ]] || mv "$BACKUP" "$TARGET"
  fail "Could not finish installation; previous app restored."
fi
printf '\nInstalled: %s\n' "$TARGET"
[[ -z "$BACKUP" ]] || printf 'Previous version saved: %s\n' "$BACKUP"
printf '\nThis preview is ad-hoc signed, not Apple notarized.\n'
printf 'Open the app in Finder. macOS may block its first launch.\n'
printf 'Read Apple’s first-launch guidance: https://support.apple.com/en-us/102445\n'
printf 'Use its menu bar entry to pause or quit. Launch at login is not configured.\n'
