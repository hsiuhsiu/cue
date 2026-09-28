# Network access / 網路存取

## English

Cue 0.5.0 adds a global network-access control in Settings. Turning it off
blocks both automatic and manual update checks. App discovery, search learning,
Clipboard History, system commands, and Chinese conversion remain available.

### Defaults and saved choices

- Source builds start with network access **off**. A missing build setting also
  means off.
- Published release builds start with network access **on**, so update checks
  can work. Installing an update still requires your choice.
- An explicit choice made in Settings is saved locally and takes precedence over
  either build default. Replacing the app does not reset that choice.
- Automatic update checking is a separate preference. Disabling network access
  pauses its activity without forgetting that preference; enabling access again
  permits the saved update schedule to resume.

### What uses the network

The only direct network feature in this version is the Sparkle updater. With
access allowed, it fetches Cue's signed update feed from GitHub and downloads
a release from GitHub when you choose to install it. Remote release-note
downloads are disabled; release notes are included in the signed feed.

Cue does not send search queries, usage history, clipboard contents, or selected
text to the updater. Sparkle's optional system-profile reporting is disabled.
Normal HTTP requests still expose connection information such as your IP address
and a user-agent string to the server; allowing updates is not anonymous access.

On an offline startup, Cue does not construct or start Sparkle. Turning access
off while an update is active blocks new checks and updater actions, stops Cue's
update timer, requests cancellation of active feed/download work, and closes
update-offer and download-progress windows. Cancellation is asynchronous inside Sparkle: data already
sent or buffered in the network stack cannot be recalled. The switch is an
application policy, not a packet-level firewall or a way to reverse an update
installation that has already started.

### Chinese conversion stays fully offline

Both conversion directions use the same bundled OpenCC dictionaries whether
network access is on or off. This includes Taiwan/mainland vocabulary rules;
there is no online service, dictionary fetch on first use, or reduced-quality
offline mode. Dictionaries load from the app bundle on a background executor.
See [conversion data and verification](chinese-conversion-data.md) for the pinned
data, algorithm, and accuracy limits of dictionary conversion.

### Scope

This control covers Cue's own network features, including updater workers.
It does not disable networking for another app you launch, macOS services,
mounted network filesystems, or clipboard providers. Cue uses the shared macOS
clipboard; Universal Clipboard and other clipboard managers follow their own
settings. Opening a link in a browser also hands control to that browser.

Developer tools are separate: cloning the repository, fetching the pinned
Sparkle package on the first build, and publishing a release require network
access. Ordinary builds use the checked-in Chinese dictionary resource.
Regenerating that resource is a maintainer operation that first obtains the
pinned OpenCC source; the running app never performs that download.

## 正體中文

Cue 0.5.0 在設定中加入全域網路存取開關。關閉後，自動與手動檢查更新都會停用；
App 索引、搜尋學習、剪貼簿記錄、系統指令及簡繁轉換仍可使用。

### 預設值與已儲存的選擇

- 自行建置的版本預設**關閉**網路存取；若缺少建置設定，也視為關閉。
- 發布下載的正式版預設**開啟**網路存取，讓更新檢查可以運作；安裝更新仍由你決定。
- 在設定中明確選擇後，會儲存在本機，並優先於版本的預設值；替換 App 不會重設。
- 自動檢查更新是另一個設定。關閉網路時會暫停其活動，但保留原本的選擇；重新
  允許網路後，才可依儲存的設定恢復排程。

### 哪些功能會連線

這個版本唯一直接使用網路的功能是 Sparkle 更新程式。允許網路時，會從 GitHub
取得已簽署的 Cue 更新列表，並在你選擇安裝後下載 GitHub 上的正式版本。
更新說明包含在已簽署的列表內，另行下載遠端更新說明的功能已停用。

Cue 不會將搜尋字詞、使用記錄、剪貼簿內容或選取文字傳給更新程式；Sparkle
的選用系統資料回報也已關閉。不過，一般 HTTP 連線仍會讓伺服器取得 IP 位址、
User-Agent 等連線資訊；允許檢查更新並不代表匿名連線。

網路關閉時啟動 Cue，不會建立或啟動 Sparkle。如果更新工作已經開始，關閉網路
會阻止新的檢查及更新操作、停止 Cue 的更新計時器、要求取消正在進行的列表或
安裝檔下載，並關閉新版通知及下載進度視窗。Sparkle 內部的取消是非同步操作，已傳送或已進入
網路緩衝區的資料無法收回。這是 App 的連線政策，不是封包層級的防火牆，也不能
撤銷已開始的更新安裝。

