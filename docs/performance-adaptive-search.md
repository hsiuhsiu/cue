# Adaptive search behavior and performance

Cue 0.4.0 learns from successful launcher actions.

## Ranking behavior

Text matching remains the first criterion: exact name, name prefix, word prefix,
substring, then initials/fuzzy matches. Within a matching category, ranking uses
the score for the exact normalized query and selected result, followed by the
result's overall score. Existing match penalties, positions, name lengths, names,
and paths break remaining ties. Commands keep their existing position before apps
and can learn their order relative to other matching commands.

Each successful selection adds one point. Older points decay with a 14-day
half-life, combining frequency and recency without a clock read on every key.
Decay is recalculated in the background when loading or recording usage, not on
every keystroke.
Queries are normalized for case, diacritics, width, and whitespace. Learning one
query does not automatically create preferences for its partial prefixes; general
usage can still influence those searches. A habit cannot introduce a result that
does not match or promote a weaker match above an exact match.

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
score dictionaries there, including decay math. The typing path looks up those
scores from memory once per matching result, then sorts; it never reads or writes
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

## Installed-app verification

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

Cue 0.4.0 支援依使用習慣排序。文字符合程度
仍優先；同一類別內，先看相同關鍵字的選擇習慣，再看帶有近期加權的使用
頻率。舊記錄的權重每 14 天減半。只記錄成功開啟的 App 或指令，不記錄
單純打字、取消、失敗操作或剪貼簿頁面內的內容與搜尋。

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
