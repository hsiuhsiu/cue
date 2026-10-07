# Build and install from source / 從原始碼建置與安裝

## English

You can build Cue directly from GitHub without downloading a DMG. You need a Mac running macOS 14 or later, **Command Line Tools with Swift 6 or later**, and an internet connection for the first build to fetch the pinned Sparkle dependency. Full Xcode is optional. No paid Apple Developer account, signing certificate, or maintainer update-signing key is required.

### First installation

1. Run `xcode-select --install` in Terminal if Command Line Tools are not installed, and finish the macOS installer before continuing. If the script reports an older Swift compiler, update Command Line Tools in **System Settings → Software Update**. You do not need to install or open Xcode.
2. Quit any running Cue through its menu bar **Quit Cue** command.
3. Run these commands in Terminal:

```sh
git clone https://github.com/hsiuhsiu/cue.git
cd cue
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

The installer uses Swift Package Manager to make an optimized **Release** build for your Mac's architecture, checks the complete app signature, and installs it at **`~/Applications/Cue.app`**. It packages the icons, translations, offline dictionaries, emoji catalog, and updater into the app. It uses local ad-hoc signing and preserves Sparkle's own signed helpers. It does not ask for a signing key or change macOS security settings. The default location requires no administrator access.

The CLT-only build and relocated-bundle checks have been verified with Command Line Tools 27 / Swift 6.4 on Apple silicon running macOS 27. Intel and older toolchains have not been revalidated for this installer change.

Cue lives in the menu bar, with no Dock icon. Press **Option+Space** to open it. The installed app remains available after reboot and is independent of the repository and `.build` folder; you can open it from your home folder's Applications directory. To start it automatically, turn on **Settings → General & Interaction → Launch at login**. If macOS requires approval, use **Open Login Items…** and allow Cue in System Settings. You can turn this off in Cue or macOS at any time.

The installer refuses to replace a running Cue; quit normally so pending clipboard saves finish. It verifies a staged copy before replacing the app and keeps the previous app until installation succeeds, restoring it if verification fails. Existing settings and clipboard history are outside the app bundle and are not modified by installation.

### Network defaults

Source builds default to **network access off** and **automatic update checks off**, including SwiftPM, Xcode Debug/Release, and the build/install scripts. Missing build metadata also means off. Official release DMGs default to on. An explicit choice made in **Settings → Network & Updates → Allow Cue to access the network** is saved locally and overrides either build default, including after replacement or reinstallation.

When network access is off, manual checks, automatic checks, and update downloads are disabled. The automatic-check toggle displays off and is disabled, while its separate preference is remembered for when access is allowed again. Chinese conversion, including regional vocabulary, remains fully offline with the same bundled dictionaries; there is no first-use download. Cloning and the first build's Sparkle fetch are developer-tool network operations, separate from the running app's setting. See [network behavior and scope](network-policy.md).

### Updating your own build

Quit Cue, then run this from the same repository:

```sh
git pull --ff-only
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

Use the same install path on each update so the login item continues to refer to the installed app. Its status comes from macOS; if approval is requested after an update, follow the message in Cue's Settings. If you have edited source files, resolve any Git conflicts before building.

Source builds include the GitHub updater but leave networking off by default. Use the commands above to keep running your own builds. If you explicitly allow network access, you can check manually and choose whether to enable automatic checks. An update offered by Cue installs the published GitHub binary, which replaces local code changes; it does not pull or compile your repository. Cue never installs an update without your action.

Rebuilding or updating an ad-hoc signed app can invalidate its previous Accessibility permission. If Chinese conversion still requests permission while Cue's switch is enabled, [remove its old permission entry and add the currently installed copy](chinese-conversion.md#permission-still-unavailable-after-rebuilding-or-updating).

### Other build options

```sh
# Check Command Line Tools/Swift setup without building or changing any files.
./scripts/build-app.sh --check

# Build only; output stays in the repository at .build/Cue.app.
./scripts/build-app.sh

# Install an existing build without rebuilding.
./scripts/install-app.sh --no-build

# Use another permanent location, if it is writable by your account.
./scripts/install-app.sh --destination /Applications/Cue.app

# Make a Debug build for development.
./scripts/build-app.sh debug
```

`./scripts/install-app.sh --check` also checks the install destination and that Cue has quit, without changing files. A destination containing spaces is supported when quoted. Keep one daily-use copy of Cue and launch that installed copy; running `.build/Cue.app` or a copy from Xcode is a separate development session.

The scripts prefer `/Library/Developer/CommandLineTools` when installed and honor an explicit `DEVELOPER_DIR`, without changing your global `xcode-select` setting. To select the standalone tools explicitly, use `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/install-app.sh`. If only Xcode is installed, the selected Xcode toolchain also works. Installing Xcode for source installation is unnecessary; the script handles compilation, resources, framework embedding, and signing for you.

For development or the maintainer's universal DMG pipeline, Xcode remains available: open `Cue.xcodeproj` and run the **Cue** scheme. The local installer builds only the current Mac's architecture, not a universal DMG.

## 正體中文

不下載 DMG 也能直接從 GitHub 建置 Cue。需要 macOS 14 以上的 Mac，以及含 **Swift 6 以上的 Command Line Tools**；不必安裝完整 Xcode。首次建置也需要網路以下載固定版本的 Sparkle 相依套件。**不需要付費 Apple Developer 帳號、簽章憑證或維護者的更新簽章金鑰**。

### 第一次安裝

