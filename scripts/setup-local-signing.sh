#!/bin/bash
set -euo pipefail
umask 077

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
config="${CUE_LOCAL_SIGNING_CONFIG:-$HOME/Library/Application Support/Cue/Build/local-signing.plist}"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
Usage: ./scripts/setup-local-signing.sh [--keychain /absolute/path/to/keychain-db]

Create a fixed local code-signing identity once, then reuse it across source
updates. The private key stays in your user keychain; only its public fingerprint
and keychain path are saved outside the checkout. No Developer ID, Xcode, sudo,
certificate trust changes, or macOS security changes are required.
The first switch from ad-hoc signing still needs one Accessibility permission grant.
USAGE
}
keychain=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --keychain) [[ $# -ge 2 ]] || fail "--keychain needs a path."; keychain="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ "$(uname -s)" == Darwin ]] || fail "Local signing requires macOS."
[[ "$config" == /* && ! -L "$config" ]] || fail "Use an absolute, non-symlink signing configuration path."
if [[ -e "$config" ]]; then
    if [[ -n "$keychain" ]]; then
        [[ "$(/usr/bin/plutil -extract keychainPath raw -o - "$config")" == "$keychain" ]] \
            || fail "A different keychain is already configured. Existing identities are never replaced automatically."
    fi
    "$repo_root/scripts/local-signing.sh" check
    printf 'Already configured; the original identity has been preserved.\n'
    exit 0
fi
if [[ -z "$keychain" ]]; then
    keychain="$(/usr/bin/security default-keychain -d user | /usr/bin/sed -E 's/^[[:space:]]*"(.*)"$/\1/')"
fi
[[ "$keychain" == /* && -f "$keychain" ]] || fail "A user keychain is required. Unlock your login keychain, then retry."

printf 'Signing key destination: %s\nPublic configuration: %s\n' "$keychain" "$config"
config_directory="$(dirname "$config")"
mkdir -p "$config_directory"
lock_directory="$config.lock"
mkdir "$lock_directory" 2>/dev/null || fail "Another signing setup is active (or was interrupted): $lock_directory."
temporary_directory=
staged_config=
cleanup() {
    [[ -z "$temporary_directory" ]] || rm -rf "$temporary_directory"
    [[ -z "$staged_config" ]] || rm -f "$staged_config"
    rmdir "$lock_directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ ! -e "$config" && ! -L "$config" ]] || fail "Signing configuration appeared during setup; retry to use it."
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/cue-signing-setup.XXXXXX")"
certificate_name="Cue Local Signing $(/usr/bin/uuidgen)"
cat > "$temporary_directory/certificate.cnf" <<CFG
[req]
distinguished_name=subject
x509_extensions=extensions
prompt=no
[subject]
CN=$certificate_name
[extensions]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$temporary_directory/certificate.cnf" -keyout "$temporary_directory/key.pem" \
    -out "$temporary_directory/certificate.pem" >/dev/null 2>&1
/usr/bin/openssl rand -base64 32 > "$temporary_directory/wrapping-password"
/usr/bin/openssl pkcs12 -export -inkey "$temporary_directory/key.pem" \
    -in "$temporary_directory/certificate.pem" -out "$temporary_directory/identity.p12" \
    -passout "file:$temporary_directory/wrapping-password"
fingerprint="$(/usr/bin/openssl x509 -in "$temporary_directory/certificate.pem" -noout -fingerprint -sha1 | /usr/bin/sed 's/.*=//;s/://g')"
[[ "$fingerprint" =~ ^[A-F0-9]{40}$ ]] || fail "Could not calculate the signing certificate fingerprint."

# Publish the identity choice BEFORE import. An interrupted/failed import must
# leave a visible error on future builds, never silently create a new identity.
# Hard-link a fully written file for atomic, no-overwrite publication.
staged_config="$config_directory/.local-signing.$$.plist"
/usr/bin/plutil -create xml1 "$staged_config"
/usr/bin/plutil -insert version -integer 1 "$staged_config"
/usr/bin/plutil -insert certificateSHA1 -string "$fingerprint" "$staged_config"
/usr/bin/plutil -insert keychainPath -string "$keychain" "$staged_config"
if ! ln "$staged_config" "$config"; then
    rm -f "$staged_config"
    fail "Signing configuration changed during setup. Nothing was imported."
fi
rm "$staged_config"

# No -A (all applications), no trust-root installation, and no login password
# collection. The imported private key is non-extractable; only codesign is
# allowed by its initial access list. macOS can still request user approval.
if ! /usr/bin/security import "$temporary_directory/identity.p12" -k "$keychain" \
    -P "$(cat "$temporary_directory/wrapping-password")" -x -T /usr/bin/codesign; then
    fail "Signing-key import failed. The chosen identity remains recorded at $config so builds cannot change identities silently. Check Keychain Access before retrying; do not remove an identity that has signed your installed Cue."
fi
rm "$temporary_directory/key.pem" "$temporary_directory/identity.p12" "$temporary_directory/wrapping-password"
"$repo_root/scripts/local-signing.sh" check
printf '\nFixed local signing is ready. Run ./scripts/install-app.sh for this and future source updates.\n'
printf 'Keep this keychain identity. The first install needs one new Accessibility grant; later builds keep the same code identity.\n'
