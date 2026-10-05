# Versioning / 版本規則

## English

Settings, About and update dialogs show one readable label: `major.minor.patch`
for stable builds, `major.minor.patch-beta.N` or `major.minor.patch-dev.N` for
source milestones. The internal build number is not appended in parentheses.

`Resources/Info.plist` is the source of truth:

| Field | Purpose |
| --- | --- |
| `CFBundleShortVersionString` | Numeric `major.minor.patch` base |
| `CFBundleVersion` | Monotonically increasing internal update build, stored as a string |
| `CueBuildChannel` | Explicit `stable`, `beta`, or `dev` |
| `CuePrereleaseNumber` | Positive integer required for beta/dev; absent for stable |

Numbers have no leading zeroes; each component is at most 2147483647. Build and
prerelease counters start at 1. Build tools require the explicit schema. Runtime
display tolerates a missing channel as stable for bundle compatibility; new
artifacts must not omit it.

Xcode's **Release** configuration means optimization, independently of channel.
A beta label does not create a GitHub prerelease, upload an app, or subscribe the
updater to betas. Source builds default to Cue-owned networking off; changing a
version does not alter a user's saved network/update choices.

### Choose and change a version

Use a **patch** for compatible fixes, a **minor** for compatible features, and a
**major** for a deliberately established new compatibility boundary. A 1.0 release
can mark a completed, supported product scope; it does not require every possible
feature or promise that all macOS versions have been tested.

Use the helper rather than editing the version and build separately:

```sh
# Inspect the current metadata without changing it.
./scripts/check-version.sh
./scripts/check-version.sh --display
```

For example, when preparing a milestone with base `1.1.0`:

```sh
./scripts/set-version.sh 1.1.0 beta 1
# Run separately when that milestone is ready for release:
./scripts/set-version.sh 1.1.0 stable
```

The beta and stable commands represent different stages, not a sequence to run
unconditionally. Every successful transition increments the internal build by
one, including beta-to-stable. Ordinary recompilation keeps the same milestone;
create a new sequence before distributing a distinct test milestone.

For a single base version, transitions move `dev → beta → stable`, and sequences
within one channel increase. Stable is final: choose the next patch/minor/major
before starting another milestone. A new base can start in any channel. The helper
validates input before atomically replacing the plist; invalid input preserves
the original bytes. `--plist` supports an isolated fixture. It never builds,
installs, commits or publishes.

### Update ordering and release guard

Sparkle compares **`CFBundleVersion`**, not the display suffix. Never reset the
build on a major/minor change or put `-beta.1` in it. Stable needs a higher build
than its betas so installed betas can receive the stable update. Do not reuse a
build for distinct distributed milestones or rewrite published tags, feeds or DMGs.

`./scripts/check-version.sh --release` requires stable metadata with no prerelease
field and a numeric base/build greater than every stable item in the local
`appcast.xml`. It does not fetch GitHub: synchronize the repository before release
preparation. `release.sh` checks before building/key access and again on the staged
app and mounted DMG. See [releasing](releasing.md) for signing and publication order.
Public releases use normal **Latest** status unless a prerelease is explicitly
requested.

`./scripts/check-version-tests.sh` exercises isolated metadata, transitions and
feed fixtures without launching Cue, modifying an installed app, reading
credentials or contacting a server.

## 正體中文

設定、「關於」與更新視窗統一顯示 `major.minor.patch`；測試里程碑則使用
`major.minor.patch-beta.N` 或 `major.minor.patch-dev.N`，不在後面加上括號
建置編號。版本以 `Resources/Info.plist` 為準：基礎版號為三段純數字，build
持續遞增，channel 明確指定 `stable`／`beta`／`dev`。Beta／dev 需要正整數
序號，stable 必須移除序號欄位。數字不能有多餘的開頭零，上限為 2147483647；
build 與測試序號從 1 開始。執行期容許舊 Bundle 缺少 channel，但新建置必須
符合完整格式。

相容的錯誤修正使用 patch，相容的新功能使用 minor，明確建立新的相容性
界線時使用 major。1.0 可代表已完成且願意支持的產品範圍，不表示必須包含
所有可能功能，也不代表已驗證所有 macOS 版本。

Xcode **Release** 只表示最佳化，不會自動把 beta 變成正式版；本機 beta 標記
也不會建立 GitHub 預覽版、上傳 App 或加入測試更新頻道。來源版維持離線預設，
使用者已儲存的網路及更新選擇不會因版號改變。

使用上方 `set-version.sh` 指令同步調整版號與 build。每次有效轉換都讓 build
加一，beta 轉正式也一樣；一般重新編譯維持同一里程碑。相同基礎版號只往
`dev → beta → stable` 前進，同階段序號必須增加；正式版之後需選下一個
patch／minor／major。腳本先驗證再原子替換，失敗不修改原檔，也不會建置、
安裝、commit 或發佈。

Sparkle 依內部 build 排序，所以 major／minor 改變時不能歸零，也不能加入
beta 後綴。不同分送里程碑不能共用 build；不要改寫已公開的 tag、簽署 feed
或 DMG。`check-version.sh --release` 以本機 appcast 檢查正式 channel 及遞增
版號／build，不會連線取得遠端狀態，發佈前需先同步 repo。封裝流程在建置與
讀取金鑰前、暫存 App 及掛載 DMG 後都會檢查。公開版預設是正常 **Latest**，
只有明確要求才用預覽版；完整流程見[發佈文件](releasing.md)。

`check-version-tests.sh` 使用隔離資料驗證版本轉換與發布門檻，不開啟 Cue、
不更換已安裝 App、不讀憑證，也不連線。
