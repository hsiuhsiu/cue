#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: %s [debug|release] [--check]\n' "$0"; }
configuration=release
check_only=0
for argument in "$@"; do
    case "$argument" in
        debug|release) configuration="$argument" ;;
        --check) check_only=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
case "$configuration" in
    debug) xcode_configuration=Debug ;;
    release) xcode_configuration=Release ;;
esac

[[ "$(uname -s)" == Darwin ]] || fail "Cue requires macOS and full Xcode."
"$repo_root/scripts/check-build-network-policy.sh"
"$repo_root/scripts/check-version.sh"
display_version="$("$repo_root/scripts/check-version.sh" --display)"
cmp "$repo_root/LICENSE" "$repo_root/Sources/Cue/Resources/Cue-LICENSE.txt" \
    || fail "The bundled Cue license must match LICENSE."

icon_resources=(
    AppIcon.icns MenuBarIconTemplate.png MenuBarIconTemplate@2x.png
    MenuBarIconUpdateTemplate.png MenuBarIconUpdateTemplate@2x.png
)
for resource in "${icon_resources[@]}"; do
    [[ -s "$repo_root/Resources/$resource" ]] \
        || { printf 'Missing icon resource: %s\n' "$resource" >&2; exit 1; }
done

# Prefer the installed Xcode toolchain; an explicit selection always wins.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! /usr/bin/xcodebuild -version; then
    fail "Install full Xcode, open it and complete setup. If Xcode is in another location, set DEVELOPER_DIR to its Contents/Developer directory. Command Line Tools alone cannot build Cue."
fi
if ! /usr/bin/xcodebuild -checkFirstLaunchStatus; then
    fail "Open Xcode and complete its license and first-launch setup, then run this command again. Repeat this after an Xcode upgrade if requested."
fi
swift_version="$(/usr/bin/xcrun swift --version)" \
    || fail "The selected Xcode Swift compiler is unavailable. Open Xcode and complete setup."
swift_major="$(printf '%s\n' "$swift_version" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -n 1)"
[[ "$swift_major" =~ ^[0-9]+$ && "$swift_major" -ge 6 ]] \
    || fail "Cue needs Swift 6 or later. Select a current full Xcode using DEVELOPER_DIR."
/usr/bin/xcrun --sdk macosx --show-sdk-path >/dev/null \
    || fail "The macOS SDK is unavailable. Open Xcode and complete setup."
[[ "$check_only" -eq 0 ]] || { printf 'Build prerequisites are ready.\n'; exit 0; }

app_directory="$repo_root/.build/Cue.app"
process_paths="$(/bin/ps -axo comm=)" \
    || fail "Cannot check whether the build output is running. Quit Cue and retry."
while IFS= read -r process_path; do
    [[ "$process_path" != "$app_directory/Contents/MacOS/Cue" ]] \
        || fail "Quit Cue from its menu before rebuilding $app_directory. This lets pending clipboard saves finish."
done <<< "$process_paths"

printf 'Building Cue %s with %s optimization; output: %s\n' "$display_version" "$xcode_configuration" "$app_directory"

build_directory="$repo_root/.build/local-xcode"
xcodebuild -quiet -project Cue.xcodeproj -scheme Cue -configuration "$xcode_configuration" \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$build_directory" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build

temporary_directory="$(mktemp -d "$repo_root/.build/.cue-app.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
staged_app="$temporary_directory/Cue.app"
ditto "$build_directory/Build/Products/$xcode_configuration/Cue.app" "$staged_app"
"$repo_root/scripts/check-build-network-policy.sh" source "$staged_app"
"$repo_root/scripts/check-version.sh" "$staged_app"
[[ "$("$repo_root/scripts/check-version.sh" --display "$staged_app")" == "$display_version" ]] \
    || fail "The built app version does not match the source version."
[[ "$(plutil -extract CFBundleVersion raw -o - "$staged_app/Contents/Info.plist")" \
    == "$(plutil -extract CFBundleVersion raw -o - "$repo_root/Resources/Info.plist")" ]] \
    || fail "The built app's internal build does not match the source."
[[ "$(plutil -extract CFBundleIconFile raw -o - "$staged_app/Contents/Info.plist")" == AppIcon ]] \
    || { printf 'The built app is missing its AppIcon reference.\n' >&2; exit 1; }
for resource in "${icon_resources[@]}"; do
    [[ -s "$staged_app/Contents/Resources/$resource" ]] \
        || { printf 'Missing bundled icon: %s\n' "$resource" >&2; exit 1; }
done

xcrun swift "$repo_root/scripts/check-localizations.swift" "$staged_app"
for resource in Cue-LICENSE.txt ChineseConversion.cuecc OpenCC-LICENSE.txt OpenCC-NOTICE.txt EmojiCatalog.json Unicode-LICENSE.txt Emoji-NOTICE.txt; do
    cmp "$repo_root/Sources/Cue/Resources/$resource" "$staged_app/Contents/Resources/$resource" \
        || fail "Missing or changed bundled resource: $resource."
done
# Keep Sparkle's signed framework and helpers intact; sign only our outer bundle.
sparkle_framework="$build_directory/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
diff --no-dereference -qr "$sparkle_framework" "$staged_app/Contents/Frameworks/Sparkle.framework"
codesign --verify --deep --strict --all-architectures \
    "$staged_app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none "$staged_app"
codesign --verify --deep --strict --all-architectures "$staged_app"

# Check again in case the old output was opened while Xcode was building.
process_paths="$(/bin/ps -axo comm=)" || fail "Cannot check whether the build output is running."
while IFS= read -r process_path; do
    [[ "$process_path" != "$app_directory/Contents/MacOS/Cue" ]] \
        || fail "Cue was opened during the build. Quit it and rerun this script to replace the output safely."
done <<< "$process_paths"
rm -rf "$app_directory"
mv "$staged_app" "$app_directory"
printf 'Built %s\n' "$app_directory"
