# Adaptive search behavior and performance

Learning was introduced in Cue 0.4.0. The ranking rules below describe the current
source. Dated measurements and installed-app verification later in this document
are historical runs; the final section measures the current app-name and alias changes.

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

## Reproduce the benchmark

Run from the repository root, serially after other builds have finished:

```sh
./scripts/benchmark-adaptive-search.sh --baseline-ref 8b887b4 > /tmp/cue-search-before.json
./scripts/benchmark-adaptive-search.sh > /tmp/cue-search-after.json
```

The script compiles Swift 6 optimized (`-O`) modules with the selected Xcode
toolchain. `--baseline-ref` extracts only the pre-feature core and model sources
to a temporary directory, leaving the checkout untouched. Both modes run the
same benchmark source. Temporary synthetic files and build outputs are removed
afterward. No installed app inventory, real usage history, preferences, clipboard,
or application window is accessed.

The fixture contains 500 or 1,000 deterministic synthetic application names,
including English, Traditional Chinese, accented names, and overlapping prefixes.
Thirty queries exercise incremental typing, exact/prefix/substring matching,
initials, fuzzy matching, nonmatches, command matching, and whitespace folding.
Current code runs both empty usage and a saturated history: 512 result IDs,
256 queries, eight associations each. At 1,000 apps, the bounded history covers
512 of them. Fixture recording and snapshot creation are outside typing timings;
snapshot creation is reported separately.

The first query after adopting a replacement maximum snapshot is also timed,
including releasing the old model-owned score dictionaries and invalidating
30 cached query results. Snapshot construction itself remains outside that sample.

For each workload the benchmark reports a first core search, then 3,000 uncached
core searches, 3,000 model cache misses, and 3,000 model cache hits. Model misses
use a fresh model for each sequence of 30 distinct raw queries. Cache hits use
the same sequence after filling the cache. The actual `LauncherModel.setQuery`
implementation runs synchronously, including a small change callback that
consumes result counts. Only the icon-cache constructor is stubbed to exclude
AppKit image setup. Baseline and current code share this arrangement.

Each workload repeats with a utility queue continuously creating synthetic
1,000-app indexes and atomically writing a 4 MiB synthetic file. This provides
controlled CPU/I/O contention; it is not a reproduction of every real indexing
or clipboard workload. The JSON includes nearest-rank p50, p95, p99, maximum,
slowest query, first-search time, and the number of completed background cycles.
For each maximum wall sample it also reports thread CPU time; CPU counters are
read outside the timed wall interval to help distinguish extra synchronous work
from scheduling or other time spent off the CPU.
There are no timing pass/fail thresholds.

These measurements cover synchronous search/model work, not keyboard event
delivery, rendering, icons, activation, launching another application, or
end-to-end response time. Check invocation, immediate typing, selection, opening,
and asynchronous updates separately in the optimized app. No Raycast comparison
is implied.

## Observations, 2026-09-27

Apple silicon development Mac, macOS 27.0 (26A428), Xcode 27 / Apple Swift 6.4,
native optimized build. The final baseline and current binaries ran serially
after all compilation and other Cue tests had stopped. Values below are elapsed
milliseconds. Each core/model/cache row contains 3,000 samples. “Full” means the
bounded 512-result / 256-query / eight-association fixture, not real user history.

Without the synthetic background worker:

| Apps | Implementation | Core p50 | Core p95 | Core maximum |
| --- | --- | ---: | ---: | ---: |
| 500 | Before learning | 0.283 | 0.471 | 0.769 |
| 500 | Current, empty | 0.271 | 0.465 | 0.696 |
| 500 | Current, full | 0.278 | 0.474 | 3.294 |
| 1,000 | Before learning | 0.563 | 0.931 | 2.173 |
| 1,000 | Current, empty | 0.560 | 0.964 | 55.113 |
| 1,000 | Current, full | 0.550 | 0.930 | 1.409 |

