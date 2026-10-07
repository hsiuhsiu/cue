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
substring, then initials/fuzzy matches. Within a matching category, ranking uses
the score for the exact normalized query and selected result, followed by the
result's overall score. Existing match penalties, positions, name lengths, names,
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
scores from memory to sort within each list and merge matching apps and commands;
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

Measured **2026-10-04** on the development **Apple silicon Mac, macOS 27.0
(26A428), Xcode 27 / Swift 6.4**, using optimized native builds, serial synthetic
workloads and offscreen native views. These numbers are a measured reference for
that source and machine, not a latency guarantee for future builds or other Macs.

| Workload | Median | p95 |
| --- | ---: | ---: |
| App search: 1,000 apps, extra names, 256 aliases, maximum usage; uncached model | 0.332 ms | 1.571 ms |
| File ranking: 384 `report` candidates → nine rows | 1.489 ms | 2.016 ms |
| File refinement + native layout | 0.172 ms | 0.185 ms |
| File completion + native layout, unchanged matching results | 0.133 ms | 0.144 ms |
| Unchanged clipboard expiration: 500 entries / 4 MiB | 0.0058 ms | 0.0114 ms |

App-search p99 was 1.607 ms; Unicode queries dominated the tail. The first file
ranking call took 6.034 ms; file-ranking p99 was 2.435 ms. Long-input model checks (268 KiB prose and 1 MiB
prose/whitespace/combining marks) observed a maximum 0.051 ms main-thread update,
excluding rendering the full pasted text. Clipboard search p95 was approximately
3 ms for the full fixture. These are component/model/layout measurements, **not
keyboard-to-display latency**, a Spotlight indexing benchmark or a comparison
with another launcher.

Spotlight availability depends on the system index and exclusions. A generated
positive fixture did not appear in either the production query or macOS `mdfind`
on the measurement machine; metadata visibility alone did not establish index
searchability. Injected positive-result and cancellation tests passed, but they
cannot replace a positive real-index check on a target machine.

## Validation boundaries

Relevant regression checks are CueCore XCTest and the isolated
`check-file-search.sh`, `check-file-search-service.sh`, `check-command-icons.sh`,
`check-launcher-keyboard.sh`, `check-adaptive-search.sh` and `check-clipboard.sh`
harnesses. They cover matching equivalence, Unicode/long input, cancellation,
stable shortcuts, progress, bounded icon work and timestamp boundaries.
`check-command-history.sh` covers recall, the first edit, IME ownership, original
action restoration after asynchronous file results, paging, deletion, and pending
storage operations in both languages.

Global hotkeys, cross-app focus, OS permission dialogs, visual composition and
perceived typing smoothness need a coordinated check of the optimized installed
app. Offscreen checks cannot establish those behaviors. Keep real-device and
simulated results separate when reporting release readiness.

### Command history measurement

On **2026-10-07**, an optimized build using standalone **Command Line Tools /
Swift 6.4** on the same Mac measured 200 synthetic recalls with native row layout:
median **0.039 ms**, p95 **0.044 ms**, p99 **0.061 ms**, maximum **3.929 ms**.
File refinement/layout in that run had a **0.171 ms** median and **0.191 ms** p95;
each synchronous edit still published one model update. The harness includes the
first recall but uses an already constructed native view. These are offscreen
component timings, not input-to-display latency or a full-history-page benchmark.

## 正體中文

搜尋使用已整理的記憶體索引、別名與使用分數；一般打字沒有 debounce 或人工等待。
檔案搜尋、圖示解碼、詞庫載入、網路及儲存工作都離開主要輸入路徑。檔案搜尋最多
九列，查詢途中保留仍符合的結果與面板高度；開始選取後固定編號，避免晚到結果
改變要執行的項目。圖示最多兩個解碼工作、256 個快取項目；剪貼簿資料與搜尋也
有固定上限。

學習只記錄成功的 App／指令選擇，保存在本機 JSON；同一符合類別先看相同
關鍵字的選擇，再看帶有 14 天半衰期的使用分數。明確別名及完全符合仍優先。
背景學習完成不會改動正在選擇的列表，下次輸入或叫出才採用新分數。要重設學習，
請結束 Cue 後只移除 `Search/usage.json`；設定與剪貼簿使用獨立儲存。

「指令歷史」與排序學習分開，預設記錄明確送出的輸入，包含 Google／GPT 文字與
檔名查詢；可在該功能中刪除或關閉。最多 200 筆／512 KiB 文字，上下鍵只讀記憶體
快照，存檔由背景處理，一般搜尋不掃描歷史。回看後的第一個修改只更新一次畫面，
不會把舊輸入或游標位置蓋回去；歷史頁每頁最多九列。

2026-10-07 使用 Command Line Tools／Swift 6.4 的最佳化建置，在同一台 Mac 測得
200 次合成歷史回看與原生列排版中位數 0.039 ms、p95 0.044 ms、p99 0.061 ms，
最大 3.929 ms。包含第一次回看，但原生 View 已建立；這是離屏元件時間，並非
按鍵到螢幕的延遲，也不是整個歷史管理頁的量測。

上表是指定日期、機器與合成工作負載的元件量測，不能當成未來版本、其他 Mac 或
按鍵到畫面的延遲保證。依序執行上列命令可重新測量；保留第一次使用與最慢樣本，
不要只看平均值。真實全域快捷鍵、跨 App 焦點、系統授權及可見畫面仍需另行協調
實機測試；測試不應打斷日常使用或讀取個人資料。
