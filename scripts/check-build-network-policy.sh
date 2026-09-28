#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    printf 'Usage: %s [source [app-or-plist] | official app-or-plist]\n' "$0"
}

[[ $# -le 2 ]] || { usage >&2; exit 2; }
mode="${1:-source}"
case "$mode" in
    source) expected=false ;;
    official)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        expected=true
        ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
plist="${2:-$repo_root/Resources/Info.plist}"
[[ ! -d "$plist" ]] || plist="$plist/Contents/Info.plist"
[[ -f "$plist" ]] || fail "Missing app Info.plist: $plist."

# These are installation defaults, not user preferences. Both Xcode configurations
# use the offline source plist; only release packaging opts its staged app in.
for setting in CueNetworkAccessAllowedByDefault SUEnableAutomaticChecks; do
    actual="$(plutil -extract "$setting" raw -expect bool -o - "$plist")" \
        || fail "$setting must be an explicit Boolean in $plist."
    [[ "$actual" == "$expected" ]] \
        || fail "$mode builds require $setting=$expected; found $actual in $plist."
done
[[ "$(plutil -extract SUEnableJavaScript raw -expect bool -o - "$plist")" == false ]] \
    || fail "Release-note JavaScript must remain disabled in $plist."
printf 'Verified %s network defaults (%s): %s\n' "$mode" "$expected" "$plist"