| Apps | Implementation | Model cache-miss p50 | p95 | Maximum | Cache-hit p95 |
| --- | --- | ---: | ---: | ---: | ---: |
| 500 | Before learning | 0.285 | 0.472 | 1.362 | 0.000500 |
| 500 | Current, empty | 0.275 | 0.474 | 1.375 | 0.000417 |
| 500 | Current, full | 0.278 | 0.472 | 0.773 | 0.000417 |
| 1,000 | Before learning | 0.576 | 0.971 | 19.948 | 0.000500 |
| 1,000 | Current, empty | 0.560 | 0.966 | 2.753 | 0.000459 |
| 1,000 | Current, full | 0.551 | 0.935 | 2.931 | 0.000417 |

With the synthetic indexing/writing worker:

| Apps | Implementation | Core p95 | Core maximum | Model cache-miss p95 | Model maximum |
| --- | --- | ---: | ---: | ---: | ---: |
| 500 | Before learning | 0.484 | 0.919 | 0.487 | 1.026 |
| 500 | Current, empty | 0.473 | 0.618 | 0.477 | 0.713 |
| 500 | Current, full | 0.488 | 9.670 | 0.483 | 0.620 |
| 1,000 | Before learning | 1.073 | 2.919 | 1.009 | 2.090 |
| 1,000 | Current, empty | 1.029 | 1.302 | 0.947 | 1.292 |
| 1,000 | Current, full | 0.956 | 4.480 | 0.961 | 2.204 |

The first core query in each fresh process took 0.748 ms before learning and
0.430 ms with current code. These exclude constructing the app index and history.
Creating a full score snapshot took 0.641 / 0.474 ms for the 500 / 1,000-app
fixtures and occurs outside the typing path. The first model query adopting a
new full snapshot, including release of the previous scores and cached results,
measured p50 / p95 / maximum of **0.300 / 0.330 / 0.375 ms** for 500 apps and
**0.593 / 0.719 / 0.803 ms** for 1,000 apps (100 samples each).

An initial implementation regressed dense-match sorting: 1,000-app core p95
rose from about 0.95 ms to 2.29 ms even with empty history. Query-specific
measurements isolated `c`, `s`, and `t`: their medians rose from roughly
0.69–0.80 ms to 1.88–2.47 ms, while sparse queries changed much less. The fix
sorts small scalar candidates containing app indices, ranks, and scores instead
of repeatedly copying the larger application values and their reference-counted
strings/arrays. Current full-history medians for `c` / `s` / `t` are
0.510 / 0.553 / 0.628 ms. The optimization benefits unlearned searches too.

The large maxima were investigated rather than dropped: the current empty-history
55.113 ms wall sample used only **1.953 ms of thread CPU**, the previous model's
19.948 ms sample used **1.407 ms**, and the current full-history background
9.670 ms sample used **0.348 ms**. Most elapsed time in those outliers was spent
off the measured thread's CPU; they are not 20–55 ms of synchronous ranking work.
The exact external scheduling/wait cause was not isolated. Earlier bracketing
runs also showed isolated long wall samples in both implementations. These tails
remain a reason to assess real input and drawing separately, not a promise that
every interaction stays below a fixed latency.

The full-history p95 remains approximately at the baseline in this workload.
Small differences between runs, especially sub-microsecond cached-query timings,
should not be treated as universal improvements. The measurements support the
bounded in-memory design and the sort fix; they do not establish smoothness on
every Mac or replace optimized app interaction checks.

## Installed-app verification from 0.4.0

The final optimized app was installed at `~/Applications/Cue.app` and exercised
on this Mac. Typing `c` initially placed Calculator eighth. Opening it with
Command-8 promoted it to first on the next invocation, and the same order survived
a normal quit and relaunch. Continuous typing and backspacing, arrow selection,
empty-query behavior, Option-Space invocation with input focus, and Command-comma
Settings focus were checked. Launch at login remained enabled and the language
remained Follow System. These native UI checks confirm behavior; they do not
measure frame delivery or establish a numeric end-to-end latency.

