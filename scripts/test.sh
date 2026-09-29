#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
FLAGS=()
# Command Line Tools ship Swift Testing outside the default search paths; Xcode does not need this.
DEV="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV" == */CommandLineTools ]]; then
    FRAMEWORKS="$DEV/Library/Developer/Frameworks"
    LIBS="$DEV/Library/Developer/usr/lib"
    FLAGS=(-Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS"
           -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBS")
fi
swift test --disable-sandbox ${FLAGS[@]+"${FLAGS[@]}"}
