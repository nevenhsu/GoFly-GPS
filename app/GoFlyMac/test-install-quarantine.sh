#!/bin/bash
set -euo pipefail

APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$APP_SOURCE/../.." && pwd)"
DMG_PATH="${1:-$WORKSPACE_ROOT/work/dist/GoFly-GPS-1.0.6-arm64.dmg}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "The quarantine installation simulation requires macOS." >&2
  exit 2
fi
if [ ! -f "$DMG_PATH" ]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 2
fi

TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/GoFly-quarantine-test.XXXXXX")"
MOUNT_POINT="$TEMP_ROOT/mount"
DOWNLOAD_COPY="$TEMP_ROOT/download"
TEST_APPLICATIONS="$TEMP_ROOT/Applications"
TEST_HOME="$TEMP_ROOT/home"
mkdir -p "$MOUNT_POINT" "$DOWNLOAD_COPY" "$TEST_APPLICATIONS" "$TEST_HOME"
MOUNTED=0
MOUNT_DEVICE=""
cleanup() {
  status=$?
  if [ "$MOUNTED" -eq 1 ]; then /usr/bin/hdiutil detach "$MOUNT_DEVICE" -quiet || true; fi
  /bin/rm -rf "$TEMP_ROOT"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" > "$TEMP_ROOT/attach.txt"
MOUNT_DEVICE="$(/usr/bin/awk '$1 ~ /^\/dev\/disk[0-9]+$/ {print $1; exit}' "$TEMP_ROOT/attach.txt")"
if [ -z "$MOUNT_DEVICE" ]; then
  echo "Could not identify the attached disk image." >&2
  exit 1
fi
MOUNTED=1
/usr/bin/ditto "$MOUNT_POINT/GoFly.app" "$DOWNLOAD_COPY/GoFly.app"
/bin/cp "$MOUNT_POINT/install.sh" "$DOWNLOAD_COPY/install.sh"
/bin/chmod u+x "$DOWNLOAD_COPY/install.sh"
/usr/bin/xattr -w com.apple.quarantine '0081;00000000;GoFly download simulation;' "$DOWNLOAD_COPY/GoFly.app"
/usr/bin/xattr -p com.apple.quarantine "$DOWNLOAD_COPY/GoFly.app" >/dev/null

# Keep the production installer fixed to /Applications. The temporary copy only
# redirects its destination and suppresses Launch Services for this isolated run.
/usr/bin/python3 - "$DOWNLOAD_COPY/install.sh" "$TEST_APPLICATIONS/GoFly.app" <<'PY'
from pathlib import Path
import sys

installer = Path(sys.argv[1])
target = sys.argv[2]
text = installer.read_text()
text = text.replace('INSTALL_TARGET="/Applications/GoFly.app"', f'INSTALL_TARGET="{target}"')
text = text.replace('open "$INSTALL_TARGET"', ': # open suppressed in the isolated test')
if 'INSTALL_TARGET="/Applications/GoFly.app"' in text or 'open "$INSTALL_TARGET"' in text:
    raise SystemExit("Could not isolate the installer target and launch step")
installer.write_text(text)
PY

bash "$DOWNLOAD_COPY/install.sh"
INSTALLED_APP="$TEST_APPLICATIONS/GoFly.app"
test -x "$INSTALLED_APP/Contents/MacOS/GoFlyMac"
test -f "$INSTALLED_APP/Contents/Resources/Python/python/install/bin/python3.14"
test -f "$INSTALLED_APP/Contents/Resources/native/libidevice_ffi.a"
if /usr/bin/xattr -p com.apple.quarantine "$INSTALLED_APP" >/dev/null 2>&1; then
  echo "Quarantine attribute remains on the installed app." >&2
  exit 1
fi

PYTHON="$INSTALLED_APP/Contents/Resources/Python/python/install/bin/python3.14"
"$PYTHON" -I -B -c 'import platform, cffi, cryptography.hazmat.bindings._rust; assert platform.machine() == "arm64"; print("Bundled Python and native extensions executed.")'
/usr/bin/lipo -archs "$INSTALLED_APP/Contents/Resources/native/libidevice_ffi.a" | /usr/bin/grep -q arm64
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"

/usr/bin/python3 - "$INSTALLED_APP" "$TEST_HOME" <<'PY'
import os
import subprocess
import sys
import time

app = sys.argv[1]
home = sys.argv[2]
binary = os.path.join(app, "Contents", "MacOS", "GoFlyMac")
env = dict(os.environ, HOME=home)
process = subprocess.Popen([
    binary, "--ui-capture", "--capture-screen=D10",
    "--capture-appearance=light", "--capture-language=en",
], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    time.sleep(2)
    if process.poll() is not None:
        raise SystemExit(f"GoFlyMac exited during launch with status {process.returncode}")
    print("Installed GoFlyMac launched in the isolated capture mode.")
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
PY

echo "Quarantine removal, app launch, bundled Python, native extension, and arm64 library checks passed."
