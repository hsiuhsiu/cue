#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-clipboard-benchmark.XXXXXX")"
trap 'rm -rf "$benchmark_directory"' EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$repo_root"/Sources/CueCore/*.swift \
    -module-cache-path "$benchmark_directory/module-cache" \
    -emit-module-path "$benchmark_directory/CueCore.swiftmodule" \
    -o "$benchmark_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -I "$benchmark_directory" -L "$benchmark_directory" -lCueCore \
    -module-cache-path "$benchmark_directory/module-cache" \
    -Xlinker -rpath -Xlinker "$benchmark_directory" \
    "$repo_root/scripts/benchmark-clipboard.swift" -o "$benchmark_directory/benchmark-clipboard"

"$benchmark_directory/benchmark-clipboard"
