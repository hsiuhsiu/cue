# Performance / 效能

Cue keeps input, ranking and keyboard selection independent of file access,
network requests and background image preparation. Ordinary edits have no debounce
or intentional delay. This guide describes the current design and how to measure it.

## Input and background work

- Search reads a prepared in-memory app index, name forms, aliases and usage scores.
  Bounded ASCII name bytes are prepared once during indexing; Unicode inputs retain
  the general matcher. Recent query results are cached.
- Application and command matching accepts at most 1,024 UTF-8 bytes per query.
  Longer input bypasses matching and numeric parsing while preserving the original
  text for explicit text actions. Long whitespace classification uses a cancellable
  worker. This is a work bound, not truncation of the user's input.
- File search starts only for `f ` queries. Spotlight work and candidate decoding
  happen in the background with cancellation between candidates. Overlapping
  exact/prefix/substring query candidates are decoded once; ranking retains nine
  results. Filename/path metadata and stable IDs are prepared before rendering.
- File refinements retain visible results that still match, preserve panel height
  while pending, and show a small progress indicator. Unrelated rows disappear.
  Navigating retained results fixes their order and numbered shortcuts until the
  next edit, so late completions cannot redirect a selection.
- Native launcher rows are reused. One synchronous input edit publishes one coherent
  snapshot; background completions publish separately.
- App action menus are created only when explicitly opened. Finder target checks
  run on a worker after execution; a canceled or superseded request cannot hand off
  to Finder after the next invocation. Ordinary search performs no new file access.
- At most two application-icon decoders run concurrently, including across cache
  invalidation. Up to nine current targets wait, and stale queued work is discarded.
  The cache holds at most 256 prepared 64×64 images, about 4 MiB of its own pixel
  data. AppKit/system allocations and command/browser caches are separate.
- Built-in command artwork is prepared on a worker at both display scales. Ready
  images update matching cells without changing rows, input focus or selection.
- Clipboard search reuses normalized UTF-8 data rather than normalizing every entry
  for every query. The store is bounded to 500 entries / 4 MiB. Unchanged expiration
  checks use sorted endpoints; expired or invalid records take the repair path.
- Conversion dictionaries load only when a conversion is executed. GPT, currency
  requests, settings persistence and clipboard writes run away from the typing path.
- Command History keeps at most 200 entries / 512 KiB of text in memory. Up/Down
  recall uses a frozen snapshot; JSON loading and saving run on a separate actor.
  Ordinary launcher edits do not filter this history. Its own page prepares search
  text once per snapshot and renders up to nine rows. The first edit after recall
  publishes one snapshot, without briefly restoring the old query or its caret.

## Ranking behavior

For applications, an exact custom search alias comes first. Automatic names include
the display name, local bundle names, and the `.app` filename, prepared once during
indexing. Each app appears once, using its strongest name match. Other text
matching follows: exact name, name prefix, word prefix,
substring, then initials/fuzzy matches. Exact custom aliases and complete names
stay ahead. Among partial matches, the score for the exact normalized query
comes before match category: choosing Home Assistant for `HA` can put it above
incidental prefix and substring matches after one successful launch. General
popularity only breaks ties within a category. Existing match penalties, positions, name lengths, names,
and paths break remaining ties. Matching commands also learn their order relative
to other commands.

The sorted app and command lists are merged by comparing the exact-query scores
of their next results, preserving each list's internal order. A higher score for
an app can move it ahead of a command; a tie keeps the command first. Overall
popularity alone does not change this app/command order. For example, `it` also
matches a substring of `traditional`, but a successful iTerm2 selection for `it`
can put the app ahead of that incidental conversion command on the next
invocation. There is no minimum repeat count: one successful choice suffices when
the competing result has no history for that query. An explicitly configured
exact app alias is placed ahead of ordinary commands and app matches. An explicit
conversion-command alias wins any legacy collision; new collisions are rejected
in both alias editors. Numeric answers keep their leading position.

Each successful selection adds one point. Older points decay with a 14-day
half-life, combining frequency and recency without a clock read on every key.
Decay is recalculated in the background when loading or recording usage, not on
every keystroke.
Queries are normalized for case, diacritics, width, and whitespace. Learning one
query does not automatically create preferences for its partial prefixes; general
usage can still influence those searches within each list. A habit cannot
introduce a result that does not match or promote a weaker app match above an
exact app match.

