#!/bin/bash
set -euo pipefail

# Build-time only. Never source this plist or put private signing material in it.
config="${CUE_LOCAL_SIGNING_CONFIG:-$HOME/Library/Application Support/Cue/Build/local-signing.plist}"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    printf 'Usage: %s check | sign APP | verify APP | check-update PREVIOUS_APP NEW_APP\n' "$0"
}
[[ "$(uname -s)" == Darwin ]] || fail "Local signing requires macOS."
[[ "$config" == /* ]] || fail "CUE_LOCAL_SIGNING_CONFIG must be an absolute path."
operation="${1:-}"
case "$operation:$#" in
    check:1|sign:2|verify:2|check-update:3) ;;
    -h:1|--help:1) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

fingerprint=
keychain=
requirement=
if [[ -e "$config" || -L "$config" ]]; then
    [[ -f "$config" && ! -L "$config" ]] || fail "Signing configuration must be a regular file: $config."
    [[ "$(/usr/bin/stat -f %u "$config")" == "$(/usr/bin/id -u)" ]] \
        || fail "Signing configuration must belong to the current user."
    config_mode="$(/usr/bin/stat -f %Lp "$config")"
    (( (8#$config_mode & 022) == 0 )) || fail "Signing configuration must not be writable by other users."
    [[ "$(/usr/bin/plutil -extract version raw -o - "$config")" == 1 ]] \
        || fail "Unsupported signing configuration: $config."
    fingerprint="$(/usr/bin/plutil -extract certificateSHA1 raw -o - "$config")"
    keychain="$(/usr/bin/plutil -extract keychainPath raw -o - "$config")"
    [[ "$fingerprint" =~ ^[A-F0-9]{40}$ ]] || fail "Invalid signing certificate fingerprint."
    [[ "$keychain" == /* && -f "$keychain" ]] \
        || fail "The configured signing keychain is missing. Restore it; Cue will not switch to ad-hoc signing."
    requirement="identifier \"com.yyhsiu.cue\" and certificate leaf = H\"$(printf '%s' "$fingerprint" | tr 'A-F' 'a-f')\""
fi

check_identity() {
    [[ -n "$fingerprint" ]] || return 0
    local identities matching
    # Self-signed certificates are deliberately NOT system trust anchors. Do not
    # use -v, which hides them, or change the user's certificate trust settings.
    identities="$(/usr/bin/security find-identity -p codesigning "$keychain")" \
        || fail "Cannot read the configured signing identity. Unlock its keychain and retry."
    matching="$(printf '%s\n' "$identities" | /usr/bin/awk -v hash="$fingerprint" '$2 == hash { print; exit }')"
    [[ -n "$matching" ]] \
        || fail "The configured certificate/private key is unavailable. Restore the original keychain identity; Cue will not create a replacement or fall back to ad-hoc signing."
    case "$matching" in
        *CSSMERR_TP_NOT_TRUSTED*) ;;
        *CSSMERR_*) fail "The configured signing certificate is not usable (for example, it may have expired). Restore a usable identity before building." ;;
    esac
}

check_app() {
    [[ -d "$1" && ! -L "$1" && -f "$1/Contents/Info.plist" ]] || fail "Not a regular app bundle: $1."
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist")" == com.yyhsiu.cue ]] \
        || fail "Local signing is restricted to Cue's bundle identifier."
}

designated_requirement() {
    local output
    output="$(/usr/bin/codesign -d -r- "$1" 2>&1)" || fail "Cannot read the app's signing requirement."
    printf '%s\n' "$output" | /usr/bin/sed -n 's/^designated => //p'
}

verify_app() {
    check_app "$1"
    /usr/bin/codesign --verify --deep --strict --all-architectures "$1"
    if [[ -n "$requirement" ]]; then
        /usr/bin/codesign --verify --strict --all-architectures -R "=$requirement" "$1" \
            || fail "This app does not use the configured local identity. Rebuild it before installing."
        [[ "$(designated_requirement "$1")" == "$requirement" ]] \
            || fail "The app's identity requirement differs from Cue's fixed certificate requirement. Rebuild it."
    fi
}

case "$operation" in
    check)
        check_identity
        if [[ -n "$fingerprint" ]]; then
            printf 'Fixed local signing identity is available.\n'
        else
            printf 'Using ad-hoc signing. For stable permissions across local updates, run ./scripts/setup-local-signing.sh once.\n'
        fi ;;
    sign)
        check_app "$2"
        check_identity
        if [[ -n "$fingerprint" ]]; then
            # Pin both identifier and certificate explicitly, independent of
            # changes to codesign's default requirement generation or trust.
            /usr/bin/codesign --force --sign "$fingerprint" --keychain "$keychain" \
                --requirements "=designated => $requirement" --timestamp=none "$2"
        else
            /usr/bin/codesign --force --sign - --timestamp=none "$2"
        fi
        verify_app "$2" ;;
    verify)
        verify_app "$2" ;;
    check-update)
        verify_app "$3"
        check_app "$2"
        /usr/bin/codesign --verify --deep --strict --all-architectures "$2"
        previous_signature="$(/usr/bin/codesign -dv "$2" 2>&1)"
        # Permit the one-time transition from an ad-hoc content-hash identity.
        # Once a certificate is in use, every source update must preserve it.
        if ! printf '%s\n' "$previous_signature" | /usr/bin/grep -qx 'Signature=adhoc'; then
            previous_requirement="$(designated_requirement "$2")"
            [[ -n "$previous_requirement" && "$(designated_requirement "$3")" == "$previous_requirement" ]] \
                || fail "The installed Cue uses a different signing identity. Nothing was replaced. Restore its local signing configuration/keychain and rebuild. Switching signing identities requires a deliberate manual installation and a new permission grant."
            /usr/bin/codesign --verify --strict --all-architectures -R "=$previous_requirement" "$3"
        fi ;;
esac
