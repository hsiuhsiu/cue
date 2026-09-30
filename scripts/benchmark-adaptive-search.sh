#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-adaptive-search-benchmark.XXXXXX")"
trap 'rm -rf "$benchmark_directory"' EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

source_root="$repo_root"
build_flags=(-D ADAPTIVE_SEARCH)
model_dependencies=(
    "$repo_root/Sources/Cue/CurrencyRatesController.swift"
    "$repo_root/Sources/Cue/NetworkPolicy.swift"
)
if [[ "${1:-}" == "--baseline-ref" && $# -eq 2 ]]; then
    source_root="$benchmark_directory/baseline"
    mkdir -p "$source_root"
    git -C "$repo_root" archive "$2" Sources/CueCore Sources/Cue/LauncherModel.swift Sources/Cue/Localization.swift \
        | tar -xf - -C "$source_root"
    build_flags=(-D BASELINE_SEARCH)
    model_dependencies=()
elif [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--baseline-ref <git-ref-before-adaptive-search>]\n' "$0" >&2
    exit 2
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$source_root"/Sources/CueCore/*.swift \
    -module-cache-path "$benchmark_directory/module-cache" \
    -emit-module-path "$benchmark_directory/CueCore.swiftmodule" \
    -o "$benchmark_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library "${build_flags[@]}" \
    -I "$benchmark_directory" -L "$benchmark_directory" -lCueCore \
    -module-cache-path "$benchmark_directory/module-cache" \
    -Xlinker -rpath -Xlinker "$benchmark_directory" \
    "$source_root/Sources/Cue/Localization.swift" \
    "$source_root/Sources/Cue/LauncherModel.swift" \
    "${model_dependencies[@]}" \
    "$repo_root/scripts/benchmark-adaptive-search.swift" \
    -o "$benchmark_directory/benchmark-adaptive-search"

"$benchmark_directory/benchmark-adaptive-search"