The launcher records a successful app launch or built-in command using the query
that led to it. Typing, arrow selection, canceling, and failures do not count.
Opening Clipboard History is a command; its contents and internal searches are
not part of search learning. An empty launcher stays empty.

## Local storage and the typing path

State is bounded at 512 result identifiers, 256 normalized queries, and eight
result associations per query. Queries longer than 128 UTF-8 bytes and result
identifiers longer than 512 UTF-8 bytes are not recorded. Oldest associations
are evicted when limits are reached. State is plain local JSON at
`~/Library/Application Support/com.yyhsiu.cue/Search/usage.json`, with owner-only
file/directory permissions. It contains successful queries, app paths or command
identifiers, scores, and timestamps. It is not uploaded or encrypted.

To reset learning, quit Cue, remove just this `Search/usage.json` file, and reopen
Cue. Preferences and Clipboard History use separate storage.

An actor loads and updates the state off the main thread. It prepares immutable
score dictionaries there, including decay math. The typing path reads those
scores from memory to rank each list and merge matching apps and commands;
queries without their own history skip the merge. It never reads or writes
the usage file or waits for that actor. Startup continues while history loads.
Recent query results remain cached.

Incoming learning updates are staged. A new query or the next invocation adopts
the snapshot and invalidates cached results, preserving the visible order and
numbered shortcuts while the user is choosing. Disk writes coalesce in the
background, and normal app termination flushes pending changes. The write delay
does not delay typing, opening an app, or learning in memory.

File queries, calculator expressions, clipboard contents, emoji searches, Google
queries and GPT input/output are excluded from search learning. Explicit app and
command choices are the only source of ranking preferences.

The separate, enabled-by-default [Command History](command-history.md) saves
submitted launcher input, including Google/GPT text and filename queries. Its
recording switch, deletion controls and file are independent of ranking data.

## Reproduce measurements

Run optimized checks serially, after other compilation and benchmarks finish:

```sh
./scripts/benchmark-adaptive-search.sh --app-aliases
./scripts/benchmark-file-search.sh
./scripts/benchmark-interactions.sh
./scripts/benchmark-clipboard.sh
./scripts/benchmark-long-query.sh
```

These fixtures use synthetic applications, queries and files, temporary stores,
private pasteboards and offscreen native views. They do not read personal history
or credentials, start network requests, replace the installed app, or take desktop
focus. Adaptive-search fixtures cover 500/1,000 apps, empty/maximum usage state,
extra names and aliases, cached/uncached queries, and synthetic CPU/I/O contention.
Clipboard fixtures fill the 500-entry / 4 MiB limit. File fixtures exercise ranking,
refinement, completion, cancellation and layout with bounded candidate sets.
The interaction harness also measures recall and native layout from 200 synthetic
command-history entries, without executing the recalled actions.

`benchmark-adaptive-search.sh --baseline-ref <git-ref>` and
`benchmark-long-query.sh --baseline-ref <git-ref>` can compare an earlier checkout
without modifying the current one. File and interaction harnesses accept an
explicit source root. Use a baseline containing the same APIs and workload;
compilation success alone does not make two fixtures equivalent.

Optional `./scripts/benchmark-icons.sh` profiles the system icon API against
installed applications without opening a window. Unlike the synthetic fixtures,
it reads the local app inventory. System/filesystem caches are not flushed.

Report medians, p95/p99 and maxima, including first-use work and scheduling tails.
A short component average cannot establish visible responsiveness. Timing thresholds
are deliberately not correctness assertions.

## Measurement reference

Measured **2026-10-18** on the development **Apple silicon Mac, macOS 27.0,
Xcode 27 / Swift 6.4**, using optimized native builds, serial synthetic
workloads and offscreen native views. These numbers are a measured reference for
that source and machine, not a latency guarantee for future builds or other Macs.

