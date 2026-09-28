#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-network-policy.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -module-cache-path "$check_directory/module-cache" \
    "$repo_root/Sources/Cue/NetworkPolicy.swift" \
    "$repo_root/scripts/check-network-policy.swift" -o "$check_directory/check-network-policy"
"$check_directory/check-network-policy"
