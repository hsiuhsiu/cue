#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-backup-ui.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swiftc -swift-version 6 -O -parse-as-library -emit-module -emit-library -module-name CueCore \
    "$repo_root"/Sources/CueCore/*.swift -module-cache-path "$check_directory/module-cache" \
    -emit-module-path "$check_directory/CueCore.swiftmodule" -o "$check_directory/libCueCore.dylib"
app_directory="$check_directory/BackupUI.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp -R "$repo_root/Sources/Cue/Resources/en.lproj" "$repo_root/Sources/Cue/Resources/zh-Hant.lproj" "$app_directory/Contents/Resources/"
cat > "$app_directory/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yyhsiu.cue.tests.backup-ui</string>
<key>CFBundleExecutable</key><string>BackupUI</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -O -parse-as-library -I "$check_directory" -L "$check_directory" -lCueCore \
    -module-cache-path "$check_directory/module-cache" -Xlinker -rpath -Xlinker "$check_directory" \
    "$repo_root/Sources/Cue/Localization.swift" "$repo_root/Sources/Cue/SettingsBackupModels.swift" \
    "$repo_root/Sources/Cue/BackupSettingsController.swift" "$repo_root/scripts/check-backup-ui.swift" \
    -o "$app_directory/Contents/MacOS/BackupUI"
preview_root="${CUE_BACKUP_PREVIEW_DIRECTORY:-}"
for language in en zh-Hant; do
    if [[ -n "$preview_root" ]]; then
        export CUE_BACKUP_PREVIEW_DIRECTORY="$preview_root/$language"
        mkdir -p "$CUE_BACKUP_PREVIEW_DIRECTORY"
    fi
    "$app_directory/Contents/MacOS/BackupUI" -AppleLanguages "($language)"
done