| Workload | Median | p95 |
| --- | ---: | ---: |
| App search: 1,000 apps, extra names, 256 aliases, maximum usage; uncached model | 0.338 ms | 1.580 ms |
| File ranking: 384 `report` candidates → nine rows | 1.557 ms | 2.006 ms |
| File refinement + native layout | 0.171 ms | 0.182 ms |
| File completion + native layout, unchanged matching results | 0.133 ms | 0.148 ms |
| Unchanged clipboard expiration: 500 entries / 4 MiB | 0.0055 ms | 0.0102 ms |

App-search p99 was 1.667 ms and maximum 2.005 ms; synthetic background CPU/I/O
work measured 1.625 ms p95. The first file-ranking call took 2.358 ms;
file-ranking p99 was 3.016 ms. Long-input model checks (268 KB prose and 1 MiB
prose/whitespace/combining marks) observed a maximum 0.047 ms main-thread update,
excluding rendering the full pasted text. Clipboard search p95 was 3.018 ms for
the full fixture. These are component/model/layout measurements, **not
keyboard-to-display latency**, a Spotlight indexing benchmark or a comparison
with another launcher.

Spotlight availability depends on the system index and exclusions. A generated
positive fixture did not appear in either the production query or macOS `mdfind`
on the measurement machine; metadata visibility alone did not establish index
searchability. Injected positive-result and cancellation tests passed, but they
cannot replace a positive real-index check on a target machine.

## Validation boundaries

The launcher is an `NSPanel` created with `.nonactivatingPanel`. It takes key
focus and prepares its native editor without requesting app activation or moving
the source app out of the foreground. Do not combine this presentation with a
process activation request: secure fields in Safari can reject that foreground switch.
The panel's key-window state determines keyboard ownership; visibility or the
foreground-app PID alone does not. The style is fixed at panel construction.

One check after the current callback can reassert an incomplete key-window
handoff. There are no waits, timers, event taps, Accessibility calls or Cue calls
that enable or disable Secure Event Input; macOS manages it during the handoff.
Dismissal, settings, a new invocation, key-window loss or a different foreground
app invalidates pending recovery. Normal typing does not
run this handshake. A visible launcher without key focus is reclaimed by its
shortcut without erasing its query. Existing field editors are not reassigned,
preserving the caret and IME composition. Settings use their own regular windows;
text conversion retains the original source regardless of Cue's active state.

Cue 主視窗使用建立時就設好 `.nonactivatingPanel` 的原生面板，直接取得鍵盤
焦點與輸入框，不切換前景 App，避免 Safari 安全輸入欄拒絕 App 切換的情況。
視窗可見或前景程序 ID 都不能單獨代表鍵盤焦點；以面板是否為 key window
判斷，不在顯示後動態更換視窗模式，也不混用 App 啟動要求。

當前回呼結束後只確認一次焦點，必要時補取一次，不加入固定等待、計時器、
鍵盤攔截、輔助使用要求，也不自行啟用或停用安全輸入；焦點交接時由 macOS
管理安全輸入狀態。關閉、設定、新的叫出操作、失去鍵盤焦點或切換 App
都會取消過期的補救；一般打字不執行這套流程。
可見但沒有焦點時，再按快速鍵會取回焦點並保留查詢；既有輸入編輯器不重設，
避免改動游標或中文組字。設定使用自己的正常視窗，文字轉換則保留來源 App。

`check-conversion-lifecycle.sh` includes injected key-focus timing, refusal,
cancellation and recovery alongside source-app preservation. These checks never
activate an app. Safari form fields (including password and autofill), immediate
typing/IME composition, repeated invocation, and deliberate
app switching still require a coordinated real-desktop check of the built app.

Relevant regression checks are CueCore XCTest and the isolated
`check-file-search.sh`, `check-file-search-service.sh`, `check-command-icons.sh`,
`check-launcher-keyboard.sh`, `check-adaptive-search.sh` and `check-clipboard.sh`
harnesses. They cover matching equivalence, Unicode/long input, cancellation,
stable shortcuts, progress, bounded icon work and timestamp boundaries.
`check-command-history.sh` covers recall, the first edit, IME ownership, original
action restoration after asynchronous file results, paging, deletion, pending
storage operations, and Finder action recall/cancellation in both languages.
`check-app-aliases.sh` covers app action menus, stable targets, keyboard equivalents,
IME ownership and alias editing in both languages without opening Finder.

