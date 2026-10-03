# Releasing Cue

Cue uses universal, ad hoc-signed apps in DMGs. Sparkle verifies update archives
and the appcast with Cue's pinned Ed25519 key. This does not provide Developer
ID signing or Apple notarization. Source and downloads are public.

Publish normal GitHub releases and mark the newest release as **Latest** by
default. Use GitHub's **Pre-release** option only when the user explicitly
requests a prerelease. Describe signing and platform-testing limitations in
the release notes and installation guide regardless of the release label.

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

## Network defaults

Keep `CueNetworkAccessAllowedByDefault` and `SUEnableAutomaticChecks` **false**
in `Resources/Info.plist`. SwiftPM (including missing bundle metadata), Xcode
Debug/Release, and ordinary local builds default to offline. `release.sh` enables
both values only in its temporary, final distribution copy before signing.
The checked-in plist and Xcode build output remain unchanged, so making a release
does not turn later source builds online. Explicit user choices are preferences
outside the bundle and are preserved by installation.

`scripts/check-build-network-policy.sh` validates the source defaults. The release
script also validates the built app before staging changes, then requires online
defaults in both the signed staged app and the mounted DMG. JavaScript in release
notes stays disabled in every build. The runtime gate and updater behavior are
covered by `scripts/check-network-policy.sh` and `scripts/check-updates.sh`, which
the release script runs with the other checks. See [network policy](network-policy.md).

原始碼的 `CueNetworkAccessAllowedByDefault` 與 `SUEnableAutomaticChecks` 維持
`false`；只有發布腳本在簽章前，將最終暫存的發行 App 改為 `true`。來源 plist 與
Xcode 建置產物不會被改成連網預設。封裝流程會檢查來源、原始建置產物、簽署後的
App 及 DMG 內的預設值，也會執行網路政策與更新器測試。使用者明確儲存的選擇
位於 App 外，安裝新版本仍會保留；完整說明見[網路政策](network-policy.md)。

## Prepare and verify

1. Set `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `Resources/Info.plist`. Sparkle compares the monotonically increasing build
   number; for example, 0.9.0 uses build 10 after 0.8.0's build 9. Never reset
   the build number when changing the displayed version. Write **both English and Traditional Chinese** sections in
   `docs/releases/v<version>.md`, with equivalent changes and limitations.
   Start with one `# Cue <version> — ...` title, then the language sections.
   The GitHub notes formatter separates this heading from the body so the
   release page displays the title only once. The release script validates
   this format before building or signing.
   Update README and installation download links. Finalize the notes before
   running the release script because they become part of the signed feed.
2. Run `./scripts/release.sh` with full Xcode. It tests, builds both
   architectures, preserves Sparkle's framework/helper signatures, signs the
   complete Cue bundle locally, creates the DMG, and signs/verifies the archive
   and appcast with the existing update key. Release notes are embedded in the
   signed feed. Tools and framework dependencies are pinned to Sparkle 2.10.0.
3. Inspect `.build/releases/<version>/`: `Cue-<version>-universal.dmg`,
   `appcast.xml`, and `SHA256SUMS.txt`. Do not edit the generated signed feed,
   notes, or DMG afterward. SHA-256 is a transfer check, not a publisher identity.
4. Run the optimized launcher, command-icon, adaptive-search, clipboard, settings,
   localization, web-search, GPT, app-alias, link-cleaner, emoji, calculator, unit-conversion, currency-rate, system-action, selected-text, conversion-lifecycle, network-policy,
   and updater checks. Clipboard checks must use synthetic data and private pasteboards.
   Run `scripts/check-unit-conversion.sh` and `scripts/check-currency-rates.sh`
   with their synthetic queries, injected transport and private cache/pasteboards.
   Verify that an offline startup or canceled request cannot show rates,
   expired data is not used as a current answer, and disabling network access
   removes even cached currency answers. In the Release interface, check unit
   and currency input, numeric-only copying, visible rate date/attribution and
   responsive typing during a rate refresh. Distinguish injected checks from a
   live provider request; record either honestly. The optional
   `scripts/check-currency-live.sh --live` makes one fixed USD-table request with
   an isolated policy and no disk cache; it is not part of the offline checks.
   Run `scripts/check-gpt.sh`, `scripts/check-gpt-settings.sh`, and
   `scripts/check-gpt-ui.sh` with injected transports and isolated credentials.
   Verify no API requests or Keychain reads while typing, offline startup,
   permission changes while awaiting a key, cancellation and stale-stream
   rejection. Test the native answer/settings pages in both languages.
   Never embed a real API key in source, tests, notes or release assets.
   Record live GPT testing separately from simulated checks; a missing
   maintainer API key does not turn mocked answers into a live validation.
   Run `scripts/check-login-item.sh` with its injected service; it must not change
   the operator's login items. For manual login testing, install Cue in a stable
   Applications location, check registration and state after reopening Settings,
   and distinguish those checks from an actual logout/login test.
   Sleep/Lock/Screen Off checks inject actions instead of changing the operator's session;
   report actual power/lock transitions as unverified unless deliberately tested. Check the
   Release interface for blank initial input, all nine numbered shortcuts,
   clipboard search and deletion, and feature-local settings.
5. Test an older updater-enabled fixture through download, verification,
   installation and relaunch. Confirm preferences and the automatic-check
   opt-out survive. Verify an explicit network choice survives both source and
   official installations; offline startup must not start Sparkle, and both
   manual and automatic checks must stay disabled. Turning access off should
   cancel active update work; turning it back on should restore the saved
   automatic-check preference. Check corrupted-download rejection, unavailable
   updates, and typing during background checks. Never weaken production signature or
   transport settings to make tests pass. If an end-to-end update or platform
   check is not completed, state that limitation in both release-note languages
   before signing; do not claim it passed based on packaging checks alone.
6. Test actual browser downloads on another Mac when available. Record tested
   machines accurately; compiling Intel and targeting macOS 14 does not prove
   runtime compatibility there. Version 0.1.0 needs one manual installation of
   the current release because it has no updater; installing 0.1.1
   first is unnecessary. Version 0.1.1 and later can use the in-app updater.

The script refuses to overwrite an existing version directory. Inspect and
move aside failed/unpublished attempts before retrying; never silently replace
an already-published build with different bytes.

## Publish assets before the feed

Commit and push the reviewed source. Create and push an annotated version tag
on that commit. Publish the tested assets and bilingual notes; for 0.9.0:

```sh
git tag -a v0.9.0 -m "Cue 0.9.0 GPT and app search"
git push origin main
git push origin v0.9.0
./scripts/github-release-notes.sh --body docs/releases/v0.9.0.md \
  > .build/github-release-v0.9.0.md
gh release create v0.9.0 \
  .build/releases/0.9.0/Cue-0.9.0-universal.dmg \
  .build/releases/0.9.0/appcast.xml \
  .build/releases/0.9.0/SHA256SUMS.txt \
  --repo hsiuhsiu/cue --verify-tag --latest \
  --title "$(./scripts/github-release-notes.sh --title docs/releases/v0.9.0.md)" \
  --notes-file .build/github-release-v0.9.0.md
```

Never upload the complete titled source file as GitHub's release body. Confirm
the published page shows one release title, followed by the language sections,
and retains both English and Traditional Chinese content. For presentation-only
corrections to an existing GitHub release, regenerate its body with the same
formatter and use `gh release edit --notes-file`. Leave the tagged source,
signed appcast, DMG, and checksums unchanged; the appcast's embedded notes retain
their own heading because they also appear outside GitHub.

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
