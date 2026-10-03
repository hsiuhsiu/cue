# Network access / 網路存取

## English

Cue has a global network-access control in Settings. Turning it off
blocks both automatic and manual update checks. It governs requests made by Cue
itself. Since Cue 0.6.0, explicit Google browser searches use a
separate feature-local switch.
App discovery, local app/command search and learning, Clipboard History, system
commands, Chinese conversion, link cleaning, emoji search, the calculator, and
physical-unit conversion remain available. GPT answers and translation require
this global permission, as does currency conversion even when rates are cached.

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
- Browser search is independently **on by default** for source and published
  builds. Its saved choice lives in **Google Search Settings** and does not
  follow the global networking switch. Turn it off to prevent Cue from handing
  Google queries to an external browser.

### What uses the network

The Sparkle updater makes direct network requests. With
access allowed, it fetches Cue's signed update feed from GitHub and downloads
a release from GitHub when you choose to install it. Remote release-note
downloads are disabled; release notes are included in the signed feed.

Cue does not send search queries, usage history, clipboard contents, or selected
text to the updater. Sparkle's optional system-profile reporting is disabled.
Normal HTTP requests still expose connection information such as your IP address
and a user-agent string to the server; allowing updates is not anonymous access.

Cue also offers explicit Google search in the default
browser or browsers the user adds. After the first app index is ready, a
nonempty query with no local match shows those actions; Return, a click, or
Command+1–9 executes one. Command+Return searches in the default browser even
if local matches exist; Command+K shows text actions for the current text.
Cue makes no Google requests or suggestions while typing. Only executing the
action hands the query to the browser, which sends it to Google. Cue does not
persist Google query text in its search-learning history; the browser and Google
apply their own history, account, and privacy settings. Empty input and input
method composition do not submit a search. See [Google search](web-search.md).

Google search checks its own browser-search setting immediately before handoff.
The global switch may stay off because Cue does not make the browser's request.
Turning browser search off in **Google Search Settings** prevents new handoffs;
the results display a disabled reason instead of opening a browser. Neither
switch can cancel navigation already accepted by another browser or remove data
already sent to Google. Search **`google settings`** or press Command-comma on a
Google result to open this feature's settings.

With Cue's own network access off at startup, it does not construct or start Sparkle. Turning access
off while an update is active blocks new checks and updater actions, stops Cue's
update timer, requests cancellation of active feed/download work, and closes
update-offer and download-progress windows. Cancellation is asynchronous inside Sparkle: data already
sent or buffered in the network stack cannot be recalled. The switch is an
application policy, not a packet-level firewall or a way to reverse an update
installation that has already started.

### Currency rates and local unit conversion

Cue 0.8.0 introduced currency conversion. With Cue's global network access
enabled, a recognized currency query can fetch the fixed HTTPS table at
`https://open.er-api.com/v6/latest/USD`.
Cue downloads the same USD-based table for every query and calculates locally:
it does not send the amount, entered text, source currency or target currency.
The provider still sees ordinary connection information, including the IP address.

