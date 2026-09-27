#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

configuration="${1:-release}"
[[ $# -le 1 ]] || { echo "Usage: $0 [debug|release]" >&2; exit 2; }
case "$configuration" in
    debug) xcode_configuration=Debug ;;
    release) xcode_configuration=Release ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

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

build_directory="$repo_root/.build/local-xcode"
xcodebuild -quiet -project Cue.xcodeproj -scheme Cue -configuration "$xcode_configuration" \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$build_directory" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build

temporary_directory="$(mktemp -d "$repo_root/.build/.cue-app.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
staged_app="$temporary_directory/Cue.app"
ditto "$build_directory/Build/Products/$xcode_configuration/Cue.app" "$staged_app"
[[ "$(plutil -extract CFBundleIconFile raw -o - "$staged_app/Contents/Info.plist")" == AppIcon ]] \
    || { printf 'The built app is missing its AppIcon reference.\n' >&2; exit 1; }
for resource in "${icon_resources[@]}"; do
    [[ -s "$staged_app/Contents/Resources/$resource" ]] \
        || { printf 'Missing bundled icon: %s\n' "$resource" >&2; exit 1; }
done

# Keep Sparkle's signed framework and helpers intact; sign only our outer bundle.
sparkle_framework="$build_directory/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
diff --no-dereference -qr "$sparkle_framework" "$staged_app/Contents/Frameworks/Sparkle.framework"
codesign --verify --deep --strict --all-architectures \
    "$staged_app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none "$staged_app"
codesign --verify --deep --strict --all-architectures "$staged_app"

app_directory="$repo_root/.build/Cue.app"
rm -rf "$app_directory"
mv "$staged_app" "$app_directory"
printf 'Built %s\n' "$app_directory"
