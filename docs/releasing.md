# Releasing Cue

Cue uses universal, ad hoc-signed apps in DMGs. Sparkle verifies update archives
and the appcast with Cue's pinned Ed25519 key. This does not provide Developer
ID signing or Apple notarization. Source and downloads are public.

Publish normal GitHub releases and mark the newest release as **Latest** by
default. Use GitHub's **Pre-release** option only when the user explicitly
requests a prerelease. Describe signing and platform-testing limitations in
the release notes and installation guide regardless of the release label.

Local source milestones use `-beta.N` or `-dev.N` labels; these
labels do not create public preview releases. Xcode **Release** means compiler
optimization, not a stable release channel. The normal packaging script requires
`CueBuildChannel=stable` and refuses beta/dev metadata before it builds or accesses
the signing key. See [versioning](versioning.md) for the complete rules and helper.

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

1. Synchronize the repository, then use `./scripts/set-version.sh <version> stable`
   to finalize the milestone in `Resources/Info.plist`. It automatically increments
   the internal build, sets the stable channel, and removes the prerelease field.
   Beta-to-stable also increments the build. Sparkle compares this
   build number, which must never reset or contain a beta suffix. Run
   `./scripts/check-version.sh --release`: both the numeric version and build must
   exceed every stable item in the local appcast. The script does not fetch remote
   state or rewrite published assets. Write **both English and Traditional Chinese** sections in
   `docs/releases/v<version>.md`, with equivalent changes and limitations.
   Start with one `# Cue <version> — ...` title, then the language sections.
   The GitHub notes formatter separates this heading from the body so the
   release page displays the title only once. The release script validates
   this format before building or signing.
   Update README and installation download links. Finalize the notes before
   running the release script because they become part of the signed feed.
   For releases introducing or changing window controls, include the default-on
   behavior, Option+M, the menu-bar Window Settings entry, and permission setup
   for both new installs and updates in both languages. Link the recovery guide
   for an enabled macOS switch that Cue still reports as untrusted. Existing
   explicit off choices stay off; a previously granted permission is not proof
   that the new executable is trusted.
2. Run `./scripts/release.sh` with full Xcode. It tests, builds both
   architectures, preserves Sparkle's framework/helper signatures, signs the
   complete Cue bundle locally, creates the DMG, and signs/verifies the archive
   and appcast with the existing update key. Release notes are embedded in the
   signed feed. Tools and framework dependencies are pinned to Sparkle 2.10.0.
3. Inspect `.build/releases/<version>/`: `Cue-<version>-universal.dmg`,
   `appcast.xml`, and `SHA256SUMS.txt`. Do not edit the generated signed feed,
   notes, or DMG afterward. SHA-256 is a transfer check, not a publisher identity.
4. Run the optimized launcher, command-icon, adaptive-search, clipboard, settings,
   localization, web-search, file-search, GPT, app-alias, link-cleaner, emoji, calculator, unit-conversion, currency-rate, system-action, selected-text, conversion-lifecycle, network-policy,
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
   Run `scripts/check-window-settings.sh` and `scripts/check-window-mode.sh`
   with injected permission state. Verify first use, valid existing permission,
   stale/revoked permission after updates, returning from System Settings,
   preserved explicit disablement, shortcut conflicts and no replay of old
   layout actions. These tests must not request or reset real system permission.
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
   runtime compatibility there. Use the app updater or the installation guide
   for manual replacement, and verify that existing preferences are preserved.

The script refuses to overwrite an existing version directory. Inspect and
move aside failed/unpublished attempts before retrying; never silently replace
an already-published build with different bytes.

版本資料請使用 `set-version.sh` 集中更新；從 beta 轉正式也會遞增 build，
避免 Sparkle 將兩者視為同一份 App。發佈前須同步 repo；`check-version.sh --release`
會以本機 appcast 驗證正式 channel 與遞增版本，不會連線、發布或更動舊產物。
`check-version-tests.sh` 使用隔離資料驗證版本轉換及回退拒絕。完整中英說明見
[版本規則](versioning.md)。

## Publish assets before the feed

Commit and push the reviewed source. Create and push an annotated version tag
on that commit. Publish the tested assets and bilingual notes, deriving the version
from the validated metadata:

```sh
./scripts/check-version.sh --release
cue_version="$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)"
cue_notes="docs/releases/v${cue_version}.md"
git tag -a "v${cue_version}" -m "Cue ${cue_version}"
git push origin main
git push origin "v${cue_version}"
./scripts/github-release-notes.sh --body "$cue_notes" \
  > ".build/github-release-v${cue_version}.md"
gh release create "v${cue_version}" \
  ".build/releases/${cue_version}/Cue-${cue_version}-universal.dmg" \
  ".build/releases/${cue_version}/appcast.xml" \
  ".build/releases/${cue_version}/SHA256SUMS.txt" \
  --repo hsiuhsiu/cue --verify-tag --latest \
  --title "$(./scripts/github-release-notes.sh --title "$cue_notes")" \
  --notes-file ".build/github-release-v${cue_version}.md"
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

## Website

The public website lives in `website/`, with English at `/cue/` and Traditional
Chinese at `/cue/zh-Hant/`. It is plain HTML/CSS with local artwork, no JavaScript,
analytics or external fonts. Preview it with
`python3 -m http.server 8765 --bind 127.0.0.1 --directory website`.

The account's existing Pages domain serves the site at
`https://yihsiu.org/cue/`; `https://hsiuhsiu.github.io/cue/` redirects there.
Keep HTTPS enforcement enabled for this repository and use the served domain
for canonical and language-alternate URLs.

`.github/workflows/pages.yml` publishes only `website/` to GitHub Pages when those
files change on `main`; it can also be dispatched manually. The repository's
Pages build source must be **GitHub Actions**. Never upload the repository root,
build products, logs or signing material as the Pages artifact.

The download buttons point to GitHub's latest release. Publish a new release
before adding its milestone link to the website. Update both language pages
together and check language switching, internal anchors, mobile layouts and
download links. Keep installation steps in the linked documentation, not on
the homepage.

官網來源位於 `website/`，英文與正體中文各有獨立頁面。GitHub Pages workflow
只發布這個目錄，不包含儲存庫根目錄、建置產物或簽章資料。下載按鈕連到最新
正式 release；新增沿革連結前先完成該版發布，兩語頁面同步更新。安裝步驟保留
在連結的文件裡，不放在首頁。
