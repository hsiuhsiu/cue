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
