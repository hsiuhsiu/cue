#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$repo_root"
if [[ $# -eq 2 && "$1" == "--source-root" ]]; then
    source_root="$(cd "$2" && pwd)"
elif [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--source-root <checkout-or-snapshot-directory>]\n' "$0" >&2
    exit 2
fi
benchmark_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-interactions.XXXXXX")"
trap 'rm -rf "$benchmark_directory"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$source_root"/Sources/CueCore/*.swift \
    -module-cache-path "$benchmark_directory/module-cache" \
    -emit-module-path "$benchmark_directory/CueCore.swiftmodule" \
    -o "$benchmark_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -I "$benchmark_directory" -L "$benchmark_directory" -lCueCore \
    -module-cache-path "$benchmark_directory/module-cache" \
    -Xlinker -rpath -Xlinker "$benchmark_directory" \
    "$source_root/Sources/Cue/AppIconCache.swift" \
    "$source_root/Sources/Cue/CommandIcon.swift" \
    "$source_root/Sources/Cue/Localization.swift" \
    "$source_root/Sources/Cue/LauncherAppearance.swift" \
    "$source_root/Sources/Cue/ResultShortcut.swift" \
    "$source_root/Sources/Cue/CurrencyRatesController.swift" \
    "$source_root/Sources/Cue/NetworkPolicy.swift" \
    "$source_root/Sources/Cue/FileSearchService.swift" \
    "$source_root/Sources/Cue/LauncherModel.swift" \
    "$source_root/Sources/Cue/LauncherView.swift" \
    "$repo_root/scripts/benchmark-interactions.swift" \
    -o "$benchmark_directory/benchmark-interactions"
"$benchmark_directory/benchmark-interactions"
