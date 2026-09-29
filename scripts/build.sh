#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p dist
if [[ "${1:-}" == "--universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64 --disable-sandbox
    BINARY_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path --disable-sandbox)
else
    swift build -c release --disable-sandbox
    BINARY_DIR=$(swift build -c release --show-bin-path --disable-sandbox)
fi
APP="$PWD/dist/SoundSwipe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY_DIR/SoundSwipe" "$APP/Contents/MacOS/SoundSwipe"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" dist/SoundSwipe.zip
printf 'Built %s\n' "$APP"
du -sh "$APP" dist/SoundSwipe.zip
