#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-long-query-benchmark.XXXXXX")"
trap 'rm -rf "$benchmark_directory"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

source_root="$repo_root"
file_dependencies=()
if [[ "${1:-}" == "--baseline-ref" && $# -eq 2 ]]; then
    source_root="$benchmark_directory/baseline"
    mkdir -p "$source_root"
    git -C "$repo_root" archive "$2" Sources/CueCore Sources/Cue/LauncherModel.swift \
        Sources/Cue/Localization.swift Sources/Cue/CurrencyRatesController.swift Sources/Cue/NetworkPolicy.swift \
        | tar -xf - -C "$source_root"
    if git -C "$repo_root" cat-file -e "$2:Sources/Cue/FileSearchService.swift" 2>/dev/null; then
        git -C "$repo_root" show "$2:Sources/Cue/FileSearchService.swift" > "$source_root/Sources/Cue/FileSearchService.swift"
    fi
elif [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--baseline-ref <git-ref>]\n' "$0" >&2
    exit 2
fi

if [[ -f "$source_root/Sources/Cue/FileSearchService.swift" ]]; then
    file_dependencies=("$source_root/Sources/Cue/FileSearchService.swift")
fi

xcrun swiftc -swift-version 6 -O -parse-as-library -emit-module -emit-library -module-name CueCore \
    "$source_root"/Sources/CueCore/*.swift -module-cache-path "$benchmark_directory/module-cache" \
    -emit-module-path "$benchmark_directory/CueCore.swiftmodule" -o "$benchmark_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -I "$benchmark_directory" -L "$benchmark_directory" -lCueCore \
    -module-cache-path "$benchmark_directory/module-cache" -Xlinker -rpath -Xlinker "$benchmark_directory" \
    "${file_dependencies[@]}" \
    "$source_root/Sources/Cue/Localization.swift" "$source_root/Sources/Cue/LauncherModel.swift" \
    "$source_root/Sources/Cue/CurrencyRatesController.swift" "$source_root/Sources/Cue/NetworkPolicy.swift" \
    "$repo_root/scripts/benchmark-long-query.swift" -o "$benchmark_directory/benchmark-long-query"
"$benchmark_directory/benchmark-long-query"
