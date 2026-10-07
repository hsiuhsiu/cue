#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-settings-backup.XXXXXX")"
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
    echo "Resolve the pinned Sparkle dependency before running settings-backup checks." >&2
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
    "$repo_root/Sources/Cue/ViewState.swift" \
    "$repo_root/Sources/Cue/NetworkPolicy.swift" \
    "$repo_root/Sources/Cue/NetworkAwareUserDriver.swift" \
    "$repo_root/Sources/Cue/UpdateController.swift" \
    "$repo_root/Sources/Cue/LoginItemController.swift" \
    "$repo_root/Sources/Cue/CueSettings.swift" \
    "$repo_root/Sources/Cue/SettingsWindowController.swift" \
    "$repo_root/Sources/Cue/WindowControlSettings.swift" \
    "$repo_root/Sources/Cue/SelectedTextService.swift" \
    "$repo_root/Sources/Cue/ChineseConversionSettings.swift" \
    "$repo_root/Sources/Cue/AppAliasSettings.swift" \
    "$repo_root/Sources/Cue/WebSearchSettings.swift" \
    "$repo_root/Sources/Cue/GPTKeychain.swift" \
    "$repo_root/Sources/Cue/GPTSettings.swift" \
    "$repo_root/Sources/Cue/ClipboardMonitor.swift" \
    "$repo_root/Sources/Cue/ClipboardModel.swift" \
    "$repo_root/Sources/Cue/SettingsBackupModels.swift" \
    "$repo_root/Sources/Cue/SettingsBackupCoordinator.swift" \
    "$repo_root/scripts/check-settings-backup.swift" \
    -o "$check_directory/check-settings-backup"

"$check_directory/check-settings-backup"
