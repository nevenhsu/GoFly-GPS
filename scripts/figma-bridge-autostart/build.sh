#!/bin/bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output_dir="${1:-"$source_dir/../../work/figma-bridge-autostart"}"
if (( $# > 1 )); then
  printf 'Usage: %s [output-directory]\n' "$0" >&2
  exit 2
fi

mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
app_name="Figma Bridge Autostart.app"
target="$output_dir/$app_name"
if [[ -e "$target" || -L "$target" ]]; then
  printf 'An app already exists at %s. Choose a different output directory.\n' "$target" >&2
  exit 1
fi

stage="$(mktemp -d "$output_dir/.build.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
app="$stage/$app_name"
contents="$app/Contents"
mkdir -p -- "$contents/MacOS" "$contents/Resources"
install -m 644 "$source_dir/Info.plist" "$contents/Info.plist"
install -m 644 "$source_dir/AppIcon.icns" "$contents/Resources/AppIcon.icns"
plutil -lint "$contents/Info.plist"
xcrun swiftc -swift-version 6 -O "$source_dir/main.swift" -o "$contents/MacOS/FigmaBridgeAutostart"
codesign --sign - "$app"
codesign --verify --strict "$app"
mv -n -- "$app" "$output_dir/"
if [[ -e "$app" ]]; then
  printf 'The output already exists at %s.\n' "$target" >&2
  exit 1
fi
printf '%s\n' "$target"