Global hotkeys, cross-app focus, OS permission dialogs, visual composition and
perceived typing smoothness need a coordinated check of the optimized installed
app. Offscreen checks cannot establish those behaviors. Keep real-device and
simulated results separate when reporting release readiness.

### Input and history comparison

On **2026-11-09**, the same fixtures ran sequentially against unmodified
**1.2.0** and **1.3.0-beta.1**, using optimized Swift 6 builds on the same Apple
silicon Mac running macOS 27.2. Exact-query learning changes only the in-memory
ranking comparator. Clipboard target validation runs only after an explicit
selection, and window controls reuse the launcher's nonactivating focus coordinator.

| Offscreen workload | 1.2.0 p95 | 1.3.0-beta.1 p95 |
| --- | ---: | ---: |
| Native editor typing + layout | 3.209 ms | 2.052 ms |
| Typing at the end of 1–32 KiB input | 20.652 ms | 16.812 ms |
| 200 history recalls + native layout | 0.082 ms | 0.059 ms |
| File refinement + native layout | 0.183 ms | 0.181 ms |
| File completion + native layout | 0.147 ms | 0.145 ms |
| Rendering during long-input edits | 4.202 ms | 3.669 ms |
| App search: 1,000 apps, 256 aliases, maximum usage; uncached model | 1.570 ms | 1.571 ms |

Native-typing p99 was 9.981 / 4.557 ms; maxima were 27.628 / 15.329 ms.
No consistent regression was observed; differences between runs do not establish
an editing speedup. Each synchronous edit published one model update, with no
cleared matching file rows or unnecessary panel-height changes. These are warm,
offscreen component measurements, not physical input-to-display latency.

One candidate uncached-search sample took 22.910 ms wall time but only 0.900 ms
thread CPU time; the baseline also had a 19.572 ms wall / 0.967 ms CPU outlier.
This suggests scheduling or non-CPU waiting rather than increased ranking work.
A separate serial candidate rerun measured a 2.318 ms maximum for that empty-usage
workload. Maximum-usage uncached model p95 was 1.602 ms and maximum 1.955 ms on
the repeat, versus 1.571 / 2.858 ms on the first run. No timing guarantee follows
from these samples, and occasional OS scheduling delays remain possible.

Validation for this change included 296 core tests, 72 adaptive-search checks,
272 isolated clipboard checks, 62 text/paste lifecycle checks, 91 window-service
checks, and 145 window-mode checks in each language. Synthetic window tests include
40 consecutive numbered presets whose old positions constrain resizing. The CLT
source bundle passed relocation, signing, offline-data and 535 localization-pair
checks. The user separately confirmed HA ranking, direct clipboard paste and rapid
custom numbered window layouts on the installed 1.3.0-beta.1 build.

Local-signing changes are confined to build/install scripts and add no app startup
or interaction work. Nineteen isolated checks verify certificate-bound identity
continuity across different executable hashes, reject other signers, tampered
resources and weakened identity requirements, and fail closed on missing signing
configuration/keys. Both 1.3.0-beta.2 and beta.3 CLT builds passed relocated-bundle
checks. Their app code hashes differ while their identifier-and-certificate
requirements are identical. In coordinated testing on this Mac, the user granted
Accessibility to beta.2 once, then confirmed Option+M and a custom numbered preset
worked immediately after installing beta.3 without changing permission settings.
This establishes retention for that update, not a guarantee across OS resets,
different signing identities, or future security-policy changes.

The final 1.3.0 integration also measures native Chinese marked-text edits. An
isolated, interleaved editor comparison found that the custom TextKit 2 field
editor spent about 18.7 ms of thread CPU per 32 KiB edit, versus 10.8 ms for the
default field editor. Explicit TextKit 1 layout reduced that custom-editor case
to about 1.1 ms while keeping native composition. With the complete launcher and
new composition fixture, ordinary typing p50/p95/p99/max measured
0.255/3.679/12.704/21.603 ms; long-input p95 was 7.528 ms. Marked-text file-query
updates measured 0.502 ms p95, and completion rendering 0.274 ms p95 (14.828 ms
maximum). These remain offscreen samples with occasional spikes, not a guarantee
of physical input latency. The native keyboard/file-search checks cover caret
placement, wrapping, candidate navigation, composition commit/cancel and stale
results with this editor.

