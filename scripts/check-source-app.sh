#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
app="${1:-$repo_root/.build/Cue.app}"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $# -le 1 && -x "$app/Contents/MacOS/Cue" ]] || fail "Usage: $0 [/path/to/Cue.app]"
app="$(cd "$app" && pwd -P)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

/usr/bin/codesign --verify --deep --strict --all-architectures "$app"
"$repo_root/scripts/check-build-network-policy.sh" source "$app"
"$repo_root/scripts/check-version.sh" "$app"

# A relocated install must not depend on the checkout, Xcode or CLT libraries.
saw_sparkle=0
while IFS= read -r dependency; do
    case "$dependency" in
        @rpath/Sparkle.framework/Versions/B/Sparkle) saw_sparkle=1 ;;
        /System/Library/*|/usr/lib/*) ;;
        *) fail "Nonportable library dependency: $dependency" ;;
    esac
done < <(/usr/bin/otool -L "$app/Contents/MacOS/Cue" | sed '1d; s/^[[:space:]]*//; s/ (compatibility version.*//')
[[ "$saw_sparkle" -eq 1 ]] || fail "Cue is not linked to the bundled Sparkle."
saw_frameworks=0
while IFS= read -r runpath; do
    case "$runpath" in
        @executable_path/../Frameworks) saw_frameworks=1 ;;
        @loader_path|/usr/lib/*|/System/Library/*) ;;
        *) fail "Nonportable framework search path: $runpath" ;;
    esac
done < <(/usr/bin/otool -l "$app/Contents/MacOS/Cue" | awk '/cmd LC_RPATH/ {getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print}')
[[ "$saw_frameworks" -eq 1 ]] || fail "Cue cannot locate its embedded frameworks."

# No production app launch: validate an untouched relocated copy, then replace
# only that copy's executable with a probe that never starts NSApplication,
# reads preferences, touches the clipboard/Keychain, or starts the updater.
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-source-app.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
relocated="$check_directory/Location With Spaces/Cue.app"
/usr/bin/ditto "$app" "$relocated"
/usr/bin/codesign --verify --deep --strict --all-architectures "$relocated"
/usr/bin/xcrun swift "$repo_root/scripts/check-localizations.swift" "$relocated"

/usr/bin/plutil -replace CFBundleIdentifier -string com.yyhsiu.cue.tests.source-app "$relocated/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleExecutable -string CueProbe "$relocated/Contents/Info.plist"
/usr/bin/plutil -replace LSBackgroundOnly -bool true "$relocated/Contents/Info.plist"
/usr/bin/xcrun swiftc -swift-version 6 -O -parse-as-library \
    -module-cache-path "$check_directory/module-cache" \
    -F "$relocated/Contents/Frameworks" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$repo_root/Sources/CueCore/ChineseConversion.swift" \
    "$repo_root/scripts/check-source-app.swift" \
    -o "$relocated/Contents/MacOS/CueProbe"
# The production executable was validated above and is never executed here.
rm "$relocated/Contents/MacOS/Cue"
/usr/bin/codesign --force --sign - --timestamp=none "$relocated"
for language in en zh-Hant; do
    "$relocated/Contents/MacOS/CueProbe" -AppleLanguages "($language)"
done

printf 'Source app passed: relocatable dependencies, signed bundle, localized resources and offline dictionaries.\n'
