#!/bin/bash
set -euo pipefail

APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$APP_SOURCE/../.." && pwd)"
BUILD_ROOT="$WORKSPACE_ROOT/work/gofly-mac"
APP_BUNDLE="$BUILD_ROOT/GoFly.app"
GOFLY_TEAM_ID="${1:-${GOFLY_TEAM_ID:-}}"
if [[ ! "$GOFLY_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Pass the selected Xcode Team ID as the first argument or GOFLY_TEAM_ID." >&2
  exit 2
fi
GOFLY_BUNDLE_ID="com.neven.gofly.$(printf '%s' "$GOFLY_TEAM_ID" | /usr/bin/tr '[:upper:]' '[:lower:]')"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"

PYTHON_BUILD="20260610"
PYTHON_VERSION="3.14.6"
PYTHON_ARCHIVE_NAME="cpython-${PYTHON_VERSION}+${PYTHON_BUILD}-aarch64-apple-darwin-install_only.tar.gz"
PYTHON_ARCHIVE_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_BUILD}/${PYTHON_ARCHIVE_NAME}"
PYTHON_ARCHIVE_SHA256="953db72ff2dea68b5112231b1ba77163ec9114f87c7ece530b3ea742a3b492c5"

if [ "$(uname -m)" != "arm64" ]; then
  echo "GoFly GPS for Mac V1 builds only on Apple Silicon (arm64)." >&2
  exit 1
fi
if [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
  echo "Xcode is required at $DEVELOPER_DIR." >&2
  exit 1
fi

mkdir -p "$BUILD_ROOT/cache"
PYTHON_ARCHIVE="$BUILD_ROOT/cache/$PYTHON_ARCHIVE_NAME"
PYTHON_TEMP=""
if [ ! -f "$PYTHON_ARCHIVE" ] || ! printf '%s  %s\n' "$PYTHON_ARCHIVE_SHA256" "$PYTHON_ARCHIVE" | /usr/bin/shasum -a 256 -c - >/dev/null 2>&1; then
  PYTHON_TEMP="$(/usr/bin/mktemp "$BUILD_ROOT/cache/python.XXXXXX")"
  /usr/bin/curl --fail --location --retry 2 --output "$PYTHON_TEMP" "$PYTHON_ARCHIVE_URL"
  printf '%s  %s\n' "$PYTHON_ARCHIVE_SHA256" "$PYTHON_TEMP" | /usr/bin/shasum -a 256 -c -
  /bin/mv -f "$PYTHON_TEMP" "$PYTHON_ARCHIVE"
  PYTHON_TEMP=""
fi

STAGING_ROOT="$(/usr/bin/mktemp -d "$BUILD_ROOT/GoFly-stage.XXXXXX")"
STAGING_BUNDLE="$STAGING_ROOT/GoFly.app"
trap 'rm -rf "$STAGING_ROOT"; if [ -n "$PYTHON_TEMP" ]; then rm -f "$PYTHON_TEMP"; fi' EXIT

/usr/bin/xcrun swift build --disable-sandbox --package-path "$APP_SOURCE" \
  --scratch-path "$BUILD_ROOT/build" --cache-path "$BUILD_ROOT/cache" \
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security"

PRODUCTS="$(/usr/bin/xcrun swift build --disable-sandbox --package-path "$APP_SOURCE" \
  --scratch-path "$BUILD_ROOT/build" --cache-path "$BUILD_ROOT/cache" \
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --show-bin-path)"
RESOURCES="$STAGING_BUNDLE/Contents/Resources"
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$RESOURCES/Bridge/Device" \
  "$RESOURCES/Bridge/Setup" "$RESOURCES/Python" "$RESOURCES/native" \
  "$RESOURCES/iOSProject"
cp "$PRODUCTS/GoFlyMac" "$STAGING_BUNDLE/Contents/MacOS/GoFlyMac"
cp "$APP_SOURCE/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp -R "$PRODUCTS/GoFlyMac_GoFlyMac.bundle" "$RESOURCES/"
cp "$APP_SOURCE/Bridge/bridge.py" "$APP_SOURCE/Bridge/wire.py" \
  "$RESOURCES/Bridge/"
cp "$APP_SOURCE/Bridge/Setup/__init__.py" "$APP_SOURCE"/Bridge/Setup/setup_*.py \
  "$RESOURCES/Bridge/Setup/"
cp "$APP_SOURCE/Bridge/Device/__init__.py" "$APP_SOURCE/Bridge/Device/gofly_device.py" \
  "$RESOURCES/Bridge/Device/"

# Keep the iOS build input relocatable and omit development-only material.
/usr/bin/rsync -a \
  --exclude='Tests/' --exclude='UITests/' --exclude='scripts/' \
  --exclude='/NativeBridge/build.sh' --exclude='/NativeBridge/prepare-build.py' \
  --exclude='/NativeBridge/*.patch' --exclude='/NativeBridge/upstream.json' \
  --exclude='.DS_Store' \
  --exclude='/.build/' --exclude='/.swiftpm/' --exclude='/work/' \
  "$WORKSPACE_ROOT/app/GoFly/" "$RESOURCES/iOSProject/"
if [ ! -d "$RESOURCES/iOSProject/GoFly.xcodeproj" ]; then
  echo "The bundled iOS project is incomplete." >&2
  exit 1
fi
if [ -e "$RESOURCES/iOSProject/.build" ]; then
  echo "The bundled iOS project contains a local build cache." >&2
  exit 1
fi
if /usr/bin/find "$RESOURCES/iOSProject" \( -name Tests -o -name UITests -o -name scripts -o -name build.sh -o -name prepare-build.py \) -print -quit | /usr/bin/grep -q .; then
  echo "The bundled iOS project contains excluded development files." >&2
  exit 1
fi

PYTHON_STAGING="$RESOURCES/Python/.archive"
mkdir -p "$PYTHON_STAGING"
/usr/bin/tar -xzf "$PYTHON_ARCHIVE" -C "$PYTHON_STAGING"
if [ ! -d "$PYTHON_STAGING/python" ]; then
  echo "The pinned Python archive has an unexpected top-level layout." >&2
  exit 1
fi
mkdir -p "$RESOURCES/Python/python"
/bin/mv "$PYTHON_STAGING/python" "$RESOURCES/Python/python/install"
/bin/rmdir "$PYTHON_STAGING"
PYTHON_ROOT="$RESOURCES/Python/python/install"
BUNDLED_PYTHON="$PYTHON_ROOT/bin/python3.14"
if [ ! -x "$BUNDLED_PYTHON" ]; then
  echo "The pinned Python archive did not contain its expected arm64 interpreter." >&2
  exit 1
fi
"$BUNDLED_PYTHON" -I -c 'import platform,sys; assert sys.version_info[:3] == (3,14,6); assert platform.machine() == "arm64"'
mkdir -p "$PYTHON_ROOT/lib/python3.14/site-packages"
"$BUNDLED_PYTHON" -I -m pip install --disable-pip-version-check --no-cache-dir \
  --no-compile --no-deps --only-binary=:all: \
  --target "$PYTHON_ROOT/lib/python3.14/site-packages" \
  -r "$APP_SOURCE/requirements.txt"

# Drop interpreter parts the bridge never imports (tests, IDLE, demos, bytecode caches).
PYLIB="$PYTHON_ROOT/lib/python3.14"
rm -rf "$PYLIB/test" "$PYLIB/idlelib" "$PYLIB/turtledemo"
/usr/bin/find "$PYTHON_ROOT" -name __pycache__ -type d -prune -exec rm -rf {} +

NATIVE_ARCHIVE="$WORKSPACE_ROOT/work/gofly-ios/native/libidevice_ffi.a"
if [ ! -f "$NATIVE_ARCHIVE" ] || [ -L "$NATIVE_ARCHIVE" ]; then
  echo "Missing prebuilt native library: $NATIVE_ARCHIVE" >&2
  exit 1
fi
/usr/bin/lipo -archs "$NATIVE_ARCHIVE" | /usr/bin/grep -q 'arm64' || {
  echo "The prebuilt native library does not contain arm64." >&2
  exit 1
}
cp "$NATIVE_ARCHIVE" "$RESOURCES/native/libidevice_ffi.a"

/usr/bin/python3 - "$STAGING_BUNDLE" "$GOFLY_BUNDLE_ID" <<'PY'
import plistlib
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
bundle_id = sys.argv[2]
info = {
    "CFBundleIdentifier": bundle_id,
    "CFBundleName": "GoFly GPS for Mac",
    "CFBundleDisplayName": "GoFly GPS for Mac",
    "CFBundleExecutable": "GoFlyMac",
    "CFBundleIconFile": "AppIcon",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "1.0.7",
    "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "15.0",
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
}
(bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY

# Validate only bundle contents. Do not enumerate or connect to physical devices.
"$BUNDLED_PYTHON" -I -c 'import importlib.metadata as m, platform; assert platform.machine() == "arm64"; assert m.version("pymobiledevice3") == "11.31.0"'
test -f "$RESOURCES/Bridge/bridge.py"
test -f "$RESOURCES/Bridge/Device/gofly_device.py"
test -f "$RESOURCES/iOSProject/GoFly.xcodeproj/project.pbxproj"
test -f "$RESOURCES/native/libidevice_ffi.a"
test -f "$RESOURCES/AppIcon.icns"

# Replace only this script's generated development artifact, after staging is complete.
if [ -e "$APP_BUNDLE" ]; then
  mv "$APP_BUNDLE" "$STAGING_ROOT/Previous.app"
fi
if ! mv "$STAGING_BUNDLE" "$APP_BUNDLE"; then
  if [ -d "$STAGING_ROOT/Previous.app" ]; then mv "$STAGING_ROOT/Previous.app" "$APP_BUNDLE"; fi
  exit 1
fi
printf 'Built self-contained GoFly GPS for Mac app: %s\n' "$APP_BUNDLE"
