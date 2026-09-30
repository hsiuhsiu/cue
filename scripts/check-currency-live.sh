#!/bin/bash
set -euo pipefail
if [[ "${1:-}" != "--live" || "$#" -ne 1 ]]; then
    echo 'Usage: ./scripts/check-currency-live.sh --live'
    echo 'Optional: makes one live request to the fixed public USD rates endpoint, with isolated preferences and no disk cache.'
    exit 64
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-currency-live.XXXXXX")"
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
    "$repo_root/Sources/Cue/NetworkPolicy.swift" \
    "$repo_root/Sources/Cue/CurrencyRatesController.swift" \
    "$repo_root/scripts/check-currency-live.swift" \
    -o "$check_directory/check-currency-live"
"$check_directory/check-currency-live"
