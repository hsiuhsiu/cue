# Core search benchmark

This benchmark measures `LauncherResult.search` over an existing in-memory index.
It includes command matching and ranking. It does **not** measure keyboard input,
window activation, icon loading, drawing, or launching another application.

Run from the repository root with the stable Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -swift-version 6 -O Sources/CueCore/*.swift scripts/benchmark-search.swift \
  -o /tmp/cue-search-benchmark-release
/tmp/cue-search-benchmark-release
```

Replace `-O` with `-Onone` to measure unoptimized Debug code. Run configurations
serially, outside a build/test run; scheduling contention can dominate these
submillisecond measurements.

The script scans installed applications once, then creates a deterministic set
of 1,000 synthetic applications. Each data set runs 30 queries (incremental
typing, exact/prefix/substring matches, initials, fuzzy matches, Chinese,
diacritics, misses, and normalized whitespace). Twenty warm-up repetitions
precede 100 measured repetitions, for 3,000 timed searches per data set. The
checksum consumes result counts. The query list and synthetic names are in the
script. Empty-query sorting is excluded; the UI caches those results.

## Observations, 2026-09-26

macOS 26.6.2, Apple Swift 6.3.3 from Xcode. The unchanged baseline and final
implementation were compiled with `-O` and run sequentially on the same 134
installed applications, after other compilation work finished. These are CPU
measurements in milliseconds, not keyboard-to-display latency guarantees.

| Index | Before p50 | After p50 | Before p95 | After p95 |
| --- | ---: | ---: | ---: | ---: |
| Installed, 134 apps | 0.123 | 0.071 | 0.281 | 0.265 |
| Synthetic, 1,000 apps | 1.608 | 0.634 | 2.498 | 1.953 |

The changes cache immutable word suffixes and initials at indexing time, avoid
allocating a new word-tail String per candidate per keystroke, and normalize
each launcher query once. Suffix strings are allocated once when indexing.
Ranking categories and deterministic path tie-breaking are unchanged. Both
runs produced the same result-count checksum (467160).

The submillisecond core times for the actual index mean that these improvements
alone cannot explain or resolve perceived launcher delay. Cue also moves icon
retrieval and rasterization off the main thread, prebuilds the native input
field, reuses table rows, caches empty/recent queries, and ships a Release build
for daily use. See [icon profiling](performance-icons.md) for the separate
synchronous-icon measurements. No direct Raycast comparison was performed.

Correctness tests cover Unicode and emoji, word prefixes, fuzzy initials,
whitespace normalization, and stable ordering for dense ties. Benchmarks are
diagnostic; noisy wall-clock thresholds are deliberately not unit-test assertions.

## Long pasted input, 2026-10-03

Application and command matching now accepts at most 1,024 UTF-8 bytes per query.
Longer input bypasses matching, numeric parsing, normalization, and the query
cache, while preserving the original text for explicit Google/GPT actions.
This is a search-work bound, not a truncation of the user's input. Each action
still enforces its own input requirements, including GPT's 32 KiB limit.

The model checks whitespace over a bounded prefix synchronously. A very long
whitespace prefix is classified by a cancellable worker; a generation check
prevents that worker from changing newer input. Ordinary short input does not
wait for a task or debounce. The native view and action shortcuts reuse the
model's classification.

The optimized `scripts/benchmark-long-query.sh` fixture uses 1,000 synthetic apps.
Each case measures 12 distinct queries. The same fixture ran serially against `a8e5f1a` and
the revised source on macOS 27 / Xcode 27:

| Synthetic input | Before median | After median | After maximum |
| --- | ---: | ---: | ---: |
| 268 KB prose | 67.180 ms | 0.001 ms | 0.026 ms |
| 1 MB prose | 260.783 ms | 0.001 ms | 0.001 ms |
| 1 MB whitespace | 42.969 ms | 0.026 ms | 0.323 ms |
| 1 MB combining marks in one grapheme | 52.693 ms | 0.001 ms | 0.001 ms |

These measure synchronous model-update wall time, excluding background
classification completion, AppKit text editing, rendering, OS input delivery,
and external actions. They do not establish an input-to-display latency bound.
Run `./scripts/benchmark-long-query.sh --baseline-ref a8e5f1a` followed by
`./scripts/benchmark-long-query.sh` to reproduce, with other builds stopped.

A separate post-change run of `./scripts/benchmark-adaptive-search.sh --app-aliases`
checked ordinary short queries over 1,000 synthetic apps with aliases and extra
names. Across empty/full learning history and idle/synthetic-background cases,
uncached model-update p95 was 1.611–1.664 ms; cache-hit p95 stayed below 0.001 ms.
The largest wall-time outlier was 25.013 ms (2.303 ms thread CPU), so scheduling
stalls remain outside a worst-case guarantee. The offscreen native text-action
check also passed, measuring p95 0.082 ms / p99 0.129 ms over 500 edits; this
measures that view update only, not full application search or visible frames.