1. 若尚未安裝 Command Line Tools，在「終端機」執行 `xcode-select --install`，等 macOS 安裝完成後再繼續。若腳本顯示 Swift 版本太舊，到**系統設定 → 軟體更新**更新 Command Line Tools 即可，不需要安裝或開啟 Xcode。
2. 若 Cue 正在執行，先從選單列選擇**結束 Cue**。
3. 在「終端機」執行：

```sh
git clone https://github.com/hsiuhsiu/cue.git
cd cue
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

安裝程式會使用 Swift Package Manager，依這台 Mac 的架構產生最佳化的 **Release** 版本，檢查完整 App 簽章，並安裝至 **`~/Applications/Cue.app`**。圖示、翻譯、離線詞庫、emoji 資料與更新元件都會包進 App。它使用本機 ad-hoc 簽章，保留 Sparkle 自己的簽章，不會要求簽章金鑰，也不會變更 macOS 安全設定。預設安裝位置不需要管理者權限。

只使用 Command Line Tools 的建置與搬移後的 App 檢查，已在 macOS 27、Apple silicon、Command Line Tools 27／Swift 6.4 通過；本次安裝流程修改尚未重新驗證 Intel 與較舊工具鏈。

Cue 會出現在選單列，不會有 Dock 圖示；按 **Option+Space** 即可叫出。安裝後的 App 獨立於儲存庫與 `.build` 目錄，重開機後仍會留在使用者個人資料夾內的「Applications／應用程式」。若希望登入 Mac 後自動執行，開啟 **設定 → 一般與操作 → 登入時啟動**。macOS 若要求授權，按**開啟登入項目⋯**，再到系統設定允許 Cue；之後可隨時從 Cue 或 macOS 關閉。

安裝程式不會取代仍在執行的 Cue；請正常結束，讓尚未完成的剪貼簿儲存作業結束。它會先驗證暫存的新 App，再取代原版本；完成前保留舊 App，若驗證失敗會還原。設定與剪貼簿記錄位於 App 外，安裝過程不會修改這些資料。

### 網路預設值

原始碼建置預設**關閉網路存取**與**自動檢查更新**，包含 SwiftPM、Xcode Debug／Release 及建置／安裝腳本；缺少建置資料也視為關閉。正式發布的 DMG 預設開啟。在**設定 → 網路與更新 → 允許 Cue 自行連網**明確選擇後，會儲存在本機並優先於版本預設值，替換 App 或重新安裝也會保留。

關閉網路時，手動檢查、自動檢查及更新下載都會停用。自動檢查開關顯示關閉且無法操作，但會記住原本偏好，重新允許網路後可恢復。簡繁轉換與地區用詞規則維持完整離線功能，使用相同內附詞庫，首次使用不需下載。取得儲存庫與首次建置下載 Sparkle 屬於開發工具的連線，與執行中 App 的設定分開。詳見[網路行為與適用範圍](network-policy.md)。

### 更新自己建置的版本

先結束 Cue，再於原本的儲存庫目錄執行：

```sh
git pull --ff-only
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

每次使用相同安裝位置，讓登入項目持續指向已安裝的 App。登入狀態由 macOS 管理；若更新後需要重新允許，請依 Cue 設定中的提示操作。如果你修改過原始碼，請先處理 Git 提示的衝突，再建置。

自行建置的版本包含 GitHub 更新功能，但預設關閉網路；若只想使用自己的版本，請用上方指令更新。若明確允許網路，可手動檢查，也可自行選擇開啟自動檢查。從 Cue 內安裝更新會換成 GitHub 上已發布的 App，取代本機程式碼修改；它不會替你的儲存庫執行更新或編譯。Cue 不會在未經你操作時自動安裝更新。

重新建置或更新使用 ad-hoc 簽章的 App，可能讓原先的輔助使用授權失效。若 Cue 的權限開關已開啟，簡繁轉換仍要求授權，請[移除舊權限項目，再加入目前已安裝的那份 App](chinese-conversion.md#重新建置或更新後仍顯示未取得權限)。

### 其他選項

```sh
# 只檢查 Command Line Tools／Swift 是否準備完成，不建置、不變更檔案。
./scripts/build-app.sh --check

# 只建置；產物位於儲存庫內的 .build/Cue.app。
./scripts/build-app.sh

# 直接安裝已有的建置產物，不重新編譯。
./scripts/install-app.sh --no-build

# 安裝到另一個你有寫入權限的固定位置。
./scripts/install-app.sh --destination /Applications/Cue.app

# 建置供開發除錯使用的 Debug 版本。
./scripts/build-app.sh debug
```

`./scripts/install-app.sh --check` 也會檢查安裝位置與 Cue 是否已結束，不會修改檔案。路徑包含空白時，請加上引號。建議保留一份日常使用的 Cue，並開啟已安裝的那份；`.build/Cue.app` 與 Xcode 產生的 App 是另外的開發執行環境。

若有安裝，腳本優先使用 `/Library/Developer/CommandLineTools`，也支援明確指定 `DEVELOPER_DIR`，不會更改全機的 `xcode-select` 設定。例如 `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/install-app.sh` 可指定使用獨立的命令列工具。若只裝了 Xcode，也可以使用目前選取的 Xcode 工具鏈。日常安裝不需要額外安裝 Xcode，編譯、資源打包、更新元件與簽章都由腳本處理。

需要開發或製作維護者發布用的通用 DMG 時，仍可使用 Xcode：開啟 `Cue.xcodeproj` 並執行 **Cue** scheme。本機安裝腳本只編譯目前 Mac 使用的架構，不製作通用 DMG。
