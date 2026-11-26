#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
build="$root/.build"
app="$build/InkOver.app"
mkdir -p "$build"

stage="$(mktemp -d "$build/stage.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
bundle="$stage/InkOver.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$build/module-cache"

xcrun swiftc \
    -target "$(uname -m)-apple-macosx14.0" \
    -swift-version 6 -O -module-cache-path "$build/module-cache" \
    "$root"/InkOver/*.swift -o "$bundle/Contents/MacOS/InkOver"

cp "$root/InkOver/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/InkOver/Resources/InkOver.icns" "$bundle/Contents/Resources/InkOver.icns"
codesign --force --sign - --entitlements "$root/InkOver/InkOver.entitlements" "$bundle"
codesign --verify --strict "$bundle"

rm -rf -- "$app"
mv "$bundle" "$app"
printf '%s\n' "$app"
