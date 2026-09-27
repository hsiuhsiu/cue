# Build and install from source / 從原始碼建置與安裝

## English

You can build Cue directly from GitHub without downloading a DMG. You need a Mac, full **Xcode with Swift 6 or later**, and an internet connection for the first build to fetch the pinned Sparkle dependency. No paid Apple Developer account, signing certificate, or maintainer update-signing key is required.

### First installation

1. Install Xcode, open it once, and finish its license and first-launch setup. Do this again after upgrading Xcode if it asks, including Xcode 27. Command Line Tools alone are not sufficient.
2. Quit any running Cue through its menu bar **Quit Cue** command.
3. Run these commands in Terminal:

```sh
git clone https://github.com/hsiuhsiu/cue.git
cd cue
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

The installer makes an optimized **Release** build for your Mac's architecture, checks the complete app signature, and installs it at **`~/Applications/Cue.app`**. It uses local ad-hoc signing and preserves Sparkle's own signed helpers. It does not ask for a signing key or change macOS security settings. The default location requires no administrator access.

Cue lives in the menu bar, with no Dock icon. Press **Option+Space** to open it. The installed app remains available after reboot and is independent of the repository and `.build` folder; you can open it from your home folder's Applications directory. To start it automatically, turn on **Settings → Launch at login**. If macOS requires approval, use **Open Login Items…** and allow Cue in System Settings. You can turn this off in Cue or macOS at any time.

The installer refuses to replace a running Cue; quit normally so pending clipboard saves finish. It verifies a staged copy before replacing the app and keeps the previous app until installation succeeds, restoring it if verification fails. Existing settings and clipboard history are outside the app bundle and are not modified by installation.

### Updating your own build

Quit Cue, then run this from the same repository:

```sh
git pull --ff-only
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

Use the same install path on each update so the login item continues to refer to the installed app. Its status comes from macOS; if approval is requested after an update, follow the message in Cue's Settings. If you have edited source files, resolve any Git conflicts before building.

Source builds retain the standard GitHub update checker. To keep using only your own builds, turn off **Settings → Updates → Automatically check for updates** and use the commands above. An update offered by Cue installs the published GitHub binary, which replaces local code changes; it does not pull or compile your repository. Cue never installs an update without your action.

### Other build options

```sh
# Check Xcode setup without building or changing any files.
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

The scripts prefer `/Applications/Xcode.app` and honor an explicit `DEVELOPER_DIR`. If Xcode is elsewhere, prefix the command with its developer directory, for example `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" ./scripts/install-app.sh`. The preflight reports incomplete setup and does not accept Apple's license for you. You can also open `Cue.xcodeproj` in Xcode and run the **Cue** scheme; use the install script for a persistent daily-use installation.

## 正體中文

不下載 DMG 也能直接從 GitHub 建置 Cue。需要 Mac、內含 **Swift 6 以上的完整 Xcode**，首次建置也需要網路以下載固定版本的 Sparkle 相依套件。**不需要付費 Apple Developer 帳號、簽章憑證或維護者的更新簽章金鑰**。

### 第一次安裝

1. 安裝並開啟 Xcode，完成授權與首次啟動設定。升級後若再次要求設定（包含 Xcode 27），請先完成；只有 Command Line Tools 無法建置 Cue。
2. 若 Cue 正在執行，先從選單列選擇**結束 Cue**。
3. 在「終端機」執行：

```sh
git clone https://github.com/hsiuhsiu/cue.git
cd cue
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

安裝程式會依這台 Mac 的架構產生最佳化的 **Release** 版本，檢查完整 App 簽章，並安裝至 **`~/Applications/Cue.app`**。它使用本機 ad-hoc 簽章，保留 Sparkle 自己的簽章，不會要求簽章金鑰，也不會變更 macOS 安全設定。預設安裝位置不需要管理者權限。

Cue 會出現在選單列，不會有 Dock 圖示；按 **Option+Space** 即可叫出。安裝後的 App 獨立於儲存庫與 `.build` 目錄，重開機後仍會留在使用者個人資料夾內的「Applications／應用程式」。若希望登入 Mac 後自動執行，開啟 **設定 → 登入時啟動**。macOS 若要求授權，按**開啟登入項目⋯**，再到系統設定允許 Cue；之後可隨時從 Cue 或 macOS 關閉。

安裝程式不會取代仍在執行的 Cue；請正常結束，讓尚未完成的剪貼簿儲存作業結束。它會先驗證暫存的新 App，再取代原版本；完成前保留舊 App，若驗證失敗會還原。設定與剪貼簿記錄位於 App 外，安裝過程不會修改這些資料。

### 更新自己建置的版本

先結束 Cue，再於原本的儲存庫目錄執行：

```sh
git pull --ff-only
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

每次使用相同安裝位置，讓登入項目持續指向已安裝的 App。登入狀態由 macOS 管理；若更新後需要重新允許，請依 Cue 設定中的提示操作。如果你修改過原始碼，請先處理 Git 提示的衝突，再建置。

自行建置的版本仍保留 GitHub 更新檢查。若只想使用自己的版本，請關閉 **設定 → 更新 → 自動檢查更新**，並用上方指令更新。從 Cue 內安裝更新會換成 GitHub 上已發布的 App，取代本機程式碼修改；它不會替你的儲存庫執行更新或編譯。Cue 不會在未經你操作時自動安裝更新。

### 其他選項

```sh
# 只檢查 Xcode 是否準備完成，不建置、不變更檔案。
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

腳本優先使用 `/Applications/Xcode.app`，也支援手動指定 `DEVELOPER_DIR`。若 Xcode 位於其他位置，可使用例如 `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" ./scripts/install-app.sh`。檢查會指出尚未完成的設定，不會代替你接受 Apple 授權。也可以在 Xcode 開啟 `Cue.xcodeproj` 並執行 **Cue** scheme；需要固定、可日常使用的安裝版本時，請使用安裝腳本。