## 正體中文

搜尋使用已整理的記憶體索引、別名與使用分數；一般打字沒有 debounce 或人工等待。
檔案搜尋、圖示解碼、詞庫載入、網路及儲存工作都離開主要輸入路徑。檔案搜尋最多
九列，查詢途中保留仍符合的結果與面板高度；開始選取後固定編號，避免晚到結果
改變要執行的項目。圖示最多兩個解碼工作、256 個快取項目；剪貼簿資料與搜尋也
有固定上限。

學習只記錄成功的 App／指令選擇，保存在本機 JSON。明確別名及完整名稱仍優先；
其他部分符合的結果會先比較相同關鍵字的選擇分數，再看符合類別。一般使用頻率
仍只影響同一類別內的順序，使用分數有 14 天半衰期。
背景學習完成不會改動正在選擇的列表，下次輸入或叫出才採用新分數。要重設學習，
請結束 Cue 後只移除 `Search/usage.json`；設定與剪貼簿使用獨立儲存。

「指令歷史」與排序學習分開，預設記錄明確送出的輸入，包含 Google／GPT 文字與
檔名查詢；可在該功能中刪除或關閉。最多 200 筆／512 KiB 文字，上下鍵只讀記憶體
快照，存檔由背景處理，一般搜尋不掃描歷史。回看後的第一個修改只更新一次畫面，
不會把舊輸入或游標位置蓋回去；歷史頁每頁最多九列。

2026-11-09 在 macOS 27.2、同一台 Apple silicon Mac 依序對照 1.2.0 與
1.3.0-beta.1 的最佳化建置。原生打字 p95 為 3.209／2.052 ms，1–32 KiB
文字尾端編輯為 20.652／16.812 ms，歷史回看為 0.082／0.059 ms。1,000 個
App、256 個別名與最大學習紀錄下，未命中快取的搜尋 p95 為 1.570／1.571 ms。
沒有看到穩定退步，也不把單次差異解讀為新增功能加快了編輯。一次 22.910 ms
搜尋尖峰只使用 0.900 ms 執行緒 CPU 時間；另外序列重跑，同一情境最大值為
2.318 ms。這些是離屏元件量測，無法保證系統排程或按鍵到螢幕的延遲。

隔離測試與 Command Line Tools 建置通過；使用者另以已安裝的 1.3.0-beta.1
確認 HA 排序、剪貼簿直接貼上，以及快速連續執行自訂數字配置正常。

固定本機簽署只修改建置及安裝腳本，不增加 App 啟動或操作時的工作。19 項隔離
檢查確認不同執行檔雜湊仍維持相同憑證身分、拒絕其他簽署者與遭修改的資源，
並在設定或金鑰遺失時停止。1.3.0-beta.2 與 beta.3 的 CLT 建置及搬移後檢查皆
通過；兩版 App 的程式碼雜湊不同，但憑證身分要求相同。另於本機實測：使用者
為 beta.2 授權一次後，更新至 beta.3，未更動任何權限設定，就能直接使用
Option+M 與自訂數字配置。這確認了本次更新保留授權，不代表系統重設、切換簽署
身分或未來安全政策改變後也一定保留。

1.3.0 最後整合中文組字即時搜尋時，交錯的離屏欄位測試發現：自訂 TextKit 2
編輯元件在 32 KiB 文字每次編輯約用 18.7 ms 執行緒 CPU，系統預設欄位約
10.8 ms；改用 TextKit 1 後，自訂欄位降至約 1.1 ms，並保留原生組字。
完整啟動器的新測試中，一般打字 p50／p95／p99／最大值為
0.255／3.679／12.704／21.603 ms，長輸入 p95 為 7.528 ms；組字中的檔案查詢
更新 p95 為 0.502 ms，結果回來後的繪製 p95 為 0.274 ms、最大值 14.828 ms。
這些仍是有偶發尖峰的離屏元件量測，不是實體按鍵延遲保證；原生鍵盤與檔案搜尋
檢查涵蓋此編輯元件的游標、換行、選字、組字確認／取消及過期結果處理。
