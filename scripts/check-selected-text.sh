#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-selected-text.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
    -module-cache-path "$check_directory/module-cache" \
    "$repo_root/Sources/Cue/SelectedTextService.swift" \
    "$repo_root/scripts/check-selected-text.swift" \
    -o "$check_directory/check-selected-text"

"$check_directory/check-selected-text"
