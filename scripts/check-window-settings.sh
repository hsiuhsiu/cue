#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-window-settings.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
sparkle_directory=""
for candidate in \
    "$repo_root/.build/release-xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64" \
    "$repo_root/.build/local-xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64" \
    "$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"; do
    if [[ -d "$candidate/Sparkle.framework" ]]; then
        sparkle_directory="$candidate"
        break
    fi
done
if [[ -z "$sparkle_directory" ]]; then
    echo "Resolve the pinned Sparkle dependency before running window-settings checks." >&2
    exit 1
fi
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$repo_root"/Sources/CueCore/*.swift \
    -module-cache-path "$check_directory/module-cache" \
    -emit-module-path "$check_directory/CueCore.swiftmodule" \
    -o "$check_directory/libCueCore.dylib"
app_directory="$check_directory/WindowSettings.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp -R "$repo_root/Sources/Cue/Resources/en.lproj" "$repo_root/Sources/Cue/Resources/zh-Hant.lproj" \
    "$app_directory/Contents/Resources/"
cat > "$app_directory/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yyhsiu.cue.tests.window-settings</string>
<key>CFBundleExecutable</key><string>WindowSettings</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
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
    "$repo_root/Sources/Cue/LoginItemController.swift" \
    "$repo_root/Sources/Cue/CueSettings.swift" \
    "$repo_root/Sources/Cue/SettingsWindowController.swift" \
    "$repo_root/Sources/Cue/WindowControlSettings.swift" \
    "$repo_root/scripts/check-window-settings.swift" \
    -o "$app_directory/Contents/MacOS/WindowSettings"
preview_root="${CUE_WINDOW_SETTINGS_PREVIEW_DIRECTORY:-}"
for language in en zh-Hant; do
    if [[ -n "$preview_root" ]]; then
        export CUE_WINDOW_SETTINGS_PREVIEW_DIRECTORY="$preview_root/$language"
        mkdir -p "$CUE_WINDOW_SETTINGS_PREVIEW_DIRECTORY"
    fi
    "$app_directory/Contents/MacOS/WindowSettings" -AppleLanguages "($language)"
done
