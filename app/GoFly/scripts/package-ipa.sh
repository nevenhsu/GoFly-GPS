#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
task_build="$task_root/work/gofly-ios/sidestore"
task_output="${1:-$task_root/work/dist/ipa}"
mkdir -p "$task_build"

# Build the pinned native archive on first use, or again when the pin changed.
native_manifest="$task_root/work/gofly-ios/native/manifest.json"
if ! python3 - "$native_manifest" "$task_root/app/GoFly/NativeBridge/upstream.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
manifest, pin = Path(sys.argv[1]), Path(sys.argv[2])
if not manifest.is_file() or not (manifest.parent / "libidevice_ffi.a").is_file():
    sys.exit(1)
recorded = json.loads(manifest.read_text())["sha256"]
inputs = [pin] + [pin.parent / patch for patch in json.loads(pin.read_text())["patches"]]
sys.exit(0 if all(recorded.get(f.name) == hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs) else 1)
PY
then
  echo "Building the pinned native library (first run downloads the Rust toolchain and idevice source)..."
  bash "$task_root/app/GoFly/NativeBridge/build.sh" > "$task_build/native-build.log" 2>&1 || {
    tail -60 "$task_build/native-build.log"
    exit 1
  }
fi

# Check native source patches and the Swift shim before using the prepared archive.
python3 "$task_root/app/GoFly/scripts/verify-native.py"
xcodebuild -project "$task_root/app/GoFly/GoFly.xcodeproj" -scheme GoFly \
  -sdk iphoneos -configuration Release \
  -derivedDataPath "$task_build" \
  -clonedSourcePackagesDirPath "$task_root/work/gofly-ios/packages" \
  GOFLY_NATIVE_DIR="$task_root/work/gofly-ios/native" \
  GOFLY_BUNDLE_ID=com.neven.gofly \
  PRODUCT_BUNDLE_IDENTIFIER=com.neven.gofly \
  CODE_SIGNING_ALLOWED=NO build > "$task_build/build.log" 2>&1 || {
    tail -60 "$task_build/build.log"
    exit 1
  }
python3 "$task_root/app/GoFly/scripts/package_ipa.py" \
  --app "$task_build/Build/Products/Release-iphoneos/GoFly.app" \
  --output-directory "$task_output"