The final Xcode Release suite passed 94 tests. Optimized AppKit harnesses passed
31 adaptive-search, 124 keyboard, and 170 system-action checks. System actions in
the harness were injected; the Mac was never put to sleep or locked.

## 正體中文摘要

Cue 從 0.4.0 開始支援依使用習慣排序。以下是目前原始碼的規則，後面的
日期、量測數字與已安裝 App 驗證是歷史紀錄，尚未量測這次 App／指令
合併排序的修改。App 的文字符合程度仍優先；同一類別內，先看相同
關鍵字的選擇習慣，再看帶有近期加權的使用頻率。指令也會在指令群組內
依使用習慣排序。

App 與指令兩個列表依序合併，只比較各自下一個結果對「完全相同且已
正規化的關鍵字」的分數；分數相同時指令優先，不改變各群組內部的順序。
一般使用頻率本身不會改變 App 與指令之間的順序。例如 `it` 會碰巧符合
`traditional` 中間的字元，但成功選擇 iTerm2 後，下次叫出就能排在正體
轉換指令前面。沒有固定的最低操作次數，另一個結果沒有該關鍵字的記錄時，
一次成功選擇即可。明確設定的完整指令別名仍優先，數值答案也保留在最前面。
較弱的 App 符合結果不會超過完全符合的 App。

舊記錄的權重每 14 天減半。只記錄成功開啟的 App 或指令，不記錄單純
打字、取消、失敗操作或剪貼簿頁面內的內容與搜尋。

資料只有本機保存，最多 512 個結果、256 個關鍵字、每個關鍵字八個結果。
檔案是可讀的 JSON，位於上述路徑。關閉 Cue 後只刪掉 `Search/usage.json`
即可重設學習，不影響設定或剪貼簿。搜尋只讀取預先準備的記憶體分數，
載入、權重計算與儲存都在背景執行；背景記錄完成時不會直接改動正在選擇
的列表，新的輸入或下次叫出 Cue 才會採用。

上方指令會使用合成的 500／1,000 個 App，分別比較舊版、無使用記錄、
滿容量使用記錄，以及背景 CPU／檔案寫入壓力下的搜尋與快取耗時。它不讀取
真實剪貼簿或使用記錄。這些是搜尋與 model 的耗時，不等於按鍵到畫面更新
的端到端延遲；完整體感仍需另外用最佳化版本實際操作驗證。

2026-09-27 在 macOS 27／Xcode 27 的最佳化版本上，1,000 個 App 的搜尋
p95 從原本約 **0.931 ms** 到滿容量學習記錄約 **0.930 ms**；500 個 App
則從 **0.471 ms** 到 **0.474 ms**。開發過程曾發現大量符合結果時排序
變慢，改成排序小型索引與分數後已消除。測試也保留並檢查偶發的長耗時，
例如 55.113 ms 的經過時間中只有 1.953 ms 是該執行緒實際使用 CPU；
這些數字不代表所有畫面互動都能保證沒有延遲。

最後也安裝到本機實際驗證：用 ⌘8 開啟 Calculator 後，下一次搜尋 `c`
會移到第一個，正常關閉並重開 Cue 後仍保留；連續輸入、刪字、上下選取、
空白搜尋、⌥Space 叫出與 ⌘, 設定焦點都正常，登入啟動與跟隨系統語言
設定也保留。這是功能操作驗證，不是逐幀延遲量測。

## Chinese conversion development follow-up, 2026-09-27

Adding the conversion commands and configurable aliases does not load conversion
dictionaries or access other apps while searching. Saved aliases are validated
and normalized once; search compares the normalized query with those cached
strings. Dictionary loading and selected-text conversion begin only on execution.

