#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-update-policy.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
sparkle_directory=""
for candidate in \
    "$repo_root/.build/release-xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64" \
    "$repo_root/.build/local-xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64" \
    "$repo_root/.build/local-swiftpm/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64" \
    "$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"; do
    if [[ -d "$candidate/Sparkle.framework" ]]; then
        sparkle_directory="$candidate"
        break
    fi
done
if [[ -z "$sparkle_directory" ]]; then
    echo "Resolve the pinned Sparkle dependency before running update-policy checks." >&2
    exit 1
fi
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$repo_root"/Sources/CueCore/*.swift \
    -module-cache-path "$check_directory/module-cache" \
    -emit-module-path "$check_directory/CueCore.swiftmodule" \
    -o "$check_directory/libCueCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -I "$check_directory" -L "$check_directory" -lCueCore \
    -F "$sparkle_directory" -framework Sparkle \
    -module-cache-path "$check_directory/module-cache" \
    -Xlinker -rpath -Xlinker "$check_directory" \
    -Xlinker -rpath -Xlinker "$sparkle_directory" \
    "$repo_root/Sources/Cue/Localization.swift" \
    "$repo_root/Sources/Cue/NetworkPolicy.swift" \
    "$repo_root/Sources/Cue/NetworkAwareUserDriver.swift" \
    "$repo_root/Sources/Cue/UpdateController.swift" \
    "$repo_root/scripts/check-updates.swift" \
    -o "$check_directory/check-updates"
"$check_directory/check-updates"
