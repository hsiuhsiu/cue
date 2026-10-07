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
[[ "$(uname -s)" == Darwin ]] || fail "Cue requires macOS."
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

# Prefer standalone Command Line Tools; an explicit selection always wins.
# Do not change the user's global xcode-select setting or require Xcode setup.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

swift_version="$(/usr/bin/xcrun swift --version)" \
    || fail "Install Command Line Tools with 'xcode-select --install', finish installation, then retry. Full Xcode is not required. If DEVELOPER_DIR is set, check that it points to a working toolchain."
swift_major="$(printf '%s\n' "$swift_version" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -n 1)"
[[ "$swift_major" =~ ^[0-9]+$ && "$swift_major" -ge 6 ]] \
    || fail "Cue needs Swift 6 or later. Update Command Line Tools in System Settings > Software Update, then retry."
/usr/bin/xcrun --sdk macosx --show-sdk-path >/dev/null \
    || fail "The macOS SDK is unavailable. Install or update Command Line Tools, then retry."
printf '%s\n' "$swift_version"
[[ "$check_only" -eq 0 ]] || { printf 'Build prerequisites are ready.\n'; exit 0; }

app_directory="$repo_root/.build/Cue.app"
process_paths="$(/bin/ps -axo comm=)" \
    || fail "Cannot check whether the build output is running. Quit Cue and retry."
while IFS= read -r process_path; do
    [[ "$process_path" != "$app_directory/Contents/MacOS/Cue" ]] \
        || fail "Quit Cue from its menu before rebuilding $app_directory. This lets pending clipboard saves finish."
done <<< "$process_paths"

printf 'Building Cue %s (%s); output: %s\n' "$display_version" "$configuration" "$app_directory"

build_directory="$repo_root/.build/local-swiftpm"
# An installed app uses its main bundle's resources, just like the Xcode build.
# SwiftPM's generated Bundle.module lookup varies across build engines and can
# fall back to an absolute build path; do not rely on that path after installing.
build_arguments=(--scratch-path "$build_directory" --configuration "$configuration" --product Cue
    --jobs 2 -Xswiftc -DCUE_APP_BUNDLE -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
/usr/bin/xcrun swift build "${build_arguments[@]}"
# SwiftPM's output layout differs between toolchain versions/build engines.
products_directory="$(/usr/bin/xcrun swift build "${build_arguments[@]}" --show-bin-path)"
[[ -x "$products_directory/Cue" ]] || fail "SwiftPM did not produce a Cue executable."
[[ -d "$products_directory/Cue_Cue.bundle" ]] || fail "SwiftPM did not produce Cue's resource bundle."
sparkle_framework="$build_directory/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$sparkle_framework" ]] || fail "The pinned Sparkle framework is missing."

temporary_directory="$(mktemp -d "$repo_root/.build/.cue-app.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
staged_app="$temporary_directory/Cue.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$staged_app/Contents/Frameworks"
cp "$products_directory/Cue" "$staged_app/Contents/MacOS/Cue"
cp "$repo_root/Resources/Info.plist" "$staged_app/Contents/Info.plist"
printf 'APPL????' > "$staged_app/Contents/PkgInfo"
# Both older SwiftPM's flat bundle and Swift Build's Contents/Resources bundle
# contain the same processed resources. Copy those once into the final app.
package_resources="$products_directory/Cue_Cue.bundle"
if [[ -d "$package_resources/Contents/Resources" ]]; then
    package_resources="$package_resources/Contents/Resources"
fi
ditto "$package_resources" "$staged_app/Contents/Resources"
rm -f "$staged_app/Contents/Resources/Info.plist"
ditto "$sparkle_framework" "$staged_app/Contents/Frameworks/Sparkle.framework"
for resource in "${icon_resources[@]}" Sparkle-LICENSE.txt; do
    cp "$repo_root/Resources/$resource" "$staged_app/Contents/Resources/$resource"
done

# SwiftPM can embed checkout/toolchain search paths. Keep only system and
# relative paths so the app remains independent of the checkout and build tools.
while IFS= read -r runpath; do
    case "$runpath" in
        /usr/lib/*|/System/Library/*|@executable_path/*|@loader_path) ;;
        *) /usr/bin/install_name_tool -delete_rpath "$runpath" "$staged_app/Contents/MacOS/Cue" ;;
    esac
done < <(/usr/bin/otool -l "$staged_app/Contents/MacOS/Cue" | awk '/cmd LC_RPATH/ {getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print}')

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
diff --no-dereference -qr "$sparkle_framework" "$staged_app/Contents/Frameworks/Sparkle.framework"
codesign --verify --deep --strict --all-architectures \
    "$staged_app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none "$staged_app"
codesign --verify --deep --strict --all-architectures "$staged_app"

# Check again in case the old output was opened during the build.
process_paths="$(/bin/ps -axo comm=)" || fail "Cannot check whether the build output is running."
while IFS= read -r process_path; do
    [[ "$process_path" != "$app_directory/Contents/MacOS/Cue" ]] \
        || fail "Cue was opened during the build. Quit it and rerun this script to replace the output safely."
done <<< "$process_paths"
rm -rf "$app_directory"
mv "$staged_app" "$app_directory"
printf 'Built %s\n' "$app_directory"