The same optimized, synthetic 30-query benchmark was rerun on this Mac with the
conversion changes. The table compares the recorded 0.4.0 measurements above
with this development run, using maximum usage history. Values are milliseconds;
each core/model row contains 3,000 samples. These are separate runs, not a fresh
paired before/after experiment, so differences cannot be attributed solely to
the added commands.

| Apps | Background worker | Core p95, 0.4.0 → development | Model miss p95, 0.4.0 → development | Development core / model maximum |
| --- | --- | ---: | ---: | ---: |
| 500 | Off | 0.474 → 0.573 | 0.472 → 0.552 | 20.195 / 1.709 |
| 500 | On | 0.488 → 0.528 | 0.483 → 0.512 | 1.118 / 0.675 |
| 1,000 | Off | 0.930 → 0.968 | 0.935 → 0.994 | 1.176 / 30.654 |
| 1,000 | On | 0.956 → 0.987 | 0.961 → 0.981 | 1.218 / 1.180 |

Across empty and maximum history, model cache-hit p95 was 0.000417–0.000458 ms.
The 20.195 ms core and 30.654 ms model maxima used 0.639 and 1.242 ms of thread
CPU respectively; most elapsed time was off that thread's CPU, with the external
cause still unisolated. This run preserves those tails and the higher 500-app
p95 rather than claiming zero overhead. The existing query set does not time
`st`/`ts` specifically, dictionary loading, conversion, clipboard restoration,
Accessibility, input delivery, or rendering. Conversion-engine measurements
are documented separately in [dictionary data and performance](chinese-conversion-data.md).

### 正體中文補充

新增簡繁轉換指令與自訂別名後，搜尋只比較已整理好的記憶體字串，不會載入
轉換詞庫或存取其他 App；實際執行指令才開始處理選取文字。

上表以相同的最佳化版本、合成 30 組查詢及滿容量使用記錄，比較先前 0.4.0
與這次開發版；每格有 3,000 次取樣，單位為毫秒。兩次量測不是同時重新做的
成對實驗，不能把差異完全歸因於新增指令。1,000 個 App 的 model 未命中快取
p95 為 0.994 ms，背景工作時為 0.981 ms；500 個 App 的 p95 增幅較大，已
如實列出。快取命中的 p95 介於 0.000417–0.000458 ms。

最長的 20.195／30.654 ms 樣本實際使用該執行緒 CPU 的時間分別為
0.639／1.242 ms，其餘等待的外部原因尚未確認。這不是零成本或無延遲的保證；
此測試也不包含 `st`／`ts` 專項、詞庫載入、文字轉換、剪貼簿還原、輔助使用、
按鍵傳遞或畫面繪製。轉換引擎的量測另見[詞庫資料與效能](chinese-conversion-data.md)。

## App/command preference follow-up, 2026-09-29

The optimized benchmark was rerun serially after compilation and tests completed,
using the current source (including inline unit conversion and the query-specific
app/command merge). Each core and model row below contains 3,000 samples; values
are milliseconds. These are current measurements, not a paired before/after
comparison of the merge alone.

| Apps | Usage | Background worker | Core p95 | Model miss p95 | Core / model maximum |
| --- | --- | --- | ---: | ---: | ---: |
| 500 | Maximum | Off | 0.490 | 0.498 | 0.565 / 0.683 |
| 500 | Maximum | On | 0.507 | 0.514 | 0.599 / 0.962 |
| 1,000 | Maximum | Off | 0.957 | 0.953 | 1.593 / 1.523 |
| 1,000 | Maximum | On | 0.995 | 0.986 | 1.990 / 2.022 |

