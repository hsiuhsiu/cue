#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-command-icons.XXXXXX")"
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
    "$repo_root/Sources/Cue/CommandIcon.swift" \
    "$repo_root/Sources/Cue/Localization.swift" \
    "$repo_root/Sources/Cue/LauncherAppearance.swift" \
    "$repo_root/Sources/Cue/ResultShortcut.swift" \
    "$repo_root/Sources/Cue/LauncherModel.swift" \
    "$repo_root/Sources/Cue/LauncherView.swift" \
    "$repo_root/scripts/check-command-icons.swift" \
    -o "$check_directory/check-command-icons"

"$check_directory/check-command-icons" "$@"
