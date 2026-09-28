# Engineering principles

## Highest priority: fast, simple, and lightweight

- Cue's most important product and engineering principle is immediate responsiveness. Keep the app extremely fast, simple, and lightweight; make every reasonable effort to eliminate perceptible interaction delay. Evaluate every feature, dependency, and architectural choice against this principle.
- Typing must feel continuous and instantaneous. Perceptible stutter, dropped keystrokes, delayed focus, or lag in search results and keyboard selection are defects, not acceptable tradeoffs for added features.
- Keep the input and rendering paths minimal. Move expensive work, filesystem access, indexing, and image loading or decoding off the main thread. Reuse views and cached work where useful, and avoid unnecessary allocations, redraws, and resource consumption.
- Do not introduce artificial waits, animations that delay interaction, or debounce delays in the core typing and navigation flow. Acknowledge user actions immediately.
- Work that genuinely takes time may run asynchronously with a clear indication that it is in progress. Such work must keep typing and navigation responsive; a progress indicator never excuses a blocked interface.
- Validate changes to interaction paths in an optimized build through actual use and appropriate measurements. Assess invocation, immediate typing, search updates, selection, and launching, including first use and background work. Fast average computation times alone do not establish a smooth experience; investigate visible stalls and latency spikes.

## Implementation

- Cue is a native macOS application. Prefer Swift, SwiftUI, AppKit, and system APIs.
- Avoid dependencies unless they provide clear value.
- Optimize for keyboard-first interaction and low latency.
- Keep core logic testable outside the UI.
- Do not prematurely create generic or plugin abstractions.
- Future product ideas are recorded in `docs/future-directions.md`. Treat them as context for later decisions, not authorization to implement them or add dependencies before requested.
- Keep feature-specific settings in that feature's own page or actions (for example, clipboard retention inside Clipboard History). Reserve the main Settings window for Cue-wide options so it stays small and easy to navigate.
- Do not add networking, telemetry, analytics, or cloud services unless explicitly requested.
- All current and future network requests made by Cue must honor `NetworkPolicy.allowsNetwork`, including manual API actions, scheduled work, embedded remote content, downloads, retries, and dependency-owned workers. Source builds and missing defaults must deny Cue-owned network access; release packaging may enable the initial default only in the staged bundle. Always preserve an explicit user choice. Disabling access must prevent new work and cancel cancellable in-flight work without blocking typing; test offline startup and transitions, not just disabled buttons. Keep Chinese conversion fully offline with the same bundled dictionaries and conversion quality. See `docs/network-policy.md` for scope and cancellation limits.
- Explicit Google search handoffs to an external browser use the feature-local browser-search setting, enabled by default and independent of Cue's own network policy. Check that setting immediately before handoff, never send queries merely while typing, and exclude web-search query text from usage learning. Keep the system default browser fixed and add other browsers only by explicit user choice. Discover browsers in the background when feature settings open or Add Browser is chosen, show candidates only in the add interface, and never discover on the typing path. Future Cue-owned API calls must not bypass the global network policy by silently opening a browser or delegating the request elsewhere.
- Run relevant tests and build checks before declaring a task complete.
- Write release notes in both English and Traditional Chinese (正體中文), covering the same changes, installation steps, and limitations in each language.
- Use `scripts/github-release-notes.sh` to separate the release-note heading into GitHub's title and the remaining text into its body. Never pass the complete titled Markdown file directly to GitHub's `--notes-file`; verify that the published body has no repeated top-level heading.
- Publish normal GitHub releases and mark the newest release as Latest by default. Use a prerelease/preview designation only when the user explicitly requests it; ad hoc signing or the lack of Apple notarization does not require a prerelease label.
