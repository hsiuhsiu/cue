#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-launcher-keyboard.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$repo_root"/Sources/CueCore/*.swift \
    -module-cache-path "$check_directory/module-cache" \
    -emit-module-path "$check_directory/CueCore.swiftmodule" \
    -o "$check_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -I "$check_directory" -L "$check_directory" -lCueCore \
    -module-cache-path "$check_directory/module-cache" \
    -Xlinker -rpath -Xlinker "$check_directory" \
    "$repo_root/Sources/Cue/AppIconCache.swift" \
    "$repo_root/Sources/Cue/LauncherModel.swift" \
    "$repo_root/Sources/Cue/LauncherView.swift" \
    "$repo_root/scripts/check-launcher-keyboard.swift" \
    -o "$check_directory/check-launcher-keyboard"

"$check_directory/check-launcher-keyboard"
