<p align="center">
  <img src="docs/branding/cue-icon.png" alt="Cue app icon" width="144" height="144">
</p>

<h1 align="center">Cue</h1>

<p align="center">Fast, simple, lightweight.</p>

Cue is a small native macOS launcher with searchable clipboard history, offline Chinese conversion, and system commands. It runs in the menu bar, opens with **Option+Space**, and searches installed applications using an in-memory index.

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/branding/menu-bar-dark.png">
    <img src="docs/branding/menu-bar-light.png" alt="Cue menu bar icon" width="20" height="20">
  </picture>
  Look for Cue in the macOS menu bar. A small dot on its icon means an update is available.
</p>

## Download and install

[Download Cue 0.5.0 for Mac](https://github.com/hsiuhsiu/cue/releases/download/v0.5.0/Cue-0.5.0-universal.dmg) · [Release notes and checksums](https://github.com/hsiuhsiu/cue/releases/tag/v0.5.0) · [正體中文安裝說明](docs/installation.md)

The repository and release downloads are public.

Open the DMG, drag **Cue.app** into **Applications**, then open Cue from Applications. Cue appears in the menu bar and has no Dock icon. If replacing an existing copy, first choose **Quit Cue** from its menu; replacing the app preserves your settings.

The universal app contains Apple silicon (`arm64`) and Intel (`x86_64`) builds targeting **macOS 14 or later**. Runtime testing for this release has been performed only on **macOS 27.0 on Apple silicon**, using Xcode 27; Intel and other macOS versions remain unverified.

The app has an **ad-hoc signature**, without Developer ID signing or Apple notarization. macOS may block its first launch. If you trust this release, follow the [first-launch instructions](docs/installation.md#首次開啟) using System Settings. Building from source is optional; downloading and installing the app does not require Xcode or Terminal.

## Features

The interface supports **English and Traditional Chinese (正體中文)**, including all settings, menus, search prompts, and Cue's status/error messages. It follows macOS by default. Choose **Settings → Language → App language** to use **Follow System**, **English**, or **正體中文**, then reopen Cue to apply the change. Cue keeps its name, and installed application names continue to follow macOS. Translations are cached outside the typing path.

The blue app icon appears in Finder and **About Cue**. The matching menu bar icon supports light and dark appearances and shows a small dot when an update is available. **Command+,** brings Settings to the front with keyboard focus, including when Settings was already open or minimized.

Cue discovers applications under `/Applications`, `/System/Applications`, and `~/Applications`, including nested folders. Results show application names and icons. Ranking prefers exact, prefix, word-prefix, substring, then subsequence matches. The global shortcut uses the system hot-key API and does not require Accessibility permission.

### Personalized search

Cue learns from applications and commands you successfully open through the launcher. Within the same matching category, it prefers the item you usually choose for that query, followed by usage frequency weighted toward recent use. Exact matches remain ahead of weaker matches. Merely typing, moving the selection, canceling, or a failed launch does not teach it anything. Clipboard contents and searches inside Clipboard History are excluded.

Learning stays on this Mac. Only successful queries, selected result identifiers, scores, and timestamps are saved in a small local file. Search uses a prepared in-memory snapshot; loading, score calculation, and saving happen in the background. An arriving update never moves the current rows while you are choosing a result. See [adaptive search behavior and performance](docs/performance-adaptive-search.md).

Cue 會記住你在啟動器中成功開啟的 App 與指令。同一符合程度內，優先考慮「這個關鍵字通常選哪個項目」，再參考使用頻率與近期使用情況；完全符合仍優先。單純打字、移動選取、取消或開啟失敗不會留下學習記錄，也不記錄剪貼簿內容或剪貼簿頁面的搜尋。資料只存本機，搜尋使用記憶體中的分數，背景更新不會讓正在選擇的列表突然跳動。

### Chinese conversion

Select text in an editable field, invoke Cue, type **`st`** for **Traditional Chinese with Taiwan vocabulary** or **`ts`** for **Simplified Chinese with mainland China vocabulary**, then press **Return**. Cue replaces the selection in the original app; use that app's **Command+Z** to undo.

Type **`chinese settings`** or **`簡繁設定`** to change these aliases. **Command+,** also opens this feature's settings while a conversion command is selected. Aliases take effect immediately and exact aliases rank first. Conversion runs fully offline, using bundled OpenCC dictionaries only when invoked; first use needs no download, and disabling network access preserves the same conversion behavior. macOS **Accessibility** permission is required for replacing another app's selection. See the [bilingual conversion guide](docs/chinese-conversion.md) for setup and supported fields.

在可編輯欄位選取文字後，叫出 Cue，輸入 **`st`** 轉為**正體中文（台灣用詞）**，或 **`ts`** 轉為**簡體中文（中國大陸用詞）**，按 **Return** 即可取代原本選取的文字；可在原 App 按 **Command+Z** 復原。輸入 **`簡繁設定`**，或在選到轉換指令時按 **Command+,**，即可自訂這兩個別名，儲存後立即生效。轉換完全離線，首次使用不需下載，關閉網路後仍使用相同詞庫與轉換規則；跨 App 取代需先允許 macOS「輔助使用」權限。

### Launch at login

Enable **Command+, → Startup → Launch at login** to start your installed Cue automatically after signing in to your Mac. This is off for a new installation; Cue does not register itself automatically. The setting reflects macOS's existing registration. If approval is needed, use **Open Login Items…** and allow Cue in System Settings. You can disable it from Cue or macOS at any time. Keep the app at the same installed location when updating.

在 **Command+, → 啟動 → 登入時啟動** 開啟此選項，即可在登入 Mac 後自動執行已安裝的 Cue。新安裝預設關閉，不會自動註冊；設定會反映 macOS 中既有的註冊狀態。若需要授權，按**開啟登入項目⋯**，再到系統設定允許 Cue。可隨時從 Cue 或 macOS 關閉；更新時請維持相同安裝位置。

### Compact launcher and numbered results

Cue opens with just an empty input field: no initial results, placeholder, footer, settings button, or Escape hint. Start typing to find apps or commands; **Command+,** still opens Settings. The window grows with the result count and shows at most nine results, with no scrollbars. Refine the query to find another match. The result limit is fixed at nine.

A blue tint, inspired by Cue's icon, carries through the window and selected rows in both light and dark appearances. Larger input text and app names make results easier to read, with balanced spacing around the input. Built-in commands use white icons with blue line drawings and generous internal spacing. Conversion icons point right toward the target character 繁 / 简. Icons are prepared once in the background and cached; typing only reuses them.

內建指令採白底、藍色線條與充足留白；簡繁互轉的箭頭由左向右指向「繁／简」目標字。圖示只在背景產生一次並快取，打字時直接重用。

Every result has a number. **Command+1–9 executes the corresponding result immediately**: it opens an app, runs a command, or copies a clipboard item. These shortcuts act on the current result list and do not require a second Return press.

### Sleep, Lock Screen, and Screen Off

Type **`sleep`** or **`睡眠`** to put the Mac to sleep, or **`lock`** / **`鎖定`** to lock its screen. Press **Return** or the displayed **Command+number** to execute immediately. Cue closes first; neither command logs you out or closes your apps. See [system commands](docs/system-actions.md) for implementation and testing limits.

輸入 **`sleep`／`睡眠`** 可讓 Mac 進入睡眠；輸入 **`lock`／`鎖定`** 可鎖定螢幕。按 **Return** 或顯示的 **Command+數字** 即可立即執行，Cue 會先關閉視窗。兩者都不會登出或關閉其他 App；實作與驗證限制見[系統指令說明](docs/system-actions.md)。

Type **`screen off` / `display off` / `關閉螢幕`** to turn off the display immediately while the Mac keeps running. Password requirements on wake follow your macOS Lock Screen settings; use **Lock Screen** when you specifically want to lock the Mac.

輸入 **`screen off`／`display off`／`關閉螢幕`**，立即讓螢幕休眠，Mac 仍繼續運作。喚醒時是否要求密碼，依 macOS「鎖定畫面」設定；若目的是鎖定電腦，請使用**鎖定螢幕**。

### Clipboard History

Type `clipboard` or `剪貼簿` in Cue, select **Clipboard History**, and press Enter. Recording is off initially; choose **Enable Clipboard History** to start saving new text and link copies on this Mac.

Saved history remains visible when its search field is empty. Each record shows its number and copied date and time, and the window adapts to the number of results. It shows the nine most recent matching records with no scrollbars; searching still covers all saved history, and this display limit does not delete older records. Search the history, select an item, and press **Return** to copy it, or use **Command+1–9** to copy a numbered result immediately. Then use **Command+V** in the destination app. Press **Delete/Backspace** to remove the selected item when the search field is empty; otherwise these keys edit the search text. The **Delete** button or **Command+Backspace** also removes a selected item from filtered results.

The page's gear or **Command+,** opens its own recording and retention settings. Retention defaults to **7 days**, with choices from **1 hour** to **No time limit**. History is stored as readable text on this Mac, up to **500 items or 4 MiB**. **Esc** returns from these settings to history, then from history to the launcher.

See the [Clipboard History guide / 剪貼簿記錄說明](docs/clipboard.md) for retention, storage limits, and privacy details, and the [clipboard search benchmark](docs/performance-clipboard.md) for reproducible performance measurements.

## Build and install from source

Prefer building your own app? Install full **Xcode with Swift 6 or later**, open it once to complete its license and setup (also after upgrading to Xcode 27), then quit any running Cue and run:

```sh
git clone https://github.com/hsiuhsiu/cue.git
cd cue
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

This builds an optimized **Release** app for your Mac and installs it permanently at **`~/Applications/Cue.app`**, without a paid developer account, signing key, or administrator access. Existing settings, clipboard history, and search learning are preserved. Full Xcode is required; Command Line Tools alone are insufficient. The first build downloads the pinned Sparkle 2.10.0 dependency. The workflow has been tested with Xcode 27. Installation keeps Cue on disk after reboot; **Launch at login** also starts it for you.

To update, quit Cue, run `git pull --ff-only` and `./scripts/install-app.sh` in this repository, then open the installed app again. Source builds default to network access and automatic update checks **off**. An explicit network choice saved in Settings is preserved across installs. You can enable network access to use the updater, but installing an update offered by Cue replaces your build with the published GitHub app.

也可以自行編譯，無須下載 DMG。先安裝內含 Swift 6 以上的完整 Xcode 並完成首次啟動與授權設定，再執行上方指令，即可建置 Release 版本並固定安裝至 **`~/Applications/Cue.app`**，不需付費開發者帳號或管理者權限。此流程已在 Xcode 27 測試；現有設定、剪貼簿記錄與搜尋學習資料會保留。首次建置需連線下載固定版本的 Sparkle；執行中的自行建置版預設關閉網路與自動檢查更新，設定中明確儲存的網路選擇則會保留。之後可用 `git pull --ff-only` 與安裝腳本更新；若自行允許網路並從 Cue 安裝更新，會換成 GitHub 發布的 App。

See the [English / 正體中文 source installation guide](docs/building.md) for updating, custom install locations, Xcode setup, build-only and Debug options. `./scripts/build-app.sh --check` checks prerequisites without building. You can also open `Cue.xcodeproj` and run the **Cue** scheme for development.

## Network access

Use **Settings → Network → Allow network access** to control Cue's network features. Source builds—including SwiftPM, Xcode Debug/Release, and the local build/install scripts—default to **off**; official release DMGs default to **on**. Missing build metadata means off. An explicit choice saved in Settings takes precedence and survives updates, reinstalls, and switching between source and published builds.

Turning network access off disables both manual and automatic update checks and downloads. The automatic-check toggle displays **off** and is disabled while offline, but Cue remembers its separate preference and can resume the chosen schedule when access is allowed again. Search, Clipboard History, system commands, and Chinese conversion remain fully available. See [network behavior and scope](docs/network-policy.md).

在**設定 → 網路 → 允許使用網路**管理 Cue 的網路功能。原始碼建置（包含 SwiftPM、Xcode Debug／Release 與本機建置／安裝腳本）預設**關閉**，正式下載的 DMG 預設**開啟**；缺少建置資料也視為關閉。在設定中明確儲存的選擇優先，更新、重新安裝或切換自行建置與下載版都會保留。

關閉網路會停用手動、自動檢查更新及下載。自動檢查開關會顯示**關閉**且無法操作，但原先的偏好仍會保留，重新允許網路後可依原設定恢復排程。搜尋、剪貼簿記錄、系統指令與簡繁轉換仍可完整使用；詳見[網路行為與適用範圍](docs/network-policy.md)。

## Updates

With network access allowed, use **Check for Updates…** from the menu bar or **Command+, → Updates**. Automatic checks are enabled by default for a fresh official DMG installation, normally once every 24 hours; source builds default to off. Existing automatic-check preferences are preserved. Turning off automatic checks leaves manual checks available while network access is allowed. Scheduled updates only change the menu bar indicator and update entry; they do not take focus from typing. The user chooses whether to download and install, then uses **Install and Relaunch** to finish.

Sparkle verifies signed update archives and the signed HTTPS appcast against the public key embedded in Cue. Checks contact GitHub; no usage analytics or system profile is sent. Updates run independently of launcher input. Sparkle's license is included in the app bundle and in [Resources/Sparkle-LICENSE.txt](Resources/Sparkle-LICENSE.txt).

## Package a release

```sh
./scripts/release.sh
```

The local release script reads the version from `Resources/Info.plist`, builds a universal app, and writes `Cue-<version>-universal.dmg`, a signed `appcast.xml`, and `SHA256SUMS.txt` under `.build/releases/<version>/`. It enables network and automatic-check defaults only in the final staged release app before signing, leaving source and ordinary build output offline by default. Publishing requires the maintainer's update-signing key in Keychain; ordinary source builds and tests do not. The script prepares files locally and never uploads them. Developer ID signing and notarization are not part of this pipeline. See [publishing a release](docs/releasing.md) for publication order and key management.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/check-settings.sh
./scripts/check-login-item.sh
./scripts/check-launcher-keyboard.sh
./scripts/check-command-icons.sh
./scripts/check-adaptive-search.sh
./scripts/check-clipboard.sh
./scripts/check-system-actions.sh
./scripts/check-selected-text.sh
./scripts/check-conversion-lifecycle.sh
./scripts/check-network-policy.sh
./scripts/check-build-network-policy.sh
./scripts/check-updates.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/check-localizations.swift .build/Cue.app
```

The settings check exercises the actual `CueSettings` store: bounded change notifications, saving edits, and reloading preferences. It uses an isolated temporary preferences domain and leaves the app’s settings untouched.

The login-item check uses an injected macOS service to verify enabling, disabling, approval-required states, errors, and refresh behavior without changing system login items.

The settings check also verifies per-app language overrides, relaunch persistence, restoring the system preference, and preserving existing shortcuts. The localization check compares all English/Traditional Chinese keys and format arguments, language fallback, and resources inside a built app. Omit the app path to check only source tables. Verify both languages in a Release build, including Settings layout, menu items, shortcut recording/canceling, Chinese command search, and Command-comma focus; restore **Follow System** after testing.

The optimized launcher keyboard check exercises the real AppKit view without an app-menu fallback, including Command-comma, modifiers, repeat events, and marked-text composition. It verifies shortcut routing, not application activation, and does not show windows or change user preferences.

The adaptive-search check covers successful and failed launches, command learning, stable visible rows during background updates, cache invalidation, and persistence across restarts using injected actions and isolated synthetic state. It never sleeps or locks the Mac or reads real usage history.

The system-actions check uses injected actions to verify Sleep, Lock Screen, and Screen Off through the real controller without changing the Mac's power or lock state. Native service details and manual verification limits are documented in [system commands](docs/system-actions.md).

The optimized clipboard check covers capture, filtering, persistence, retention, rapid query/copy/delete interactions, and feature-local keyboard settings. It uses synthetic text on private named pasteboards and isolated preferences; it never reads the system clipboard.

The selected-text check uses a synthetic accessibility driver and private pasteboards to verify selection validation, one-shot replacement, cancellation, acknowledgement, and clipboard restoration. Dictionary tests and the [OpenCC reference verifier](docs/chinese-conversion-data.md) check conversion separately; native app replacement still needs a manual test with Accessibility enabled.

The network-policy check uses isolated preferences to verify source/release defaults, missing or malformed metadata, saved choices, and immediate change notifications. The build-policy check verifies the source plist; use `source <app-or-plist>` or `official <app-or-plist>` to validate a built bundle's defaults. The updater check exercises offline startup, manual and scheduled checks, cancellation, and preference restoration with an injected update engine.

Verify Settings focus in a Release build: with another app active, invoke Cue, type a query, and press Command-comma. Settings must appear in front with an active title bar and keyboard focus, without another click. Repeat with Settings already open behind another app, after closing it, and after minimizing it. Switching away afterward must not pull focus back to Cue.

Or run the **Cue** scheme's tests in Xcode / from the command line:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Cue.xcodeproj -scheme Cue -destination 'platform=macOS' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO test
```

`CueCore` holds discovery, search, and preference validation independently of presentation. `Sources/Cue` uses AppKit for the latency-sensitive launcher and SwiftUI for Settings. The launcher reuses native table rows, loads and decodes icons in the background, caches recent searches, and sets focus synchronously. Tests cover ranking, discovery, and preferences. Reproducible CPU measurements are in [search profiling](docs/performance-search.md), [adaptive search profiling](docs/performance-adaptive-search.md), and [icon profiling](docs/performance-icons.md); these are not end-to-end comparisons with Raycast.

## Controls

| Control | Action |
| --- | --- |
| Option+Space (default, configurable) | Show or hide Cue |
| Command+, | Open Settings from Cue's launcher |
| Up / Down | Select a result |
| Enter | Launch the selected application or run the selected command |
| Command+1–9 | Immediately execute the numbered result; in Clipboard History, copy it and close Cue |
| Escape | Dismiss Cue |
| Menu bar → Show Cue / Settings… / Quit Cue | Open the launcher, configure Cue, or exit |

Type `reindex`, `update index`, `refresh apps`, or `更新索引` to find **Update App Index**, then press Enter. Cue scans again in the background, keeps the launcher usable, and shows the updated application count when finished. You can install or remove applications and refresh without restarting Cue.

Press **Command+,** in the launcher (or choose the menu-bar Settings item) to configure the global shortcut, pointer/main display placement, dismissal on focus loss, launch at login, language, network access, and update checks. Inside Clipboard History, its gear and **Command+,** open clipboard-specific settings instead. Preferences are saved immediately and persist across restarts; language changes take effect when Cue reopens. If a new shortcut conflicts, Cue keeps the previous working shortcut.

Pressing Enter on an app dismisses Cue immediately; launch failures reopen the query with an error. The default placement follows the mouse pointer. The index is built at startup; use Update App Index after installing or removing applications. Show Cue remains available from the menu bar if another app occupies the saved shortcut.

To verify the interface manually, invoke Cue from another app, type `saf` or `term`, change selection with the arrow keys, and launch with Enter. Invoke Cue again to check that the query is empty, then test Escape, shortcut toggling, light/dark appearance, and placement on another display.
