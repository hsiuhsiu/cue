# Cue

Cue is a small native macOS application launcher. It runs in the menu bar, opens with **Option+Space**, and searches installed applications using an in-memory index.

## Download and install

[Download Cue 0.1.1 for Mac](https://github.com/hsiuhsiu/cue/releases/download/v0.1.1/Cue-0.1.1-universal.dmg) · [Release notes and checksums](https://github.com/hsiuhsiu/cue/releases/tag/v0.1.1) · [正體中文安裝說明](docs/installation.md)

The repository and release downloads are public. **Version 0.1.0 users must install 0.1.1 manually once** to gain in-app updates.

Open the DMG, drag **Cue.app** into **Applications**, then open Cue from Applications. Cue appears in the menu bar and has no Dock icon. If replacing an existing copy, first choose **Quit Cue** from its menu; replacing the app preserves your settings.

The universal app contains Apple silicon (`arm64`) and Intel (`x86_64`) builds targeting **macOS 14 or later**. Runtime testing for this preview has been performed only on **macOS 26.6.2 on Apple silicon**; Intel and other macOS versions remain unverified.

The preview has an **ad-hoc signature**, without Developer ID signing or Apple notarization. macOS may block its first launch. If you trust this release, follow the [first-launch instructions](docs/installation.md#首次開啟) using System Settings. Building from source is optional; downloading and installing the app does not require Xcode or Terminal.

## Features

The prototype discovers applications under `/Applications`, `/System/Applications`, and `~/Applications`, including nested folders. Results show application names and icons. Ranking prefers exact, prefix, word-prefix, substring, then subsequence matches. The global shortcut uses the system hot-key API and does not require Accessibility permission.

## Build and run

Open `Cue.xcodeproj` in Xcode and run the **Cue** scheme, or use:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Cue.xcodeproj -scheme Cue -configuration Release \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
open .build/xcode/Build/Products/Release/Cue.app
```

Source builds require a Swift 6 toolchain. Xcode must have completed its first-run setup and license acceptance. The app is not sandboxed; the preview packaging process below uses ad-hoc signing.

Alternatively, use the local app build script:

```sh
./scripts/build-app.sh
open .build/Cue.app
```

The script defaults to an optimized **Release** build for daily use; pass `debug` for development. It uses `/Applications/Xcode.app` when available, otherwise the selected developer tools, and honors an explicit `DEVELOPER_DIR`. Full Xcode is required to build the app bundle with its embedded updater and run tests. Sparkle 2.10.0 is pinned in both dependency graphs.

## Updates

Use **Check for Updates…** from the menu bar or **Command+, → Updates**. Automatic checks are enabled by default, normally once every 24 hours, and can be disabled without losing manual checks. Scheduled updates only change the menu bar indicator and update entry; they do not take focus from typing. The user chooses whether to download and install, then uses **Install and Relaunch** to finish.

Sparkle verifies signed update archives and the signed HTTPS appcast against the public key embedded in Cue. Checks contact GitHub; no usage analytics or system profile is sent. Updates run independently of launcher input. Sparkle's license is included in the app bundle and in [Resources/Sparkle-LICENSE.txt](Resources/Sparkle-LICENSE.txt).

## Package a preview release

```sh
./scripts/release.sh
```

The local release script reads the version from `Resources/Info.plist`, builds a universal app, and writes `Cue-<version>-universal.dmg`, a signed `appcast.xml`, and `SHA256SUMS.txt` under `.build/releases/<version>/`. Publishing requires the maintainer's update-signing key in Keychain; ordinary source builds and tests do not. The script prepares files locally and never uploads them. Developer ID signing and notarization are not part of this pipeline. See [publishing a release](docs/releasing.md) for publication order and key management.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/check-settings.sh
```

The settings check exercises the actual `CueSettings` store: bounded change notifications, saving edits, and reloading preferences. It uses an isolated temporary preferences domain and leaves the app’s settings untouched.

Or run the **Cue** scheme's tests in Xcode / from the command line:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Cue.xcodeproj -scheme Cue -destination 'platform=macOS' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO test
```

`CueCore` holds discovery, search, and preference validation independently of presentation. `Sources/Cue` uses AppKit for the latency-sensitive launcher and SwiftUI for Settings. The launcher reuses native table rows, loads and decodes icons in the background, caches recent searches, and sets focus synchronously. Tests cover ranking, discovery, and preferences. Reproducible CPU measurements are in [search profiling](docs/performance-search.md) and [icon profiling](docs/performance-icons.md); these are not end-to-end comparisons with Raycast.

## Controls

| Control | Action |
| --- | --- |
| Option+Space (default, configurable) | Show or hide Cue |
| Command+, | Open Settings while Cue is active |
| Up / Down | Select a result |
| Enter | Launch the selected application or run the selected command |
| Escape | Dismiss Cue |
| Menu bar → Show Cue / Settings… / Quit Cue | Open the launcher, configure Cue, or exit |

Type `reindex`, `update index`, `refresh apps`, or `更新索引` to find **Update App Index**, then press Enter. Cue scans again in the background, keeps the launcher usable, and shows the updated application count when finished. You can install or remove applications and refresh without restarting Cue.

Press **Command+,** in Cue (or click the gear/menu-bar Settings item) to configure the global shortcut, maximum result count, pointer/main display placement, and dismissal on focus loss. Changes apply immediately and persist across restarts. If a new shortcut conflicts, Cue keeps the previous working shortcut.

Pressing Enter on an app dismisses Cue immediately; launch failures reopen the query with an error. The default placement follows the mouse pointer. The index is built at startup; use Update App Index after installing or removing applications. Show Cue remains available from the menu bar if another app occupies the saved shortcut.

To verify the interface manually, invoke Cue from another app, type `saf` or `term`, change selection with the arrow keys, and launch with Enter. Invoke Cue again to check that the query is empty, then test Escape, shortcut toggling, light/dark appearance, and placement on another display.
