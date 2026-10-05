#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
check="$repo_root/scripts/check-version.sh"
set_version="$repo_root/scripts/set-version.sh"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-version-tests.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
plist="$temporary_directory/Info.plist"
feed="$temporary_directory/appcast.xml"
checks=0
fail() { printf 'Version test failed: %s\n' "$*" >&2; exit 1; }
expect() {
    local description="$1"; shift
    "$@" >"$temporary_directory/output" 2>&1 || { cat "$temporary_directory/output" >&2; fail "$description"; }
    checks=$((checks + 1))
}
reject() {
    local description="$1"; shift
    if "$@" >"$temporary_directory/output" 2>&1; then fail "$description"; fi
    checks=$((checks + 1))
}
same() { [[ "$1" == "$2" ]] || fail "$3: '$1' != '$2'"; checks=$((checks + 1)); }
fixture() {
    cat >"$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>0.9.1</string>
<key>CFBundleVersion</key><string>11</string>
<key>CueBuildChannel</key><string>stable</string>
<key>CueNetworkAccessAllowedByDefault</key><false/>
</dict></plist>
PLIST
}
write_feed() {
    printf '%s\n' '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' "$@" '</channel></rss>' >"$feed"
}
item() {
    printf '<item><sparkle:shortVersionString>%s</sparkle:shortVersionString><sparkle:version>%s</sparkle:version>%s</item>' "$1" "$2" "${3:-}"
}
unchanged_after_reject() {
    cp "$plist" "$temporary_directory/before.plist"
    reject "$@"
    expect 'Rejected transition must preserve the original bytes' cmp -s "$plist" "$temporary_directory/before.plist"
}

fixture
expect 'A stable fixture validates' "$check" "$plist"
same "$("$check" --display "$plist")" 0.9.1 'Stable display omits internal build'
same "$("$check" --compare 0.9.9 0.10.0)" -1 'Numeric minor ordering'
same "$("$check" --compare 1.0.0 0.99.99)" 1 'Numeric major ordering'
same "$("$check" --compare 0.10.0 0.10.0)" 0 'Equal numeric versions'
for bad in 1.2 01.2.3 1.02.3 1.2.03 1.2.3-beta.1 1.2.2147483648 99999999999999999999.0.0; do
    unchanged_after_reject "Reject malformed version $bad" "$set_version" --plist "$plist" "$bad" beta 1
done
unchanged_after_reject 'Stable cannot become beta of the same version' "$set_version" --plist "$plist" 0.9.1 beta 1
unchanged_after_reject 'Stable cannot reuse the same visible version' "$set_version" --plist "$plist" 0.9.1 stable
unchanged_after_reject 'Older base version is rejected' "$set_version" --plist "$plist" 0.9.0 beta 1
unchanged_after_reject 'Stable cannot carry a sequence argument' "$set_version" --plist "$plist" 0.10.0 stable 1
for bad in 0 01 -1 1.5 2147483648; do
    unchanged_after_reject "Reject invalid sequence $bad" "$set_version" --plist "$plist" 0.10.0 beta "$bad"
done

expect 'Stable to next beta increments the build' "$set_version" --plist "$plist" 0.10.0 beta 1
same "$("$check" --display "$plist")" 0.10.0-beta.1 'Beta display'
same "$(plutil -extract CFBundleVersion raw -o - "$plist")" 12 'Beta internal build'
same "$(plutil -extract CueNetworkAccessAllowedByDefault raw -o - "$plist")" false 'Unrelated defaults preserved'
unchanged_after_reject 'Beta cannot return to dev' "$set_version" --plist "$plist" 0.10.0 dev 9
unchanged_after_reject 'Beta sequence cannot be repeated' "$set_version" --plist "$plist" 0.10.0 beta 1
write_feed "$(item 0.9.1 11)"
reject 'Beta must never be packaged into the stable feed' "$check" --release "$plist" "$feed"
expect 'Next beta sequence increments the build' "$set_version" --plist "$plist" 0.10.0 beta 2
same "$(plutil -extract CFBundleVersion raw -o - "$plist")" 13 'Second beta build'
expect 'Beta can become stable at the same base version' "$set_version" --plist "$plist" 0.10.0 stable
same "$("$check" --display "$plist")" 0.10.0 'Stable graduation display'
same "$(plutil -extract CFBundleVersion raw -o - "$plist")" 14 'Stable graduation gets a distinct build'
reject 'Stable graduation removes prerelease metadata' plutil -extract CuePrereleaseNumber raw -o - "$plist"
expect 'New stable version passes the published feed guard' "$check" --release "$plist" "$feed"
write_feed "$(item 0.10.0 11)"
reject 'Published marketing version cannot be reused' "$check" --release "$plist" "$feed"
write_feed "$(item 0.9.1 14)"
reject 'Published build cannot be reused' "$check" --release "$plist" "$feed"
write_feed "$(item 0.9.1 11)" "$(item 0.9.0 15)"
reject 'All stable items are checked regardless of order' "$check" --release "$plist" "$feed"
write_feed "$(item 0.9.1 11)" "$(item 9.0.0 100 '<sparkle:channel>beta</sparkle:channel>')"
expect 'An explicit beta channel is not a published stable version' "$check" --release "$plist" "$feed"
write_feed
reject 'An empty feed fails closed' "$check" --release "$plist" "$feed"
printf '%s\n' '<!DOCTYPE rss [<!ENTITY x "0.9.1">]><rss><channel/></rss>' >"$feed"
reject 'Entity-bearing feeds fail closed' "$check" --release "$plist" "$feed"

expect 'Next base may begin with a dev build' "$set_version" --plist "$plist" 0.11.0 dev 1
same "$("$check" --display "$plist")" 0.11.0-dev.1 'Dev display'
expect 'Dev can graduate to beta' "$set_version" --plist "$plist" 0.11.0 beta 1
mkdir -p "$temporary_directory/Cue.app/Contents"
cp "$plist" "$temporary_directory/Cue.app/Contents/Info.plist"
same "$("$check" --display "$temporary_directory/Cue.app")" 0.11.0-beta.1 'App-bundle input'
plutil -replace CuePrereleaseNumber -string 2 "$plist"
reject 'Sequence must have integer plist type' "$check" "$plist"
fixture
plutil -replace CFBundleVersion -integer 12 "$plist"
reject 'Build must have string plist type' "$check" "$plist"
fixture
plutil -replace CFBundleVersion -string 2147483647 "$plist"
unchanged_after_reject 'Build overflow does not alter the source' "$set_version" --plist "$plist" 0.10.0 beta 1
fixture
plutil -replace CuePrereleaseNumber -integer 1 "$plist"
reject 'Stable with stale sequence is invalid' "$check" "$plist"
fixture
plutil -remove CueBuildChannel "$plist"
reject 'Build scripts require an explicit channel' "$check" "$plist"
printf 'Passed %s isolated version workflow checks. No app was built, installed, or contacted.\n' "$checks"
