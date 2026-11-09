#!/bin/bash
set -euo pipefail
umask 077

# Uses only synthetic executables, isolated configuration and a disposable
# keychain. Never launches Cue, changes TCC/trust, or reads personal identities.
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-local-signing-check.XXXXXX")"
keychain="$check_directory/Test.keychain-db"
cleanup() {
    /usr/bin/security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$check_directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
export CUE_LOCAL_SIGNING_CONFIG="$check_directory/Configuration With Spaces/local-signing.plist"
signing="$repo_root/scripts/local-signing.sh"
setup="$repo_root/scripts/setup-local-signing.sh"
checks=0
pass() { checks=$((checks + 1)); printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reject() {
    local label="$1"; shift
    if "$@" > "$check_directory/rejection.log" 2>&1; then fail "$label"; fi
    pass "$label"
}

"$signing" check
[[ ! -e "$CUE_LOCAL_SIGNING_CONFIG" ]] || fail 'Read-only check created configuration.'
pass 'No-configuration check is read-only.'
for version in 1 2; do
    app="$check_directory/Version $version/Cue.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    /usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleIdentifier -string com.yyhsiu.cue "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleExecutable -string Cue "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleVersion -string "$version" "$app/Contents/Info.plist"
    printf 'int main(void) { return %d; }\n' "$version" > "$check_directory/probe.c"
    /usr/bin/xcrun clang "$check_directory/probe.c" -o "$app/Contents/MacOS/Cue"
    printf 'Synthetic resource %d\n' "$version" > "$app/Contents/Resources/fixture.txt"
done
first="$check_directory/Version 1/Cue.app"
second="$check_directory/Version 2/Cue.app"
"$signing" sign "$first"
/usr/bin/ditto "$first" "$check_directory/Ad Hoc/Cue.app"
pass 'Unconfigured source builds still support ad-hoc signing.'

/usr/bin/openssl rand -base64 32 > "$check_directory/password"
/usr/bin/security create-keychain -p "$(cat "$check_directory/password")" "$keychain"
"$setup" --keychain "$keychain"
cp "$CUE_LOCAL_SIGNING_CONFIG" "$check_directory/original.plist"
"$setup" --keychain "$keychain"
cmp "$CUE_LOCAL_SIGNING_CONFIG" "$check_directory/original.plist"
pass 'Repeated setup reuses the same identity and configuration.'
[[ "$(/usr/bin/stat -f %Lp "$CUE_LOCAL_SIGNING_CONFIG")" == 600 ]] || fail 'Configuration permissions.'
pass 'Configuration has private file permissions.'
"$signing" sign "$first"
"$signing" sign "$second"
"$signing" check-update "$check_directory/Ad Hoc/Cue.app" "$first"
pass 'One-time migration from ad-hoc signing succeeds.'
"$signing" check-update "$first" "$second"
first_requirement="$(/usr/bin/codesign -d -r- "$first" 2>&1 | sed -n 's/^designated => //p')"
second_requirement="$(/usr/bin/codesign -d -r- "$second" 2>&1 | sed -n 's/^designated => //p')"
[[ -n "$first_requirement" && "$first_requirement" == "$second_requirement" ]] || fail 'Identity changed across builds.'
first_hash="$(/usr/bin/codesign -dv --verbose=4 "$first" 2>&1 | sed -n 's/^CDHash=//p')"
second_hash="$(/usr/bin/codesign -dv --verbose=4 "$second" 2>&1 | sed -n 's/^CDHash=//p')"
[[ -n "$first_hash" && -n "$second_hash" && "$first_hash" != "$second_hash" ]] || fail 'Fixtures need different executable hashes.'
pass 'Different executables/versions keep exactly the same certificate-bound identity.'

original_config="$CUE_LOCAL_SIGNING_CONFIG"
export CUE_LOCAL_SIGNING_CONFIG="$check_directory/Other Identity.plist"
"$setup" --keychain "$keychain"
/usr/bin/ditto "$second" "$check_directory/Other Identity/Cue.app"
"$signing" sign "$check_directory/Other Identity/Cue.app"
export CUE_LOCAL_SIGNING_CONFIG="$original_config"
reject 'Different certificate cannot impersonate the configured identity.' "$signing" verify "$check_directory/Other Identity/Cue.app"
reject 'Configured install rejects an old ad-hoc build.' "$signing" verify "$check_directory/Ad Hoc/Cue.app"

/usr/bin/ditto "$second" "$check_directory/Tampered/Cue.app"
printf 'changed\n' >> "$check_directory/Tampered/Cue.app/Contents/Resources/fixture.txt"
reject 'Resource tampering is detected.' "$signing" verify "$check_directory/Tampered/Cue.app"

fingerprint="$(/usr/bin/plutil -extract certificateSHA1 raw -o - "$original_config")"
/usr/bin/ditto "$second" "$check_directory/Weak Requirement/Cue.app"
/usr/bin/codesign --force --sign "$fingerprint" --keychain "$keychain" --timestamp=none \
    -r '=designated => identifier "com.yyhsiu.cue"' "$check_directory/Weak Requirement/Cue.app"
reject 'A certificate-signed app with an identity-only requirement is rejected.' "$signing" verify "$check_directory/Weak Requirement/Cue.app"

export CUE_LOCAL_SIGNING_CONFIG="$check_directory/Absent.plist"
reject 'Losing configuration cannot downgrade an installed fixed signature to ad-hoc.' "$signing" check-update "$first" "$check_directory/Ad Hoc/Cue.app"
reject 'Losing configuration cannot replace a fixed signature with another certificate.' "$signing" check-update "$first" "$check_directory/Other Identity/Cue.app"

export CUE_LOCAL_SIGNING_CONFIG="$original_config"
/usr/bin/plutil -replace certificateSHA1 -string 0000000000000000000000000000000000000000 "$original_config"
reject 'Missing configured key stops preflight.' "$signing" check
reject 'Missing configured key stops signing instead of falling back.' "$signing" sign "$second"
reject 'Repeated setup does not rotate a missing configured identity.' "$setup" --keychain "$keychain"
cp "$check_directory/original.plist" "$original_config"
/usr/bin/plutil -replace certificateSHA1 -string '$(touch should-never-execute)' "$original_config"
reject 'Malformed configuration is parsed as data, never executed.' "$signing" check
cp "$check_directory/original.plist" "$original_config"
chmod 666 "$original_config"
reject 'Configuration writable by other users is rejected.' "$signing" check
chmod 600 "$original_config"
ln -s "$original_config" "$check_directory/Symlink.plist"
export CUE_LOCAL_SIGNING_CONFIG="$check_directory/Symlink.plist"
reject 'Configuration symlinks are rejected.' "$signing" check
export CUE_LOCAL_SIGNING_CONFIG="$original_config"

/usr/bin/security delete-keychain "$keychain"
reject 'A missing keychain fails without creating a new identity.' "$signing" check
printf '\nPassed %d isolated local-signing checks. No app was launched or permission changed.\n' "$checks"
