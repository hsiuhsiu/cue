# Clipboard history search benchmark

Run from the repository root:

```sh
bash scripts/benchmark-clipboard.sh > /tmp/cue-clipboard-benchmark.json
```

The script compiles CueCore and the probe with Swift 6 and `-O`, using the stable
Xcode installation when available. Build products and a synthetic history file
are created in temporary directories and removed afterward. It never accesses
the system clipboard or Cue's real history. No application window is opened.

## Workload and timing

The fixture fills the current capacity: **500 entries, exactly 4,194,304 bytes
(4 MiB) of UTF-8 text**. It mixes English, Traditional Chinese, accented and
full-width characters, and `.invalid` example links. JSON generation and writing
are outside the measured load. The store loads once, with a fixed clock and
unlimited retention; the probe verifies that no entries or text bytes were lost.

Then 100 queries run sequentially, without warm-up queries: English/Chinese
matches and misses, groups, URLs, whitespace, case/width/diacritic folding, and
empty queries. Each sample measures `MainActor await → ClipboardStore actor →
return`, including query normalization, actor scheduling, searching, and result
construction. JSON includes nearest-rank percentiles, per-category timings,
result counts, and the first ten samples.

The separate first-load number includes file reading, JSON decoding, normalization,
preview creation, and store validation. “First load” means a fresh process/store;
the file was just generated, and OS/filesystem caches are **not** flushed. These
are not keyboard-to-display or complete clipboard-interaction measurements:
capture, UI rendering, selection, copy, focus, and window invocation are excluded.

## Observations, 2026-09-26

Development Mac, arm64, macOS 26.6.2, Xcode's Swift 6 toolchain, optimized native
build. Both runs used the same synthetic text and queries. Values are milliseconds.
Competing build activity and OS scheduling can affect individual samples; these
are diagnostic measurements, not timing assertions or guarantees for every Mac.

| Search implementation | Median | p95 | p99 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Cached normalized String with `contains` | 70.000 | 143.097 | 149.589 | 199.508 |
| Cached normalized UTF-8 with native `memmem` | 2.827 | 4.161 | 4.476 | 5.560 |

The optimized implementation's separate first load took **453.678 ms**, versus
386.103 ms for the baseline. Search p95 dropped about 34×. Both runs returned
the same result counts. The new cache uses canonical Unicode composition after
case/diacritic/width normalization; query normalization happens once, and matching
does not allocate per entry. The byte cache replaces the cached normalized String.
Core tests cover canonical-equivalent spellings, emoji, Chinese, and URL matching.

The tracked scripts preserve the measured workload. Re-run on the target Mac when
evaluating later changes, preferably after unrelated builds finish. Assess actual
typing and presentation separately; fast core search alone does not prove a
smooth interface or establish a comparison with Raycast.
