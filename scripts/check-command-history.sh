#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-command-history.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
    -emit-module -emit-library -module-name CueCore \
    "$repo_root"/Sources/CueCore/*.swift \
    -module-cache-path "$check_directory/module-cache" \
    -emit-module-path "$check_directory/CueCore.swiftmodule" \
    -o "$check_directory/libCueCore.dylib"
app_directory="$check_directory/CommandHistoryChecks.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp -R "$repo_root/Sources/Cue/Resources/en.lproj" "$repo_root/Sources/Cue/Resources/zh-Hant.lproj" "$app_directory/Contents/Resources/"
cat > "$app_directory/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yyhsiu.cue.tests.history</string>
<key>CFBundleExecutable</key><string>CommandHistoryChecks</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -I "$check_directory" -L "$check_directory" -lCueCore \
    -module-cache-path "$check_directory/module-cache" \
    -Xlinker -rpath -Xlinker "$check_directory" \
    "$repo_root/Sources/Cue/AppIconCache.swift" \
    "$repo_root/Sources/Cue/CommandIcon.swift" \
    "$repo_root/Sources/Cue/Localization.swift" \
    "$repo_root/Sources/Cue/ViewState.swift" \
    "$repo_root/Sources/Cue/LauncherAppearance.swift" \
    "$repo_root/Sources/Cue/ResultShortcut.swift" \
    "$repo_root/Sources/Cue/CurrencyRatesController.swift" \
    "$repo_root/Sources/Cue/FileSearchService.swift" \
    "$repo_root/Sources/Cue/LauncherModel.swift" \
    "$repo_root/Sources/Cue/LauncherView.swift" \
    "$repo_root/Sources/Cue/ClipboardMonitor.swift" \
    "$repo_root/Sources/Cue/ClipboardModel.swift" \
    "$repo_root/Sources/Cue/ClipboardView.swift" \
    "$repo_root/Sources/Cue/HotKeyManager.swift" \
    "$repo_root/Sources/Cue/SystemActions.swift" \
    "$repo_root/Sources/Cue/SelectedTextService.swift" \
    "$repo_root/Sources/Cue/ChineseConversionEngine.swift" \
    "$repo_root/Sources/Cue/ChineseConversionSettings.swift" \
    "$repo_root/Sources/Cue/WebSearchSettings.swift" \
    "$repo_root/Sources/Cue/LinkCleaningService.swift" \
    "$repo_root/Sources/Cue/EmojiGlyphCache.swift" \
    "$repo_root/Sources/Cue/EmojiModel.swift" \
    "$repo_root/Sources/Cue/EmojiView.swift" \
    "$repo_root/Sources/Cue/CalculatorCopyService.swift" \
    "$repo_root/Sources/Cue/GPTKeychain.swift" \
    "$repo_root/Sources/Cue/GPTClient.swift" \
    "$repo_root/Sources/Cue/GPTSettings.swift" \
    "$repo_root/Sources/Cue/GPTModel.swift" \
    "$repo_root/Sources/Cue/GPTView.swift" \
    "$repo_root/Sources/Cue/CommandHistoryModel.swift" \
    "$repo_root/Sources/Cue/CommandHistoryView.swift" \
    "$repo_root/Sources/Cue/LauncherPanelController.swift" \
    "$repo_root/Sources/Cue/NetworkPolicy.swift" \
    "$repo_root/scripts/check-command-history.swift" \
    -o "$app_directory/Contents/MacOS/CommandHistoryChecks"

for language in en zh-Hant; do
    "$app_directory/Contents/MacOS/CommandHistoryChecks" -AppleLanguages "($language)"
done