[ExchangeRate-API's open endpoint](https://www.exchangerate-api.com/docs/free)
requires no API key and updates daily. Cue caches the table until the provider's
next-update time (rejecting data or update intervals over 48 hours), displays the rate timestamp and a visible attribution link,
and treats rates as indicative rather than bank or transaction quotes. When
refresh is required, failure shows an unavailable state rather than a stale
answer. No rate request starts at app startup or outside an active currency
query. Rates load asynchronously; typing does not wait for them.

Turning Cue networking off prevents new rate requests, cancels active work and
hides cached currency answers. Canceled or older responses cannot restore an
answer. Data already sent cannot be recalled. An offline or failed currency
query shows its reason instead of automatically becoming a Google result;
explicit Google actions continue to use their own separate permission.
Conversion queries and results are excluded from search learning. Ordinary
physical-unit conversions, including Taiwan's 坪, stay fully offline. See
[unit and currency conversion](unit-conversion.md).

### GPT answers and translation

GPT is available in Cue 0.9.0. Only explicitly choosing **Ask GPT**, **Translate with GPT**, or **Retry** sends the current text to `https://api.openai.com/v1/responses`. Typing, rendering choices, opening GPT settings and changing the model do not request answers. The request contains that text, the selected model, and short task instructions; it does not include app inventory, search-learning data, clipboard history, other windows, or previous replies. No live web-search tool is enabled. Credentials stay in the user's macOS Keychain, not preferences or the app bundle.

The global network permission is checked before reading the key and again before starting a request. Turning it off cancels the active stream; older callbacks cannot restore the answer or start another request. Stop, returning from a reply, closing Cue's panel, and changing credentials cancel pending work. A retry is always explicit, and re-enabling networking never resubmits a question. Cancellation cannot recall text OpenAI already received or guarantee that server-side generation or billing stops immediately.

Cue uses an ephemeral session without cookies or a disk cache, refuses redirects, sends `store: false`, and does not save questions or replies as conversation history or search-learning data. Copying a reply writes it to the system clipboard, where normal Clipboard History rules apply. `store: false` is not a promise of zero retention at OpenAI: its [API data controls](https://developers.openai.com/api/docs/guides/your-data) still apply. See [GPT setup and behavior](gpt.md).

### Chinese conversion stays fully offline

Both conversion directions use the same bundled OpenCC dictionaries whether
network access is on or off. This includes Taiwan/mainland vocabulary rules;
there is no online service, dictionary fetch on first use, or reduced-quality
offline mode. Dictionaries load from the app bundle on a background executor.
See [conversion data and verification](chinese-conversion-data.md) for the pinned
data, algorithm, and accuracy limits of dictionary conversion.

### Link cleaning stays fully offline

Cue cleans a single HTTP or HTTPS link in the clipboard
only when you run the link-cleaning command. It removes known tracking query
parameters locally and writes the result back to the clipboard; it makes no
network request, DNS lookup, browser handoff, or automatic paste. It does not
expand short links or follow redirects. Recognized signed URLs remain unchanged,
and clipboard URL text is not saved in Cue's search-learning history. The same
cleaning rules apply whether either network/browser-search switch is on or off.
See [link cleaner behavior](link-cleaner.md).

### Emoji search stays fully offline

Emoji and their English/Traditional Chinese names and keywords are bundled with
Cue. Searching needs no service, first-use download, or network permission. The
feature copies only the emoji you explicitly choose; it does not paste into
another app. Emoji search text and result selections are not saved in Cue's
search-learning history. If Clipboard History recording is enabled, the copied
emoji follows its normal recording rules. See [Emoji search](emoji.md).

### Scope

This control covers Cue's own network features, including updater workers.
It does not disable networking for another app you launch, macOS services,
mounted network filesystems, or clipboard providers. Cue uses the shared macOS
clipboard; Universal Clipboard and other clipboard managers follow their own
settings. Explicitly handing a Google query to a browser uses the separate
browser-search preference, not `NetworkPolicy.allowsNetwork`. Once a link is
handed over, that browser controls its own network activity. Merely launching
a browser application from local app results remains an app-launch action;
these switches are not a firewall for that app. Any future network API request
made by Cue must use the global gate just as GPT and currency
rates do.

Developer tools are separate: cloning the repository, fetching the pinned
Sparkle package on the first build, and publishing a release require network
access. Ordinary builds use the checked-in Chinese dictionary and emoji catalog.
Regenerating those resources is a maintainer operation using pinned OpenCC or
Unicode/CLDR source data; the running app never downloads these resources.

## 正體中文

Cue 在設定中提供全域網路存取開關，管理 Cue 自己發出的請求。關閉後，
自動與手動檢查更新都會停用。自 Cue 0.6.0 起提供的 Google 瀏覽器搜尋使用獨立
功能開關。App 索引、本機 App／指令搜尋與學習、剪貼簿記錄、系統指令、
簡繁轉換、連結清理、emoji 搜尋、計算機與一般單位換算仍可使用。GPT 問答與
翻譯需要這項全域許可；幣值換算也一樣，即使已快取匯率也需要允許連網。

### GPT 問答與翻譯

Cue 0.9.0 起提供 GPT。只有明確選擇**問 GPT**、**GPT 翻譯**或**重試**，才會將目前文字傳送至 `https://api.openai.com/v1/responses`；打字、顯示選項、開啟 GPT 設定或更改模型都不會請求答案。請求包含該段文字、模型與簡短的任務指示，不包含 App 清單、搜尋學習資料、剪貼簿歷史、其他視窗或先前回答，也不啟用即時網頁搜尋工具。金鑰存於使用者的 macOS 鑰匙圈，不放進偏好設定或 App 套件。

讀取金鑰前與開始請求前都會檢查全域網路許可。關閉網路會取消回答串流，過期回呼不能恢復答案或發出新請求。停止、返回、收起 Cue 視窗及修改金鑰也會取消進行中的工作；重試必須明確操作，重新允許網路不會自動重送。取消無法收回 OpenAI 已收到的文字，也不能保證伺服器端生成或計費立即停止。

連線不使用 Cookie 或磁碟快取，拒絕重新導向，且傳送 `store: false`。Cue 不會將提問或回答存成對話歷史或搜尋學習資料；拷貝答案則會寫入系統剪貼簿，適用一般剪貼簿記錄規則。`store: false` 不代表 OpenAI 端完全零保留，仍適用其 [API 資料政策](https://developers.openai.com/api/docs/guides/your-data)。詳見 [GPT 設定與行為](gpt.md)。


### 預設值與已儲存的選擇

- 自行建置的版本預設**關閉**網路存取；若缺少建置設定，也視為關閉。
- 發布下載的正式版預設**開啟**網路存取，讓更新檢查可以運作；安裝更新仍由你決定。
- 在設定中明確選擇後，會儲存在本機，並優先於版本的預設值；替換 App 不會重設。
- 自動檢查更新是另一個設定。關閉網路時會暫停其活動，但保留原本的選擇；重新
  允許網路後，才可依儲存的設定恢復排程。
- 瀏覽器搜尋在自行建置與發布版都**預設開啟**，選擇儲存在 **Google 搜尋設定**，
  不跟隨全域網路開關。若也要阻止 Cue 將 Google 字詞交給其他瀏覽器，請關閉
  這項獨立設定。

### 哪些功能會連線

Sparkle 更新程式會直接使用網路。允許網路時，會從 GitHub
取得已簽署的 Cue 更新列表，並在你選擇安裝後下載 GitHub 上的正式版本。
更新說明包含在已簽署的列表內，另行下載遠端更新說明的功能已停用。

Cue 不會將搜尋字詞、使用記錄、剪貼簿內容或選取文字傳給更新程式；Sparkle
的選用系統資料回報也已關閉。不過，一般 HTTP 連線仍會讓伺服器取得 IP 位址、
User-Agent 等連線資訊；允許檢查更新並不代表匿名連線。

Cue 也提供在預設或自行加入瀏覽器執行的 Google 搜尋。初次 App 索引
完成後，若非空白查詢沒有本機結果，就會顯示這些動作；按 Return、點選或
Command+1–9 才會執行。即使已有本機結果，也可用 Command+Return 在預設瀏覽器
搜尋，或按 Command+K 顯示目前文字的可用動作。
打字時不會向 Google 發送請求或取得搜尋建議；只有執行動作時，才將查詢交給
瀏覽器送至 Google。Cue 不會將 Google 搜尋字詞存入搜尋學習記錄；瀏覽器與
Google 依各自的歷史記錄、帳號及隱私設定處理。空白輸入與輸入法組字期間都
不會送出搜尋。詳見 [Google 搜尋](web-search.md)。

Google 搜尋在交給瀏覽器前會再次檢查自己的瀏覽器搜尋開關。全域開關可以維持
關閉，因為瀏覽器的請求並非由 Cue 發出。在 **Google 搜尋設定**關閉瀏覽器搜尋，
才會阻止新的交接，結果會顯示停用原因而不開啟瀏覽器。兩個開關都不能取消已
由其他瀏覽器接手的導覽，或移除已送至 Google 的資料。輸入 **`google settings`**，
或選到 Google 結果時按 Command-comma，即可開啟功能設定。

關閉 Cue 自行連網時啟動 App，不會建立或啟動 Sparkle。如果更新工作已經開始，關閉網路
會阻止新的檢查及更新操作、停止 Cue 的更新計時器、要求取消正在進行的列表或
安裝檔下載，並關閉新版通知及下載進度視窗。Sparkle 內部的取消是非同步操作，已傳送或已進入
網路緩衝區的資料無法收回。這是 App 的連線政策，不是封包層級的防火牆，也不能
撤銷已開始的更新安裝。

### 匯率與本機單位換算

Cue 0.8.0 起提供幣值換算。允許 Cue 自行連網時，
辨識出的幣值查詢可觸發下載固定的 HTTPS 匯率表：
`https://open.er-api.com/v6/latest/USD`。每次都取得同一份以美元為基準的資料，
換算在本機完成；不會送出金額、輸入文字、來源或目標幣別。服務提供者仍會
收到 IP 位址等一般連線資訊。

[ExchangeRate-API 公開端點](https://www.exchangerate-api.com/docs/free)不需要
API 金鑰，每日更新。Cue 會快取至來源指定的下次更新時間，拒絕超過 48 小時
的資料或更新間隔，顯示匯率資料時間
與來源連結。這些是參考匯率，不是銀行或交易報價。需要更新時若下載失敗，會
顯示無法取得資料，不會用過期答案替代；App 啟動時或未使用幣值查詢時不會
請求匯率，資料在背景載入，不阻塞打字。

關閉 Cue 自行連網會阻止新匯率請求、取消進行中的工作，並隱藏快取的幣值
答案。已取消或較舊的回應不能重新顯示答案；已送出的資料則無法收回。
離線或失敗的幣值查詢會顯示原因，不會自動變成 Google 結果；明確執行的
Google 動作仍遵守自己的獨立許可。換算查詢與結果不會加入搜尋學習。
一般單位換算包含台灣的坪，維持完全離線。詳見[單位與幣值換算](unit-conversion.md)。

### 簡繁轉換維持完整離線功能

無論網路開關為何，兩個方向都使用同一份內附 OpenCC 詞庫，包含台灣與中國大陸
用語規則。不會呼叫線上服務、首次使用時下載詞庫，也沒有品質較差的離線替代模式。
詞庫由背景執行工作從 App 內讀取。固定版本的資料、演算法、驗證與字詞轉換的
準確度限制，請見[轉換資料說明](chinese-conversion-data.md)。

### 連結清理維持完整離線功能

Cue 只在執行清理指令時，才處理剪貼簿中的單一 HTTP 或 HTTPS 連結。
在本機移除已知的網址追蹤參數後寫回剪貼簿，不發出網路請求、查詢 DNS、交給
瀏覽器或自動貼上，也不展開短網址或跟隨重新導向。已識別的簽署網址維持原樣，
剪貼簿網址也不會存入 Cue 的搜尋學習記錄。無論網路與瀏覽器搜尋開關開啟或
關閉，清理規則都相同。詳見[連結清理行為](link-cleaner.md)。

### Emoji 搜尋維持完整離線功能

Emoji 及其英文／正體中文名稱與關鍵字隨 Cue 內附，不需服務、首次下載或網路
許可。此功能只拷貝你明確選擇的 emoji，不會貼入其他 App。Emoji 搜尋文字與
選取結果不會存入 Cue 的搜尋學習記錄；若已啟用剪貼簿記錄，拷貝的 emoji 依
一般記錄規則處理。詳見 [Emoji 搜尋](emoji.md)。

### 適用範圍

開關管理 Cue 自己的網路功能及更新工作，不會關閉其他已啟動 App、macOS 服務、
網路磁碟或剪貼簿提供者的網路。Cue 使用 macOS 共用剪貼簿；通用剪貼簿與其他
剪貼簿管理程式仍依各自設定運作。明確將 Google 查詢交給瀏覽器的動作遵守
獨立的瀏覽器搜尋偏好，不受 `NetworkPolicy.allowsNetwork` 控制；交接後的
網路活動由瀏覽器自行管理。單純從本機 App 結果開啟瀏覽器仍屬於啟動 App，
這些開關不是該 App 的防火牆。未來由 Cue 自己發出的其他 API 請求，
也必須像 GPT 與匯率功能一樣遵守全域網路開關。

開發工具另計：取得 Git 儲存庫、首次建置下載固定版本的 Sparkle，以及發布版本
都需要網路。一般建置直接使用儲存庫內附的中文詞庫與 emoji 目錄；重新產生
資料是維護者的工作，使用固定版本的 OpenCC 或 Unicode／CLDR 來源。
執行中的 Cue 不會下載這些資料。

## Implementation contract / 實作約定

`NetworkPolicy.allowsNetwork` is the shared runtime gate for Cue-owned requests,
including dependencies and background workers. Explicit external browser search
uses the feature's separate saved preference, enabled by default. Never turn an
internal API call into a silent browser handoff to bypass the global gate. The source
`Resources/Info.plist` sets `CueNetworkAccessAllowedByDefault` to `false`; the
release packaging step sets it to `true` only in the staged app. Missing values
fail closed. An explicit saved user choice overrides this build metadata.

`NetworkPolicy.allowsNetwork` 是 Cue 自有請求共用的執行時檢查，包含相依套件及
背景工作。明確操作的外部瀏覽器搜尋使用功能內獨立、預設開啟的已儲存偏好；
不可把內部 API 呼叫悄悄換成瀏覽器交接來繞過全域開關。原始碼中的
`Resources/Info.plist` 將 `CueNetworkAccessAllowedByDefault` 設為 `false`，
發布封裝流程只在暫存的 App 內改成 `true`；缺少值時預設關閉。已儲存的明確
使用者選擇優先於這項建置資料。

## 0.5.0 verification / 0.5.0 驗證

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
