#!/bin/bash
set -euo pipefail
bridge_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$bridge_dir/../../.." && pwd)"
build_dir="$project_dir/work/gofly-ios"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CARGO_HOME="$build_dir/cargo-home"
export RUSTUP_HOME="$build_dir/rustup-home"
export PATH="$build_dir/toolchain/bin:$DEVELOPER_DIR/usr/bin:$PATH"
export CARGO_TARGET_DIR="$build_dir/cargo-target"
features="$(python3 -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))["features"]))' "$bridge_dir/upstream.json")"
native_target="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["target"])' "$bridge_dir/upstream.json")"
if [[ "$native_target" != aarch64-apple-ios ]]; then
  echo "This SDK/CC recipe supports only aarch64-apple-ios" >&2
  exit 1
fi

python3 "$bridge_dir/prepare-build.py"
mkdir -p "$build_dir/native"
# Packaging builds only the iOS library; it does not create host test products.
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
IPHONEOS_DEPLOYMENT_TARGET=26.0 \
CC_aarch64_apple_ios="$(xcrun --sdk iphoneos --find clang)" \
  cargo build --manifest-path "$build_dir/native-source/Cargo.toml" -p idevice-ffi \
  --release --locked --no-default-features --features "$features" --target "$native_target"
cp "$CARGO_TARGET_DIR/$native_target/release/libidevice_ffi.a" "$build_dir/native/libidevice_ffi.a"
cp "$build_dir/native-source/ffi/idevice.h" "$build_dir/native/idevice-full.h"
cp "$build_dir/native-source/Cargo.lock" "$build_dir/native/Cargo.lock"
python3 "$bridge_dir/../scripts/verify-native.py"
python3 "$bridge_dir/prepare-build.py" --record
