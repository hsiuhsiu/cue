#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-conversion-lifecycle.XXXXXX")"
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
    "$repo_root/scripts/check-conversion-lifecycle.swift" \
    -o "$check_directory/check-conversion-lifecycle"

mkdir -p "$check_directory/ConversionCheck.app/Contents/MacOS" "$check_directory/ConversionCheck.app/Contents/Resources"
cp "$check_directory/check-conversion-lifecycle" "$check_directory/ConversionCheck.app/Contents/MacOS/ConversionCheck"
cp "$repo_root/Sources/Cue/Resources/ChineseConversion.cuecc" "$check_directory/ConversionCheck.app/Contents/Resources/"
cat > "$check_directory/ConversionCheck.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.yyhsiu.cue.tests.conversion-lifecycle</string><key>CFBundleExecutable</key><string>ConversionCheck</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST

"$check_directory/ConversionCheck.app/Contents/MacOS/ConversionCheck"