The 1,000-app empty-history run also had a 16.038 ms core wall sample with
0.705 ms of thread CPU and an 8.625 ms model sample with 1.689 ms of CPU. As in
earlier runs, most elapsed time in those samples was off the measured thread;
the external cause remains unisolated. They are retained rather than treated as
zero-delay evidence. This benchmark does not measure input delivery or drawing.
The Release core suite passed 217 tests, and the isolated AppKit adaptive-search
harness passed 52 checks, including the `it`/iTerm2 collision and persistence.
The optimized app was installed and reopened on this Mac. Its existing `it`
history placed iTerm2 first, ahead of Traditional Chinese conversion, without
resetting history or adding a test launch to the user's data.

### 正體中文補充

上述是 2026-09-29 在其他建置與測試結束後，依序測量目前原始碼的結果，
每格 3,000 次取樣，單位為毫秒；包含單位換算與這次的 App／指令合併，
不是針對合併變更單獨做的成對比較。滿容量學習記錄下，1,000 個 App 的
搜尋與 model 未命中快取 p95 約 0.95–1.00 ms。無學習記錄時也保留了
16.038／8.625 ms 的長樣本，實際執行緒 CPU 為 0.705／1.689 ms，
其餘等待原因尚未隔離；這些數字不代表按鍵到畫面更新保證沒有延遲。
Release 核心測試 217 項與原生整合檢查 52 項通過，包含 `it` 選擇 iTerm2
後跨過正體轉換指令，以及重新載入後保留排序。
本機安裝最佳化版本並重開後，也確認既有 `it` 紀錄讓 iTerm2 排第一；
沒有重設學習記錄，也沒有額外開啟真實 App 來增加測試次數。


## App names and aliases, 2026-09-30

Automatic name forms are deduplicated and tokenized during the background app
scan. Search compares those prepared forms and returns each app only once.
Explicit aliases use a separate pre-normalized exact/prefix comparison. Alias
preferences are limited to 256 apps, keyed by bundle identifier (or standardized
path for bundles without an identifier), and read outside the typing path.
Saving/removing an alias replaces the in-memory app values and invalidates cached
queries. It does not erase learned usage or reread application bundles.

Optimized native builds on this Apple silicon Mac used the same deterministic
500/1,000-app benchmark and 3,000 samples per model workload. The comparison
baseline was commit `4ca7aad` (Cue 0.8.0 with the published update feed). Baseline,
current single-name, and expanded-name binaries ran sequentially after compilation.
The expanded fixture gives 25% of apps two additional names and fills all 256
custom-alias slots. Ranges below cover empty/maximum usage and with/without the
synthetic background indexing/writing worker, for **1,000 apps**:

| Fixture | Model cache-miss p95 | Highest model wall sample | Thread CPU time for that sample |
| --- | ---: | ---: | ---: |
| Cue 0.8.0, original names | 0.972–1.003 ms | 14.785 ms | 2.132 ms |
| Current code, same names | 0.947–0.982 ms | 7.669 ms | 1.712 ms |
| Current code, extra names and aliases | 1.601–1.682 ms | 28.823 ms | 2.632 ms |

Current model cache-hit p95 was at most 0.000833 ms in these runs. Extra names
have a measurable uncached cost; the original single-name workload did not
regress in this run. The largest wall samples include considerable time not
spent executing on the measured thread. These results do not establish an
absence of input stalls or include event delivery, rendering, or window focus.

Reproduce the current fixtures, serially:

```sh
./scripts/benchmark-adaptive-search.sh
./scripts/benchmark-adaptive-search.sh --app-aliases
```

The optimized installed app was also exercised with the actual Visual Studio
Code bundle: `vs`/`visual` matched Code, Return opened the app, Command+E and the
selected row's button opened a focused alias editor, conversion-alias collisions
showed an error, clearing/saving removed the alias, and `vs` persisted across a
normal quit/relaunch. Core tests (227), existing native keyboard checks (206),
adaptive-search checks (52), and the new app-alias checks (78) passed. The new
checks include a menu opened before rows change, so a completed background
refresh cannot redirect its edit action to a different app. Release packaging
runs these checks through `scripts/check-app-aliases.sh`.
