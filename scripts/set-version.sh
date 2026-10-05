#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
Usage: ./scripts/set-version.sh [--plist /path/Info.plist] major.minor.patch stable
       ./scripts/set-version.sh [--plist /path/Info.plist] major.minor.patch beta|dev sequence

Set the visible version and increment the existing internal build by one.
The default target is Resources/Info.plist. Files are validated before atomic
replacement. This command does not build, install, commit, or publish anything.
USAGE
}
plist="$repo_root/Resources/Info.plist"
if [[ "${1:-}" == --plist ]]; then
    [[ $# -ge 3 && -n "$2" ]] || { usage >&2; exit 2; }
    plist="$2"; shift 2
fi
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }
version="$1"; channel="$2"; sequence="${3:-}"
[[ -f "$plist" && ! -L "$plist" ]] || fail "Use an existing regular Info.plist, not a symlink."
validator="$repo_root/scripts/check-version.sh"
"$validator" --compare "$version" "$version" >/dev/null
case "$channel" in
    stable) [[ $# -eq 2 ]] || fail "Stable versions do not take a prerelease sequence." ;;
    beta|dev)
        [[ $# -eq 3 && "$sequence" =~ ^[1-9][0-9]{0,9}$ && "$sequence" -le 2147483647 ]] \
            || fail "$channel requires a positive sequence no greater than 2147483647." ;;
    *) fail "Unknown channel '$channel'; use stable, beta, or dev." ;;
esac

# Serialize helper invocations and compare with a snapshot before replacing the
# source, so a concurrent editor cannot silently lose its changes either.
lock_directory="$plist.cue-version-lock"
mkdir "$lock_directory" 2>/dev/null || fail "Another version change is active: $lock_directory."
temporary_directory=
cleanup() {
    [[ -z "$temporary_directory" ]] || rm -rf "$temporary_directory"
    rmdir "$lock_directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
temporary_directory="$(mktemp -d "$(dirname "$plist")/.cue-version.XXXXXX")"
cp -p "$plist" "$temporary_directory/original.plist"
original="$temporary_directory/original.plist"
"$validator" "$original" >/dev/null
previous_version="$(plutil -extract CFBundleShortVersionString raw -o - "$original")"
previous_build="$(plutil -extract CFBundleVersion raw -o - "$original")"
previous_channel="$(plutil -extract CueBuildChannel raw -o - "$original")"
comparison="$("$validator" --compare "$version" "$previous_version")"
[[ "$comparison" != -1 ]] || fail "Cannot move backwards from $previous_version to $version."
if [[ "$comparison" == 0 ]]; then
    case "$previous_channel:$channel" in
        stable:*) fail "A stable version is final; choose a newer major.minor.patch version." ;;
        beta:dev) fail "Cannot move backwards from beta to dev for the same version." ;;
        beta:beta|dev:dev)
            previous_sequence="$(plutil -extract CuePrereleaseNumber raw -o - "$original")"
            [[ "$sequence" -gt "$previous_sequence" ]] || fail "The prerelease sequence must increase." ;;
    esac
fi
[[ "$previous_build" -lt 2147483647 ]] || fail "The internal build counter is exhausted."
build=$((previous_build + 1))

# All values/transitions are valid before editing even the staged plist. Work
# beside the target so the final rename is atomic on the same filesystem.
cp -p "$original" "$temporary_directory/Info.plist"
staged="$temporary_directory/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$staged"
plutil -replace CFBundleVersion -string "$build" "$staged"
plutil -replace CueBuildChannel -string "$channel" "$staged"
if [[ "$channel" == stable ]]; then
    if plutil -extract CuePrereleaseNumber raw -o - "$staged" >/dev/null 2>&1; then
        plutil -remove CuePrereleaseNumber "$staged"
    fi
else
    plutil -replace CuePrereleaseNumber -integer "$sequence" "$staged"
fi
"$validator" "$staged" >/dev/null
cmp -s "$plist" "$temporary_directory/original.plist" || fail "Info.plist changed during preparation; retry without concurrent edits."
[[ ! -L "$plist" ]] || fail "Info.plist became a symlink; nothing was replaced."
mv "$staged" "$plist"
printf 'Set Cue %s; internal build %s.\n' "$("$validator" --display "$plist")" "$build"
