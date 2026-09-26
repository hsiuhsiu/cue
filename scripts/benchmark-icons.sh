#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-icons.XXXXXX")"
trap 'rm -rf "$benchmark_directory"' EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

optimization="${CUE_BENCHMARK_OPTIMIZATION:--O}"
xcrun swiftc -swift-version 6 "$optimization" -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$repo_root"/Sources/CueCore/*.swift \
    -module-cache-path "$benchmark_directory/module-cache" \
    -emit-module-path "$benchmark_directory/CueCore.swiftmodule" \
    -o "$benchmark_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 "$optimization" -parse-as-library \
    -I "$benchmark_directory" -L "$benchmark_directory" -lCueCore \
    -module-cache-path "$benchmark_directory/module-cache" \
    -Xlinker -rpath -Xlinker "$benchmark_directory" \
    "$repo_root/scripts/benchmark-icons.swift" -o "$benchmark_directory/benchmark-icons"

# Fresh processes keep the two first-use groups independent; the OS cache remains shared.
"$benchmark_directory/benchmark-icons" 20
"$benchmark_directory/benchmark-icons"
