# Icon retrieval profiling

Measured on the development Mac on 2026-09-26, arm64, macOS 26.6.2 (25G83),
using Xcode's Swift toolchain and the 135 applications found by `AppIndex.scan()`.
These measurements establish the cost of synchronous icon work; they do not
measure keyboard-to-display latency or compare Cue with Raycast.

## Results

Every number below is milliseconds for the entire group, not per icon. The
first 20 applications are the first 20 results of the empty alphabetical search.
Each group starts in a separate process. OS, filesystem, and icon-service caches
are **not** flushed. The Debug benchmark ran after the optimized benchmark, so
the rows must not be interpreted as a compiler-optimization comparison.

| Build | Apps | First retrieval | First rasterization | Warm retrieval | Warm rasterization | App cache lookup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `-O` | 20 | 39.71 | 38.04 | 38.27 | 15.02 | 0.0047 |
| `-O` | 135 | 186.70 | 68.07 | 123.76 | 60.70 | 0.0283 |
| `-Onone` | 20 | 16.56 | 19.43 | 15.53 | 8.14 | 0.0093 |
| `-Onone` | 135 | 101.77 | 58.65 | 114.72 | 54.92 | 0.0626 |

“Retrieval” calls `NSWorkspace.shared.icon(forFile:)` and stores the returned
image. “Rasterization” draws each returned image into a fresh 64 × 64 bitmap,
equivalent in pixel count to a 32-point icon at 2×. This includes bitmap/context
allocation, representation selection, any deferred decode, and rasterization.
It is a CPU-path probe, not an exact reproduction of SwiftUI's renderer.
“App cache lookup” reads existing images from a dictionary and accesses image
size; 1,000 batches are averaged and rendering is excluded.

## What this establishes

The previous row-building path called `LauncherModel.icon(for:)` synchronously
on the main actor. On the first miss it requested an icon from `NSWorkspace`;
the row then gave that `NSImage` to SwiftUI, which could incur deferred image
work. A refresh also emptied the app's icon cache.

The icon API consumed roughly 0.7–1.8 ms per image at the median in these runs.
Even a warm system icon service did not make repeated requests as cheap as an
app dictionary hit. Moving cache misses and preparing small raster images
away from UI work therefore removes a measured source of main-thread stalls.
Refreshing the index also prepares the initial results' icons in the background.

The first 20 benchmark is a repeatable sample, **not** a claim that a frame
renders 20 icons. The previous lazy list may build fewer visible rows. These
figures should not be reported as an end-to-end speedup or perceived delay;
that would require live input and presentation instrumentation.

## Reproduce

```sh
bash scripts/benchmark-icons.sh
CUE_BENCHMARK_OPTIMIZATION=-Onone bash scripts/benchmark-icons.sh
```

The script compiles the core and probe in a temporary directory, creates no
windows, and leaves the application's normal build directory untouched. It
prints one JSON report per fresh process, including per-icon median, p95,
maximum, and total timings. Results depend on the installed apps, competing
work, display resources, and system caches; rerun when assessing another Mac.


## Built-in command artwork (2026-09-27)

Cue 0.5.0 replaces per-row SF Symbol requests for built-in commands
with eight matching white tiles and blue outline icons. Core Graphics and Core Text render both
28-pixel and 56-pixel representations once on a detached worker. Main-actor
publication wraps the completed bitmaps and updates only matching existing
cells; it never reloads the table, changes selection, or rebuilds search results.
Application-index invalidation leaves this separate command cache intact.

`./scripts/check-command-icons.sh --preview .build/command-icons-preview.png`
passed 96 checks on the development Mac using Swift 6.4 / Xcode 27 in an optimized
build. It covers background rendering, both scales, distinct artwork, cache
identity, invalidation during and after preparation, and delayed callbacks after
the visible query changes. The real launcher view retained its field editor,
selection, row objects, and ordering, with no model notification or table reload.

For 100 batches of 800 cached lookups (80,000 verified identity hits), the median
batch average was 174.4 ns per lookup, p95 185.7 ns, and maximum 215.4 ns. These are
in-process cache lookup costs, not keystroke-to-display latency. Normal startup
may briefly show the existing placeholder while the background worker prepares
artwork; it does not wait for that worker before accepting input.

The installed Release build was also inspected through its native UI: screen
search, conversion results, typing, keyboard selection, and Command-comma focus.
The generated review sheet checks actual 28-pixel artwork and a separately
rendered 4× enlargement on light and dark backgrounds; it does not stretch a
small bitmap. The lighter revision uses solid blue strokes on white, extra
internal spacing, left-side arrows pointing toward the conversion target, and
diagonal 繁/简 characters with independent left/right return arrows and a larger
upper-right gear for feature settings. No display-off, lock, or system-sleep transition was
triggered during these checks.