### 簡繁轉換維持完整離線功能

無論網路開關為何，兩個方向都使用同一份內附 OpenCC 詞庫，包含台灣與中國大陸
用語規則。不會呼叫線上服務、首次使用時下載詞庫，也沒有品質較差的離線替代模式。
詞庫由背景執行工作從 App 內讀取。固定版本的資料、演算法、驗證與字詞轉換的
準確度限制，請見[轉換資料說明](chinese-conversion-data.md)。

### 適用範圍

開關管理 Cue 自己的網路功能及更新工作，不會關閉其他已啟動 App、macOS 服務、
網路磁碟或剪貼簿提供者的網路。Cue 使用 macOS 共用剪貼簿；通用剪貼簿與其他
剪貼簿管理程式仍依各自設定運作。若在瀏覽器開啟連結，也由該瀏覽器接手處理。

開發工具另計：取得 Git 儲存庫、首次建置下載固定版本的 Sparkle，以及發布版本
都需要網路。一般建置直接使用儲存庫內附的中文詞庫；重新產生詞庫是維護者的
工作，須先取得固定版本的 OpenCC 原始碼，執行中的 Cue 不會進行這項下載。

## Implementation contract / 實作約定

`NetworkPolicy.allowsNetwork` is the shared runtime gate. The source
`Resources/Info.plist` sets `CueNetworkAccessAllowedByDefault` to `false`; the
release packaging step sets it to `true` only in the staged app. Missing values
fail closed. An explicit saved user choice overrides this build metadata.

`NetworkPolicy.allowsNetwork` 是共用的執行時檢查。原始碼中的
`Resources/Info.plist` 將 `CueNetworkAccessAllowedByDefault` 設為 `false`，
發布封裝流程只在暫存的 App 內改成 `true`；缺少值時預設關閉。已儲存的明確
使用者選擇優先於這項建置資料。

## Verification / 驗證

The optimized policy harness passes 324 checks using isolated preferences. The
updater harness passes 68 checks covering offline startup, daily scheduling,
preference restoration, canceled/stale callbacks, and real Sparkle delegate
selectors and request guards. It uses an injected engine and native user-driver
protocol fixtures without starting Sparkle or making network requests. These
checks do not constitute packet capture or an end-to-end update installation.
The installed Release app was also checked in English and Traditional Chinese:
source defaults are off, both update controls are disabled, and the menu reports
that networking is off. Packaging separately validates source and DMG defaults.

最佳化政策測試以隔離偏好設定通過 324 項檢查；更新測試通過 68 項，涵蓋離線啟動、
每日排程、偏好還原、取消及過期回呼，以及實際 Sparkle 委派介面與請求檢查。
更新測試使用注入引擎及原生使用者介面協定的測試物件，不會啟動 Sparkle 或發送
網路請求，因此不等同封包擷取或完整更新安裝測試。另已在安裝的 Release App
檢查英文及正體中文介面：來源版預設關閉網路，兩種更新控制均停用，選單也顯示
網路關閉。封裝流程會另外驗證原始碼與 DMG 的預設值。

A separate, randomly identified QA app using the final 0.5.0 executable was also
tested against a loopback server serving an unchanged signed feed/archive. Turning
network access off during a real Sparkle feed check closed the connection after
1,553 of 1,554 bytes; during an archive download it closed after 3,047,424 of
3,231,531 bytes. Both update controls immediately became disabled. The server
withheld completion deliberately, so no old fixture update could install. This
confirms cancellation through the real Sparkle stack; it does not test public
HTTPS delivery, final installation, or every possible transition timing. The QA
app and server were stopped, with production preferences untouched.

另以最終 0.5.0 執行檔建立隨機識別碼的獨立測試 App，連到提供未改動之簽署列表
與安裝檔的本機回環伺服器。真正的 Sparkle 列表檢查在關閉網路後，於傳輸
1,553／1,554 位元組時斷線；安裝檔下載則於 3,047,424／3,231,531 位元組時斷線，
兩種更新控制也立即停用。伺服器刻意不傳完，確保舊測試更新不可能安裝。
此測試確認真正 Sparkle 流程能取消，不代表已驗證公開 HTTPS 傳輸、最終安裝
或所有切換時序。測試 App 與伺服器已結束，正式偏好設定未受影響。
