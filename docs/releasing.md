# Releasing Cue

Cue uses universal, ad hoc-signed apps in DMGs. Sparkle verifies update archives
and the appcast with Cue's pinned Ed25519 key. This does not provide Developer
ID signing or Apple notarization. Source and downloads are public.

## Signing key

The Cue update key is stored in the maintainer's login Keychain under the
Sparkle account `com.yyhsiu.cue`. Only its public key belongs in
`Resources/Info.plist` (`SUPublicEDKey`). The release script requires an existing
key and verifies that its public half matches the bundle; it must never create
or replace a key automatically.

Maintain a protected offline/encrypted backup of this key or its Keychain.
Never commit, upload, log, or paste the private key. With Cue's current ad hoc
signing and pre-extraction verification, losing it prevents existing installs
from trusting future updates; recovering with a new key requires another
manual installation. Ordinary contributors can build and test Cue without
access to this signing key.

Feed verification fails closed without an expiration fallback
(`SUSignedFeedFailureExpirationInterval = 0`). Keep this and pre-extraction
archive verification enabled in production.

## Prepare and verify

1. Set `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `Resources/Info.plist`. Sparkle compares the monotonically increasing build
   number. Write **both English and Traditional Chinese** sections in
   `docs/releases/v<version>.md`, with equivalent changes and limitations.
   Update README and installation download links.
2. Run `./scripts/release.sh` with full Xcode. It tests, builds both
   architectures, preserves Sparkle's framework/helper signatures, signs the
   complete Cue bundle locally, creates the DMG, and signs/verifies the archive
   and appcast with the existing update key. Release notes are embedded in the
   signed feed. Tools and framework dependencies are pinned to Sparkle 2.10.0.
3. Inspect `.build/releases/<version>/`: `Cue-<version>-universal.dmg`,
   `appcast.xml`, and `SHA256SUMS.txt`. Do not edit the generated signed feed,
   notes, or DMG afterward. SHA-256 is a transfer check, not a publisher identity.
4. Test an older updater-enabled fixture through download, verification,
   installation and relaunch. Confirm preferences and the automatic-check
   opt-out survive. Check corrupted-download rejection, unavailable updates,
   and typing during background checks. Never weaken production signature or
   transport settings to make tests pass.
5. Test actual browser downloads on another Mac when available. Record tested
   machines accurately; compiling Intel and targeting macOS 14 does not prove
   runtime compatibility there. Version 0.1.0 needs one manual installation of
   0.1.1 because it has no updater.

The script refuses to overwrite an existing version directory. Inspect and
move aside failed/unpublished attempts before retrying; never silently replace
an already-published build with different bytes.

## Publish assets before the feed

Commit and push the reviewed source. Create and push an annotated version tag
on that commit. Publish the tested assets and bilingual notes; for 0.1.1:

```sh
git tag -a v0.1.1 -m "Cue 0.1.1 in-app updates"
git push origin main
git push origin v0.1.1
gh release create v0.1.1 \
  .build/releases/0.1.1/Cue-0.1.1-universal.dmg \
  .build/releases/0.1.1/appcast.xml \
  .build/releases/0.1.1/SHA256SUMS.txt \
  --repo hsiuhsiu/cue --verify-tag --prerelease --latest=false \
  --title "Cue 0.1.1 — Updates / App 內更新" \
  --notes-file docs/releases/v0.1.1.md
```

Download the assets into a fresh directory and run
`shasum -a 256 -c SHA256SUMS.txt`. Confirm the release tag and files are correct.
Only then copy the generated `appcast.xml` to the repository root, commit it
unchanged, and push `main`. This is the live feed at
`https://raw.githubusercontent.com/hsiuhsiu/cue/main/appcast.xml`. Publishing the
feed last prevents installed apps from seeing an update before its asset exists.
The appcast is an explicit update channel: only versions deliberately added to
it are offered in Cue, regardless of GitHub's prerelease/latest labels.

Verify the live feed's signature and perform a manual update check. GitHub's
raw-content cache may take a short time to refresh. Installation guidance must
use the system's app-specific first-launch approval flow; do not remove
quarantine or disable Gatekeeper.
