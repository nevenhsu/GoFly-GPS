#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
task_build="$task_root/work/gofly-ios/sidestore"
task_output="${1:-$task_root/work/dist/ipa}"
mkdir -p "$task_build"

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
