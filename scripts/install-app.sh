#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_app="$repo_root/.build/Cue.app"
destination="$HOME/Applications/Cue.app"
build_app=1
check_only=0

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
Usage: ./scripts/install-app.sh [--destination /path/to/Cue.app] [--no-build] [--check]

Build an optimized Release app and install it in ~/Applications/Cue.app.
Requires Command Line Tools with Swift 6 or later; full Xcode is optional.
  --destination  Use another writable, permanent Cue.app path (no sudo).
  --no-build     Install the existing .build/Cue.app without rebuilding.
  --check        Check prerequisites and the destination without changing files.
Quit Cue normally before installation; the script never terminates it for you.
USAGE
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --destination)
            [[ $# -ge 2 && -n "$2" ]] || fail "--destination needs a path ending in /Cue.app."
            destination="$2"
            shift 2 ;;
        --no-build) build_app=0; shift ;;
        --check) check_only=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$(uname -s)" == Darwin ]] || fail "Cue requires macOS."
[[ "$destination" == /* && "$(basename "$destination")" == Cue.app ]] \
    || fail "Use an absolute destination ending in /Cue.app, for example \"$HOME/Applications/Cue.app\"."
[[ ! -L "$destination" ]] || fail "Refusing to replace an app symlink: $destination."
destination_parent="$(dirname "$destination")"
# Resolve an existing parent to catch alternate spellings of the build output.
if [[ -d "$destination_parent" ]]; then
    destination_parent="$(cd "$destination_parent" && pwd -P)"
    destination="$destination_parent/Cue.app"
fi
case "$destination" in
    "$repo_root/.build/"*) fail "Choose a permanent install location outside the repository's .build directory." ;;
esac
existing_parent="$destination_parent"
while [[ ! -e "$existing_parent" ]]; do existing_parent="$(dirname "$existing_parent")"; done
[[ -d "$existing_parent" && -w "$existing_parent" && -x "$existing_parent" ]] \
    || fail "The install location is not writable. Use the default ~/Applications/Cue.app instead."
if [[ -e "$destination" ]]; then
    [[ -d "$destination" && -f "$destination/Contents/Info.plist" ]] \
        || fail "The destination already exists and is not a Cue app bundle."
    existing_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$destination/Contents/Info.plist")"
    [[ "$existing_identifier" == com.yyhsiu.cue ]] \
        || fail "The destination belongs to another app; nothing was replaced."
fi

printf 'Build: %s\nInstall: %s\n' "$source_app" "$destination"
printf 'Your existing Cue settings and clipboard history will be preserved.\n'

if [[ "$build_app" -eq 1 ]]; then
    "$repo_root/scripts/build-app.sh" --check
else
    [[ -x "$source_app/Contents/MacOS/Cue" ]] || fail "No built app found. Run this script without --no-build first."
    /usr/bin/codesign --verify --deep --strict --all-architectures "$source_app"
fi

require_cue_quit() {
    local process_paths process_path
    process_paths="$(/bin/ps -axo comm=)" || fail "Cannot check whether Cue is running."
    while IFS= read -r process_path; do
        case "$process_path" in
            */Contents/MacOS/Cue)
                fail "Quit Cue from its menu, then retry. Cue must finish pending clipboard saves before installation." ;;
        esac
    done <<< "$process_paths"
}
require_cue_quit
[[ "$check_only" -eq 0 ]] || { printf 'Installation prerequisites are ready. No files changed.\n'; exit 0; }

if [[ "$build_app" -eq 1 ]]; then
    "$repo_root/scripts/build-app.sh" release
fi

[[ -x "$source_app/Contents/MacOS/Cue" ]] || fail "The build did not produce a Cue executable."
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$source_app/Contents/Info.plist")" == com.yyhsiu.cue ]] \
    || fail "The built app has an unexpected bundle identifier."
/usr/bin/codesign --verify --deep --strict --all-architectures "$source_app"

mkdir -p "$destination_parent" \
    || fail "Cannot create $destination_parent. Choose a writable destination; the default needs no administrator access."
destination_parent="$(cd "$destination_parent" && pwd -P)"
destination="$destination_parent/Cue.app"
case "$destination" in
    "$repo_root/.build/"*) fail "Choose a permanent install location outside the repository's .build directory." ;;
esac
[[ -w "$destination_parent" ]] || fail "The install location is not writable. Use the default ~/Applications/Cue.app instead."
temporary_directory="$(mktemp -d "$destination_parent/.cue-install.XXXXXX")"
staged_app="$temporary_directory/Cue.app"
previous_app="$temporary_directory/Previous Cue.app"
had_previous=0
installed_new=0
completed=0
cleanup() {
    local result=$?
    if [[ "$completed" -eq 0 && "$installed_new" -eq 1 ]]; then
        rm -rf "$destination"
    fi
    if [[ "$completed" -eq 0 && "$had_previous" -eq 1 ]]; then
        if ! mv "$previous_app" "$destination"; then
            printf 'Could not restore the previous app. It is safe at %s.\n' "$previous_app" >&2
            return "$result"
        fi
    fi
    rm -rf "$temporary_directory"
    return "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/ditto "$source_app" "$staged_app"
/usr/bin/codesign --verify --deep --strict --all-architectures "$staged_app"
# Recheck after the build/copy, before changing the installed app.
require_cue_quit
[[ ! -L "$destination" ]] || fail "The destination became a symlink. Nothing was replaced."
if [[ -e "$destination" ]]; then
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$destination/Contents/Info.plist")" == com.yyhsiu.cue ]] \
        || fail "The destination changed to another app. Nothing was replaced."
    mv "$destination" "$previous_app"
    had_previous=1
fi
mv "$staged_app" "$destination"
installed_new=1
/usr/bin/codesign --verify --deep --strict --all-architectures "$destination"
completed=1

printf '\nInstalled %s\n' "$destination"
printf 'Open it with: open %q\n' "$destination"
