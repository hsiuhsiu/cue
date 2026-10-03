# Unit and currency conversion / 單位與幣值換算

## English

Available in Cue 0.8.0. Enter a number and unit directly in Cue's main launcher. No separate page
or setting is needed.

### Convert and copy

| Input | Behavior |
| --- | --- |
| `10m` | Show up to three common length conversions. |
| `10m to ft` | Convert metres to feet. |
| `5坪` | Convert Taiwan's 坪 to common area units. |
| `100 m2 to 坪` | Show `30.25 坪`. |
| `100USD` | Show up to three common currency conversions. |
| `100USD to TWD` | Convert US dollars to Taiwan dollars using the current reference table. |

Select a result and press **Return**, or use its **Command+number**, to copy
only the numeric value and close Cue. The displayed unit is not copied. Paste
with **Command+V** in the destination app; Cue does not paste automatically.
App and command matches remain available within the nine-result limit.

Physical units are calculated entirely on this Mac, including with networking
off. Taiwan area conversion uses **1 m² = 0.3025 坪**, consistent with the
[Taipei Department of Land Administration](https://w3.land.gov.taipei/calareacnvr/).
The reverse conversion uses that ratio rather than a rounded `3.3058` constant.

### Supported input

| Category | Unit symbols |
| --- | --- |
| Length | `mm`, `cm`, `m`, `km`, `in`, `ft`, `yd`, `mi` |
| Area | `cm2`, `m2`, `ft2`, `坪`, `ha`, `acre` |
| Mass | `g`, `kg`, `oz`, `lb` |
| Volume | `mL`, `L`, `US fl oz`, `US gal` |
| Temperature | `C`, `F`, `K` |
| Time | `s`, `min`, `h`, `day` |
| Speed | `km/h`, `m/s`, `mph` |

Common English names and Traditional Chinese aliases are also accepted, such as
`10公尺`, `5平方公尺`, `20公斤`, `100美元`. Use `to`, `in`, `轉`, or `→` to
specify a target; both units must have the same kind. Currency codes ignore case;
short unit symbols use their listed case and explicit aliases. `gal` and `fl oz`
mean US units; `oz` is mass. Area also accepts superscripts such as `m²`.

Amounts can be signed decimals or scientific notation; use a leading zero for
fractions, such as `0.5m`. Input is limited to 256 UTF-8 bytes. Grouping separators,
mixed-unit expressions and arithmetic before a unit are not supported. A
temperature below absolute zero or a value outside the supported numeric range
does not produce a conversion. Physical-unit results use up to 8 significant
digits and show `≈` when rounded; the calculation retains its decimal precision.
Currency answers always show `≈`; magnitudes of at least `0.01` round to two
decimal places, while smaller values retain up to 16 significant digits.

### Currency rates

Currencies use three-letter codes, such as **TWD, USD, JPY, EUR, CNY, HKD and
GBP**. A recognized currency query requires **Settings → Network & Updates → Allow Cue
to access the network**. If access is off, Cue shows the reason and does not
display a cached currency answer. Physical units still work.

Rates come from [ExchangeRate-API](https://www.exchangerate-api.com). Its
[open endpoint](https://www.exchangerate-api.com/docs/free) needs no API key
and updates once per day. Cue displays the source and rate timestamp. These
are indicative rates, not live market prices or a bank's buy/sell quote.

With network access allowed, entering a currency query can download the rate
table in the background. A fresh table is reused until its stated next-update
time; data or update intervals older than 48 hours are rejected. Requests run
only while a currency query is active, not at app startup. When a refresh is
required, Cue shows progress; a failed refresh shows an unavailable state with
a retry action instead of using stale rates. After ordinary errors, explicit
retry has a five-second cooldown and subsequent automatic attempts have a
five-minute cooldown; a server rate limit requires 20 minutes. It does not turn that recognized currency query into
an automatic Google result.

Cue always requests the same USD-based table at
`https://open.er-api.com/v6/latest/USD` and performs the conversion locally.
The amount, entered text, and requested currencies are not sent. The server
still receives normal connection information, including your IP address.
Turning off networking cancels pending rate work and hides currency answers;
already-sent network data cannot be recalled. Explicit Google actions use
their own browser-search permission. See [network scope](network-policy.md).

### Privacy

The cache at `~/Library/Caches/com.yyhsiu.cue/Currency/rates.json` contains only
the rate table and timestamps, not amounts or conversion history.
Conversion text and results are not saved in search-learning history. Typing
does not change the clipboard. If Clipboard History recording is enabled,
numeric values you explicitly copy follow its normal recording rules.
macOS Universal Clipboard and other clipboard managers have their own settings.

## 正體中文

Cue 0.8.0 起提供。直接在 Cue 主搜尋輸入
數值與單位，不需要進入另一個頁面，也沒有額外設定。

### 換算與拷貝

| 輸入 | 行為 |
| --- | --- |
| `10m` | 顯示最多三種常用長度換算。 |
| `10m to ft` | 公尺換算為英呎。 |
| `5坪` | 將台灣的坪換算為常用面積單位。 |
| `100 m2 to 坪` | 顯示 `30.25 坪`。 |
| `100USD` | 顯示最多三種常用幣值換算。 |
| `100USD to TWD` | 依目前的參考匯率表，將美元換算為新台幣。 |

選取結果後按 **Return**，或按對應的 **Command+數字**，即可只拷貝數值並
收起 Cue，不會拷貝畫面上的單位。再到目標 App 按 **Command+V** 貼上，
Cue 不會自動貼入。符合的 App 與指令仍會列出，合計最多九筆結果。

一般單位全部在這台 Mac 計算，關閉網路仍可使用。台灣面積採用
**1 平方公尺 = 0.3025 坪**，與
[臺北市政府地政局](https://w3.land.gov.taipei/calareacnvr/)公布的換算一致；
反向換算也使用同一比例，不使用已四捨五入的 `3.3058` 常數。

### 支援輸入

| 類別 | 單位符號 |
| --- | --- |
| 長度 | `mm`、`cm`、`m`、`km`、`in`、`ft`、`yd`、`mi` |
| 面積 | `cm2`、`m2`、`ft2`、`坪`、`ha`、`acre` |
| 質量 | `g`、`kg`、`oz`、`lb` |
| 體積 | `mL`、`L`、`US fl oz`、`US gal` |
| 溫度 | `C`、`F`、`K` |
| 時間 | `s`、`min`、`h`、`day` |
| 速度 | `km/h`、`m/s`、`mph` |

也接受常用英文名稱及正體中文別名，例如 `10公尺`、`5平方公尺`、`20公斤`、
`100美元`。可用 `to`、`in`、`轉` 或 `→` 指定目標，兩邊必須是相同類別的單位。
幣別代碼不區分大小寫；短單位符號依上表的大小寫及明列別名辨識。`gal` 與
`fl oz` 代表美制單位，`oz` 則是質量。面積也接受 `m²` 這類上標寫法。

數值可含正負號、小數或科學記號；小數請加前方的零，例如 `0.5m`。輸入最多
256 個 UTF-8 位元組，不支援千分位符號、混合單位算式或先運算再接單位。
低於絕對零度的溫度，或超出可處理數值範圍的輸入，不會產生換算結果。
一般單位結果最多顯示 8 位有效數字，四捨五入時標示 `≈`，運算仍保留十進位
精度。幣值答案一律標示 `≈`；絕對值至少為 `0.01` 時四捨五入至小數點後兩位，
更小的數值則最多保留 16 位有效數字。

### 幣值匯率

幣別使用三個英文字母代碼，例如 **TWD、USD、JPY、EUR、CNY、HKD、GBP**。
辨識出的幣值查詢需要開啟**設定 → 網路與更新 → 允許 Cue 自行連網**。若關閉，
Cue 會顯示原因，也不會顯示快取的幣值答案；一般單位仍可使用。

匯率來自 [ExchangeRate-API](https://www.exchangerate-api.com)，其
[公開端點](https://www.exchangerate-api.com/docs/free)不需 API 金鑰，每日更新
一次。Cue 會顯示來源與匯率資料時間。這是參考匯率，不是即時行情或銀行
買入／賣出報價。

允許網路時，輸入幣值查詢可觸發背景下載匯率表；未到資料標示的下次更新
時間前，會重用快取；資料或更新間隔超過 48 小時則不接受。只有正在使用
幣值查詢時才會請求匯率，不會在 App 啟動時下載。需要更新時顯示處理狀態；
若下載失敗，會顯示無法取得資料與重試動作，不使用過期匯率。一般錯誤後，
手動重試至少間隔五秒，後續自動嘗試至少間隔五分鐘；若服務限制請求頻率，
則需等待 20 分鐘。
已辨識的幣值查詢不會自動轉成 Google 結果。

Cue 固定下載 `https://open.er-api.com/v6/latest/USD` 的美元基準匯率表，
在本機完成換算，不會送出金額、輸入文字或指定的幣別；伺服器仍會收到
IP 位址等一般連線資訊。關閉網路會取消等待中的匯率工作並隱藏幣值答案，
已送出的網路資料則無法收回。明確執行的 Google 動作依自己的瀏覽器搜尋
許可處理；詳見[網路適用範圍](network-policy.md)。

### 隱私

`~/Library/Caches/com.yyhsiu.cue/Currency/rates.json` 只快取匯率表與時間，
不包含金額或換算歷史。換算文字與結果不會存入搜尋學習記錄。單純打字不會修改剪貼簿；若啟用
剪貼簿記錄，明確拷貝的數值會依一般記錄規則處理。macOS 通用剪貼簿與
其他剪貼簿管理程式仍有各自的設定。
