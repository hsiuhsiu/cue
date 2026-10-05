#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-window-service.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -module-cache-path "$check_directory/module-cache" -emit-module -emit-library -module-name CueCore \
    "$repo_root/Sources/CueCore/WindowGeometry.swift" \
    -emit-module-path "$check_directory/CueCore.swiftmodule" -o "$check_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -module-cache-path "$check_directory/module-cache" -I "$check_directory" -L "$check_directory" -lCueCore \
    -Xlinker -rpath -Xlinker "$check_directory" \
    "$repo_root/Sources/Cue/WindowControlService.swift" "$repo_root/scripts/check-window-service.swift" \
    -o "$check_directory/check-window-service"
"$check_directory/check-window-service"
