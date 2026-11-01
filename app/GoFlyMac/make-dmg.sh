#!/bin/bash
set -euo pipefail

APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$APP_SOURCE/../.." && pwd)"
APP_BUNDLE="$WORKSPACE_ROOT/work/gofly-mac/GoFly.app"
OUTPUT_DIR="$WORKSPACE_ROOT/work/dist"
INSTALLER_SOURCE="$APP_SOURCE/install.sh"
NOTICES_GENERATOR="$APP_SOURCE/write-third-party-notices.py"
GOFLY_TEAM_ID="${1:-${GOFLY_TEAM_ID:-}}"

if [[ ! "$GOFLY_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Pass the selected Xcode Team ID as the first argument or GOFLY_TEAM_ID." >&2
  exit 2
fi

"$APP_SOURCE/build-app.sh" "$GOFLY_TEAM_ID"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "The GoFly app bundle was not built at $APP_BUNDLE." >&2
  exit 1
fi
/usr/bin/lipo -archs "$APP_BUNDLE/Contents/MacOS/GoFlyMac" | /usr/bin/grep -q arm64 || {
  echo "The GoFly Mac executable does not contain arm64." >&2
  exit 1
}

/usr/bin/codesign --force --deep -s - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
OUTPUT="$OUTPUT_DIR/GoFly-$VERSION-arm64.dmg"
CHECKSUM="$OUTPUT.sha256"
/bin/mkdir -p "$OUTPUT_DIR"
STAGING_ROOT="$(/usr/bin/mktemp -d "$OUTPUT_DIR/.GoFly-dmg.XXXXXX")"
TEMP_DMG="$STAGING_ROOT/GoFly-$VERSION-arm64.dmg"
trap 'rm -rf "$STAGING_ROOT"' EXIT

/usr/bin/ditto "$APP_BUNDLE" "$STAGING_ROOT/GoFly.app"
/bin/cp "$INSTALLER_SOURCE" "$STAGING_ROOT/install.sh"
"$APP_BUNDLE/Contents/Resources/Python/python/install/bin/python3.14" \
  -I -B "$NOTICES_GENERATOR" "$STAGING_ROOT/THIRD-PARTY-NOTICES.md"

/usr/bin/hdiutil create -quiet -volname GoFly -srcfolder "$STAGING_ROOT" \
  -format ULMO "$TEMP_DMG"
/bin/mv -f "$TEMP_DMG" "$OUTPUT"
HASH="$(/usr/bin/shasum -a 256 "$OUTPUT" | /usr/bin/awk '{print $1}')"
printf '%s  %s\n' "$HASH" "$(/usr/bin/basename "$OUTPUT")" > "$CHECKSUM"

printf 'DMG: %s\nSHA-256: %s\nChecksum: %s\n' "$OUTPUT" "$HASH" "$CHECKSUM"
