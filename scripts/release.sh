#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
step() { printf '\n%s\n' "$*"; }

[[ $# -eq 0 ]] || fail "Usage: $0 (version comes from Resources/Info.plist)"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

source_plist="$repo_root/Resources/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw -o - "$source_plist")"
build_number="$(plutil -extract CFBundleVersion raw -o - "$source_plist")"
minimum_os="$(plutil -extract LSMinimumSystemVersion raw -o - "$source_plist")"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || fail "Expected a numeric major.minor.patch version; found '$version'."
[[ "$build_number" =~ ^[0-9]+$ ]] || fail "CFBundleVersion must be an integer."
[[ "$minimum_os" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || fail "Invalid LSMinimumSystemVersion: '$minimum_os'."
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$source_plist")" == com.yyhsiu.cue ]] \
    || fail "Unexpected bundle identifier."

release_root="$repo_root/.build/releases"
output_directory="$release_root/$version"
[[ ! -e "$output_directory" && ! -L "$output_directory" ]] \
    || fail "Refusing to overwrite $output_directory."

step "Checking Xcode for Cue $version (build $build_number)..."
xcodebuild -version
xcodebuild -checkFirstLaunchStatus
native_arch="$(uname -m)"
case "$native_arch" in
    arm64|x86_64) ;;
    *) fail "Unsupported build host architecture: $native_arch" ;;
esac

mkdir -p "$release_root"
temporary_directory="$(mktemp -d "$release_root/.cue-release.XXXXXX")"
mount_directory="$temporary_directory/mount"
image_attached=0
created_output=0
published=0

cleanup() {
    local result=$?
    if [[ "$image_attached" -eq 1 ]]; then
        if hdiutil detach "$mount_directory" >/dev/null 2>&1; then
            image_attached=0
        else
            printf 'Could not detach %s; temporary files retained at %s.\n' \
                "$mount_directory" "$temporary_directory" >&2
        fi
    fi
    if [[ "$image_attached" -eq 0 ]]; then
        rm -rf "$temporary_directory"
    fi
    if [[ "$created_output" -eq 1 && "$published" -eq 0 ]]; then
        rm -rf "$output_directory"
    fi
    return "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

build_directory="$repo_root/.build/release-xcode"
step "Running optimized tests on $native_arch..."
xcodebuild -quiet -project Cue.xcodeproj -scheme Cue -configuration Release \
    -destination "platform=macOS,arch=$native_arch" -derivedDataPath "$build_directory" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES "ARCHS=$native_arch" test
"$repo_root/scripts/check-settings.sh"

step "Building the universal Release application..."
xcodebuild -quiet -project Cue.xcodeproj -scheme Cue -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$build_directory" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build

stage_directory="$temporary_directory/stage"
package_directory="$temporary_directory/package"
mkdir -p "$stage_directory" "$package_directory" "$mount_directory"
ditto "$build_directory/Build/Products/Release/Cue.app" "$stage_directory/Cue.app"
ln -s /Applications "$stage_directory/Applications"

step "Ad hoc signing the complete app bundle..."
codesign --force --sign - --timestamp=none "$stage_directory/Cue.app"

verify_app() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    local executable="$app/Contents/MacOS/Cue"
    local architectures architecture binary_minimum
    [[ -f "$executable" && -x "$executable" ]] || fail "Missing Cue executable in $app."
    [[ "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" == com.yyhsiu.cue ]] \
        || fail "Packaged bundle identifier does not match."
    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == "$version" ]] \
        || fail "Packaged version does not match."
    [[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == "$build_number" ]] \
        || fail "Packaged build number does not match."
    [[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$plist")" == "$minimum_os" ]] \
        || fail "Packaged minimum macOS version does not match."
    architectures="$(xcrun lipo -archs "$executable")"
    case "$architectures" in
        'arm64 x86_64'|'x86_64 arm64') ;;
        *) fail "Expected exactly arm64 and x86_64; found '$architectures'." ;;
    esac
    for architecture in arm64 x86_64; do
        binary_minimum="$(xcrun vtool -arch "$architecture" -show-build "$executable" \
            | awk '$1 == "minos" { print $2 }')"
        [[ "$binary_minimum" == "$minimum_os" ]] \
            || fail "$architecture minimum macOS is '$binary_minimum', expected '$minimum_os'."
    done
    codesign --verify --deep --strict --all-architectures --verbose=2 "$app"
}

verify_app "$stage_directory/Cue.app"
image_name="Cue-$version-universal.dmg"
image_path="$package_directory/$image_name"
step "Creating and verifying $image_name..."
hdiutil create -volname "Cue $version" -fs HFS+ -format UDZO \
    -srcfolder "$stage_directory" "$image_path"
hdiutil verify "$image_path"

# Set this before attaching so a partially successful attach is cleaned up too.
image_attached=1
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_directory" "$image_path"
[[ -d "$mount_directory/Cue.app" && ! -L "$mount_directory/Cue.app" ]] \
    || fail "The disk image is missing Cue.app."
[[ -L "$mount_directory/Applications" \
    && "$(readlink "$mount_directory/Applications")" == /Applications ]] \
    || fail "The disk image is missing the Applications shortcut."
shopt -s nullglob dotglob
image_contents=("$mount_directory"/*)
shopt -u nullglob dotglob
[[ ${#image_contents[@]} -eq 2 ]] || fail "Unexpected items in the disk image."
verify_app "$mount_directory/Cue.app"
hdiutil detach "$mount_directory"
image_attached=0

step "Writing and checking SHA-256 checksum..."
(
    cd "$package_directory"
    shasum -a 256 "$image_name" > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)

# mkdir also rejects a release directory created by another process during the build.
mkdir "$output_directory"
created_output=1
mv "$image_path" "$package_directory/SHA256SUMS.txt" "$output_directory/"
published=1
step "Release artifacts ready (ad hoc signed; not Apple-notarized):"
printf '%s\n' "$output_directory/$image_name" "$output_directory/SHA256SUMS.txt"
