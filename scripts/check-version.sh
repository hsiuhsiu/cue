#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
Usage: ./scripts/check-version.sh [--display | --release] [app-or-plist] [appcast]
       ./scripts/check-version.sh --compare major.minor.patch major.minor.patch

Validate version metadata without changing files or contacting a server.
--display prints only the user-facing version. --release also requires a stable
version and build newer than every stable item in the local appcast.
USAGE
}

# Keep components inside the same explicit range as Cue's version formatter.
valid_integer() { [[ "$1" =~ ^[1-9][0-9]{0,9}$ && ${#1} -le 10 ]] && [[ "$1" -le 2147483647 ]]; }
valid_version() {
    [[ "$1" =~ ^(0|[1-9][0-9]{0,9})\.(0|[1-9][0-9]{0,9})\.(0|[1-9][0-9]{0,9})$ ]] || return 1
    local major minor patch
    IFS=. read -r major minor patch <<< "$1"
    [[ "$major" -le 2147483647 && "$minor" -le 2147483647 && "$patch" -le 2147483647 ]]
}
compare_versions() {
    local a b index
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for index in 0 1 2; do
        if [[ "${a[$index]}" -lt "${b[$index]}" ]]; then printf '%s\n' -1; return; fi
        if [[ "${a[$index]}" -gt "${b[$index]}" ]]; then printf '%s\n' 1; return; fi
    done
    printf '%s\n' 0
}

mode=validate
case "${1:-}" in
    --display) mode=display; shift ;;
    --release) mode=release; shift ;;
    --compare)
        [[ $# -eq 3 ]] || { usage >&2; exit 2; }
        valid_version "$2" && valid_version "$3" || fail "Expected numeric major.minor.patch versions."
        compare_versions "$2" "$3"
        exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --*) usage >&2; exit 2 ;;
esac
[[ $# -le 2 ]] || { usage >&2; exit 2; }
[[ $# -lt 2 || "$mode" == release ]] || fail "An appcast argument requires --release."
plist="${1:-$repo_root/Resources/Info.plist}"
[[ ! -d "$plist" ]] || plist="$plist/Contents/Info.plist"
[[ -f "$plist" ]] || fail "Missing app Info.plist: $plist."
version="$(plutil -extract CFBundleShortVersionString raw -expect string -o - "$plist")" \
    || fail "CFBundleShortVersionString must be a string."
build="$(plutil -extract CFBundleVersion raw -expect string -o - "$plist")" \
    || fail "CFBundleVersion must be a string."
channel="$(plutil -extract CueBuildChannel raw -expect string -o - "$plist")" \
    || fail "CueBuildChannel must explicitly be stable, beta, or dev."
valid_version "$version" || fail "CFBundleShortVersionString must be numeric major.minor.patch without leading zeroes."
valid_integer "$build" || fail "CFBundleVersion must be a positive integer no greater than 2147483647."
display="$version"
case "$channel" in
    stable)
        if plutil -extract CuePrereleaseNumber raw -o - "$plist" >/dev/null 2>&1; then
            fail "Stable versions must not include CuePrereleaseNumber."
        fi ;;
    beta|dev)
        sequence="$(plutil -extract CuePrereleaseNumber raw -expect integer -o - "$plist")" \
            || fail "$channel versions require an integer CuePrereleaseNumber."
        valid_integer "$sequence" || fail "CuePrereleaseNumber must be a positive integer no greater than 2147483647."
        display="$version-$channel.$sequence" ;;
    *) fail "Unknown CueBuildChannel '$channel'; use stable, beta, or dev." ;;
esac

if [[ "$mode" == release ]]; then
    [[ "$channel" == stable ]] || fail "Only stable builds may enter the public release feed; found $display."
    feed="${2:-$repo_root/appcast.xml}"
    [[ -f "$feed" ]] || fail "Missing local appcast: $feed."
    # Do not load a DTD or accept an entity-bearing feed, even in local fixtures.
    if LC_ALL=C /usr/bin/grep -Eiq '<![[:space:]]*(DOCTYPE|ENTITY)' "$feed"; then
        fail "The local appcast must not contain DTDs or entity declarations."
    fi
    xmllint --nonet --noout "$feed" || fail "The local appcast is not valid XML."
    stable_items='/rss/channel/item[not(*[local-name()="channel"]) or *[local-name()="channel"]="stable"]'
    count="$(xmllint --nonet --xpath "count($stable_items)" "$feed")"
    [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || fail "The local appcast contains no stable release to compare."
    for (( index=1; index<=count; index++ )); do
        item="($stable_items)[$index]"
        previous_version="$(xmllint --nonet --xpath "string($item/*[local-name()='shortVersionString'])" "$feed")"
        previous_build="$(xmllint --nonet --xpath "string($item/*[local-name()='version'])" "$feed")"
        valid_version "$previous_version" && valid_integer "$previous_build" \
            || fail "A stable appcast item has invalid version metadata."
        [[ "$(compare_versions "$version" "$previous_version")" == 1 ]] \
            || fail "Release $version must be newer than published $previous_version."
        [[ "$build" -gt "$previous_build" ]] \
            || fail "Build $build must be greater than published build $previous_build."
    done
fi

if [[ "$mode" == display ]]; then
    printf '%s\n' "$display"
else
    printf 'Verified version %s; internal build %s; channel %s.\n' "$display" "$build" "$channel"
fi
