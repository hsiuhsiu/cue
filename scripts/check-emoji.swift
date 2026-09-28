import AppKit
import CueCore

private final class EmojiLoaderFixture: @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private var count = 0
    private var onMain = false
    private var shouldFail = false
    private var gate: DispatchSemaphore?

    init(data: Data) { self.data = data }
    func configure(fail: Bool = false, suspended: Bool = false) -> DispatchSemaphore? {
        lock.lock(); defer { lock.unlock() }
        shouldFail = fail
        gate = suspended ? DispatchSemaphore(value: 0) : nil
        return gate
    }
    func load() throws -> EmojiCatalog {
        lock.lock()
        count += 1
        onMain = onMain || Thread.isMainThread
        let fail = shouldFail
        let gate = gate
        lock.unlock()
        if let gate { _ = gate.wait(timeout: .now() + 5) }
        if fail { throw CocoaError(.fileReadCorruptFile) }
        return try EmojiCatalog(data: data)
    }
    var state: (count: Int, onMain: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (count, onMain)
    }
}

private actor EmojiCopyFixture {
    private var waits: [CheckedContinuation<Void, Never>] = []
    private var fail = false
    private(set) var attempts = 0
    private(set) var written: [String] = []
    func configure(fail: Bool = false) { self.fail = fail }
    func copy(_ emoji: String) async throws {
        attempts += 1
        await withCheckedContinuation { waits.append($0) }
        try Task.checkCancellation()
        if fail { throw CocoaError(.fileWriteUnknown) }
        written.append(emoji)
    }
    func resume() {
        let pending = waits
        waits.removeAll()
        pending.forEach { $0.resume() }
    }
}

@main struct CheckEmoji {
    @MainActor static var checks = 0
    @MainActor static func check(_ value: Bool, _ message: String) {
        guard value else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }
    @MainActor static func eventually(_ message: String, _ predicate: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await predicate() { check(true, message); return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(false, message)
    }
    static func fixtureData() throws -> Data {
        let values = [
            ("😀", "grinning face", "笑臉"), ("😂", "tears of joy", "喜極而泣"),
            ("❤️", "red heart", "紅心"), ("👍", "thumbs up", "讚"),
            ("🙏", "folded hands", "合掌"), ("🎉", "party popper", "拉炮"),
            ("🔥", "fire", "火"), ("😊", "smiling eyes", "微笑"),
            ("👩🏽‍💻", "woman technologist medium skin tone", "女性工程師：中等膚色"),
            ("👨‍👩‍👧‍👦", "family", "家庭"), ("🇹🇼", "Taiwan flag", "臺灣旗"),
            ("🏳️‍🌈", "rainbow flag", "彩虹旗"), ("⚽", "soccer ball", "足球")
        ]
        return try JSONSerialization.data(withJSONObject: [
            "formatVersion": 1, "unicodeVersion": "15.0", "cldrVersion": "42",
            "entries": values.map { ["emoji": $0.0, "name": $0.1, "traditionalName": $0.2, "keywords": ["fixture"]] }
        ])
    }
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.mainMenu = nil
        let data = try fixtureData()
        let domain = "com.yyhsiu.cue.tests.emoji.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        try await checkModel(data, board: board)
        try await checkView(data)
        try await checkReopenedGlyphs(data)
        try await checkController(data, app: app, defaults: defaults, board: board)
        check(!policy.allowsNetwork, "Emoji loading, search, and copy do not need or change Cue networking permission")
        check(!app.isActive && app.windows.allSatisfy { !$0.isVisible }, "Emoji checks stay hidden without activating any window")
        print("Emoji passed: \(checks) checks; background loading/retry, synchronous local search, native keyboard/IME routing, private clipboard copy/cancellation, and controller entry/back/dismiss. No general clipboard or network access.")
    }

    @MainActor static func checkModel(_ data: Data, board: NSPasteboard) async throws {
        let loader = EmojiLoaderFixture(data: data)
        let gate = loader.configure(suspended: true)!
        let model = EmojiModel(pasteboardName: board.name, loader: { try loader.load() })
        board.clearContents()
        board.setString("preserve private fixture", forType: .string)
        board.setString("<b>stale private fixture</b>", forType: .html)
        let untouchedCount = board.changeCount
        check(loader.state.count == 0 && !model.isLoading, "Construction does not synchronously load data or touch clipboard content")
        model.prepare()
        model.prepare()
        await eventually("Preparation begins one off-main catalog load") { loader.state.count == 1 }
        model.open()
        model.setQuery("family")
        check(model.isLoading && model.query == "family" && model.results.isEmpty,
              "Typing remains synchronous while the initial catalog loader is suspended")
        gate.signal()
        await eventually("Loading resolves the most recent query") { !model.isLoading && model.results.first?.emoji == "👨‍👩‍👧‍👦" }
        check(!loader.state.onMain && loader.state.count == 1 && board.changeCount == untouchedCount,
              "Catalog I/O/decoding stays off-main and opening/searching never changes the clipboard")
        model.setQuery("fixture")
        check(model.results.count == 9 && model.selectedEntry != nil, "Feature results are immediately capped at nine with a valid first selection")
        model.setQuery("臺灣旗")
        check(model.results.first?.emoji == "🇹🇼", "Traditional Chinese queries reach the catalog synchronously")
        model.setQuery("family")
        var copied = 0
        model.copySelected { copied += 1 }
        for _ in 0..<5 { model.copySelected { copied += 1 } }
        await eventually("Explicit execution copies one selected emoji") { copied == 1 }
        check(board.string(forType: .string) == "👨‍👩‍👧‍👦",
              "Copy preserves the complete joined family emoji without changing its code points")
        check(board.types?.contains(.string) == true && board.data(forType: .html) == nil && board.data(forType: .URL) == nil,
              "Copy publishes plain text without retaining stale rich-text or URL flavors")
        model.setQuery("woman technologist")
        model.copySelected(at: 0) { copied += 1 }
        await eventually("A numbered copy preserves skin-tone and joiner sequences") { copied == 2 }
        check(board.string(forType: .string) == "👩🏽‍💻", "Skin-tone modifiers and ZWJ code points are preserved exactly")
        let afterCopy = board.changeCount
        model.copySelected(at: 9) { copied += 1 }
        model.setQuery("nonexistent fixture word")
        model.copySelected { copied += 1 }
        check(copied == 2 && board.changeCount == afterCopy && model.results.isEmpty,
              "Out-of-range and empty selection requests do not publish clipboard content")
        model.close()
        model.open()
        check(model.query.isEmpty && model.results.count == 9 && loader.state.count == 1,
              "Reopening uses the loaded catalog immediately without rereading data")
        model.close()
        model.copySelected { copied += 1 }
        check(copied == 2, "An inactive feature cannot copy from stale visible results")

        let failureLoader = EmojiLoaderFixture(data: data)
        _ = failureLoader.configure(fail: true)
        let failedModel = EmojiModel(pasteboardName: board.name, loader: { try failureLoader.load() })
        failedModel.open()
        await eventually("Failed initial loads end their spinner and expose a retryable error") {
            !failedModel.isLoading && failedModel.errorMessage == EmojiText.shared.loadError
        }
        _ = failureLoader.configure()
        failedModel.prepare()
        await eventually("Retry successfully loads the catalog") { !failedModel.isLoading && !failedModel.results.isEmpty }
        check(failureLoader.state.count == 2 && failedModel.errorMessage == nil,
              "A failed load can be retried without permanently caching the error")
        failedModel.close()

        let copyFixture = EmojiCopyFixture()
        let delayed = EmojiModel(loader: { try EmojiCatalog(data: data) }, copier: { try await copyFixture.copy($0) })
        delayed.open()
        await eventually("Delayed-copy fixture catalog becomes ready") { !delayed.isLoading }
        var completions = 0
        for cancellation in ["query", "close", "reopen", "selection", "focus"] {
            delayed.open()
            delayed.setQuery("fixture")
            let attempts = await copyFixture.attempts
            let writes = await copyFixture.written.count
            delayed.copySelected { completions += 1 }
            await eventually("\(cancellation): a copy enters the suspended writer") { await copyFixture.attempts == attempts + 1 }
            delayed.copySelected { completions += 1 }
            switch cancellation {
            case "query": delayed.setQuery("family")
            case "close": delayed.close()
            case "reopen": delayed.open()
            case "selection": delayed.moveSelection(by: 1)
            default: delayed.cancelPendingCopy()
            }
            let query = delayed.query
            let selection = delayed.selectedID
            await copyFixture.resume()
            try await Task.sleep(for: .milliseconds(15))
            check(await copyFixture.written.count == writes && completions == 0 && !delayed.isCopying
                  && delayed.query == query && delayed.selectedID == selection,
                  "\(cancellation): cancellation prevents stale writes and completion-driven dismissal")
        }
        delayed.open()
        await copyFixture.configure(fail: true)
        let priorAttempts = await copyFixture.attempts
        delayed.copySelected { completions += 1 }
        await eventually("A failing copy reaches the injected writer") { await copyFixture.attempts == priorAttempts + 1 }
        await copyFixture.resume()
        await eventually("A failed copy remains visible with actionable feedback") { delayed.errorMessage == EmojiText.shared.copyError }
        check(!delayed.isCopying && completions == 0, "Copy failures do not dismiss the feature or leave it busy")
        delayed.close()
    }

    @MainActor static func checkView(_ data: Data) async throws {
        let model = EmojiModel(loader: { try EmojiCatalog(data: data) }, copier: { _ in })
        var copies: [Int?] = []
        var backs = 0
        var settings = 0
        let view = EmojiView(model: model, onCopy: { copies.append($0) }, onBack: { backs += 1 }, onSettings: { settings += 1 })
        let window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        let blankDrawStart = DispatchTime.now().uptimeNanoseconds
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        let blankDraw = Double(DispatchTime.now().uptimeNanoseconds - blankDrawStart) / 1_000_000
        print(String(format: "First native blank-feature bitmap draw: %.3f ms. Initializes the offscreen AppKit drawing path before measuring emoji glyphs.", blankDraw))
        model.open()
        await eventually("The native emoji page loads its initial choices") { !model.isLoading && model.results.count == 9 }
        await eventually("Starter glyphs finish rendering away from the input thread") { !model.glyphs.isLoading }
        window.setContentSize(NSSize(width: 640, height: view.preferredHeight))
        view.layoutSubtreeIfNeeded()
        check(view.frame.width == 640 && view.searchField.font?.pointSize == 21,
              "The feature retains the launcher's compact width and readable search size")
        guard let scroll = view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let table = scroll.documentView as? NSTableView else { fatalError("Missing emoji table") }
        let firstDrawStart = DispatchTime.now().uptimeNanoseconds
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "The first native emoji frame renders to an offscreen bitmap")
        } else { check(false, "The native emoji view must support an offscreen render check") }
        let firstDraw = Double(DispatchTime.now().uptimeNanoseconds - firstDrawStart) / 1_000_000
        print(String(format: "First populated emoji draw after blank-frame infrastructure (fixture rows, offscreen): %.3f ms. Includes glyph drawing; not an OS-delivered frame measurement.", firstDraw))
        check(!scroll.hasVerticalScroller && !scroll.hasHorizontalScroller && table.numberOfRows == 9,
              "At most nine numbered rows are displayed without scrollbars")
        for row in [0, 8] {
            let cell = view.tableView(table, viewFor: table.tableColumns.first, row: row)
            let fields = cell?.subviews.compactMap { $0 as? NSTextField } ?? []
            check(fields.contains { $0.stringValue == ResultShortcut.label(for: row) }
                  && cell?.subviews.compactMap { $0 as? NSImageView }.first?.image === model.glyphs.image(for: model.results[row]),
                  "Each result contains its cached glyph and the matching numbered shortcut")
            let reps = model.glyphs.image(for: model.results[row])?.representations.compactMap { $0 as? NSBitmapImageRep } ?? []
            check(Set(reps.map(\.pixelsWide)) == [28, 56]
                  && reps.allSatisfy { $0.pixelsHigh == $0.pixelsWide && $0.size == NSSize(width: 28, height: 28) },
                  "Background-rendered glyphs retain 28-point ordinary and Retina backing images")
        }
        func key(_ code: UInt16, _ value: String, modifiers: NSEvent.ModifierFlags = .command, repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: value,
                             charactersIgnoringModifiers: value, isARepeat: repeated, keyCode: code)!
        }
        check(view.performKeyEquivalent(with: key(18, "1")) && copies.count == 1 && copies.last! == 0,
              "Command-1 executes the first emoji choice through real key-equivalent routing")
        check(view.performKeyEquivalent(with: key(25, "9")) && copies.count == 2 && copies.last! == 8,
              "Command-9 executes the last visible emoji choice")
        _ = view.handleNumberShortcut(key(25, "9", repeated: true))
        check(copies.count == 2, "A held numbered shortcut does not copy repeatedly")
        check(view.handleNumberShortcut(key(83, "", modifiers: [.command, .capsLock])) && copies.last! == 0,
              "Numeric keypad and Caps Lock retain numbered execution")
        for flags in [NSEvent.ModifierFlags(), [.command, .shift], [.command, .option], [.command, .control]] {
            check(!view.handleNumberShortcut(key(18, "1", modifiers: flags)), "Additional modifiers and ordinary numbers do not execute emoji choices")
        }
        let editor = NSTextView()
        let selection = model.selectedID
        _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        check(model.selectedID != selection, "Down moves to the next result immediately")
        _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
        check(model.selectedID == selection, "Up returns to the previous result immediately")
        _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check(copies.last! == nil, "Return copies the selected emoji through the feature callback")
        _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        check(backs == 1, "Escape returns to the launcher")
        check(view.performKeyEquivalent(with: key(43, ",")) && settings == 1,
              "Command-comma remains available for Cue-wide Settings")
        _ = view.handleSettingsShortcut(key(43, ",", repeated: true))
        check(settings == 1, "Held Command-comma opens Settings only once")
        window.makeFirstResponder(view.searchField)
        guard let fieldEditor = view.searchField.currentEditor() as? NSTextView else { fatalError("Missing emoji field editor") }
        fieldEditor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let beforeIME = copies.count
        let marked = fieldEditor.string
        check(!view.handleNumberShortcut(key(18, "1")), "Numbered shortcuts leave provisional IME text alone")
        check(!view.control(view.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
              && !view.control(view.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:))),
              "Return and Escape during composition remain available to the input method")
        check(copies.count == beforeIME && backs == 1 && fieldEditor.hasMarkedText() && fieldEditor.string == marked,
              "IME-safe routing preserves marked text and never copies or navigates")
        fieldEditor.unmarkText()
        let publish = model.onChange
        var modelPublications = 0
        model.onChange = { modelPublications += 1; publish?() }
        model.setQuery("woman technologist")
        let publicationsAfterQuery = modelPublications
        let glyphQuery = model.query
        let glyphSelection = model.selectedID
        let glyphResponder = window.firstResponder
        let glyphCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView
        await eventually("A newly searched complex glyph arrives asynchronously") { !model.glyphs.isLoading }
        check(modelPublications == publicationsAfterQuery && model.query == glyphQuery && model.selectedID == glyphSelection
              && window.firstResponder === glyphResponder && table.view(atColumn: 0, row: 0, makeIfNecessary: false) === glyphCell,
              "Asynchronous glyph completion preserves the existing row, input, selection, and model publication count")
        check(glyphCell?.subviews.compactMap { $0 as? NSImageView }.first?.image === model.glyphs.image(for: model.results[0]),
              "The visible row receives only its currently selected emoji's cached image")
        model.setQuery("family")
        let beforeMissing = copies.count
        _ = view.handleNumberShortcut(key(25, "9"))
        check(copies.count == beforeMissing, "An absent numbered row cannot copy a stale choice")
        model.setQuery("fixture")
        window.setContentSize(NSSize(width: 640, height: 250))
        view.layoutSubtreeIfNeeded()
        for _ in 0..<8 { model.moveSelection(by: 1) }
        check(table.rows(in: table.visibleRect).contains(8), "Keyboard selection remains visible when a small screen clamps the panel height")
        model.close()
        if let path = ProcessInfo.processInfo.environment["CUE_EMOJI_CATALOG"] {
            try await benchmarkCatalog(URL(fileURLWithPath: path))
        }
    }

    @MainActor static func checkReopenedGlyphs(_ data: Data) async throws {
        let model = EmojiModel(loader: { try EmojiCatalog(data: data) }, copier: { _ in })
        let view = EmojiView(model: model, onCopy: { _ in }, onBack: {})
        let window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { model.onChange = nil; model.close(); window.contentView = nil; window.close() }
        guard let scroll = view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let table = scroll.documentView as? NSTableView else { fatalError("Missing reopened emoji table") }
        let render = model.onChange
        var closedBeforeGlyphs = false
        var cells: [NSTableCellView] = []
        model.onChange = { [weak model, weak view, weak window] in
            render?()
            guard !closedBeforeGlyphs, let model, let view, let window, !model.results.isEmpty else { return }
            // This runs synchronously in the catalog-ready callback before the
            // queued glyph task gets its first actor turn, making the race deterministic.
            window.setContentSize(NSSize(width: 640, height: view.preferredHeight))
            view.layoutSubtreeIfNeeded()
            cells = model.results.indices.compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView }
            check(cells.count == 9 && cells.allSatisfy {
                $0.subviews.compactMap { $0 as? NSImageView }.first?.image == nil
            }, "Reopen regression materializes rows before their first glyph render can run")
            closedBeforeGlyphs = true
            model.close()
        }
        model.open()
        await eventually("The closed feature finishes its already-started glyph batch") {
            closedBeforeGlyphs && model.glyphs.cachedGlyphCount == 9
        }
        check(cells.allSatisfy { $0.subviews.compactMap { $0 as? NSImageView }.first?.image == nil },
              "Hidden glyph completion intentionally leaves old native rows untouched")
        let originalResults = model.results
        model.open()
        check(model.results == originalResults && !model.glyphs.isLoading,
              "Reopening identical popular results reuses the finished cache without another render")
        for (row, cell) in cells.enumerated() {
            check(table.view(atColumn: 0, row: row, makeIfNecessary: false) === cell
                  && cell.subviews.compactMap { $0 as? NSImageView }.first?.image === model.glyphs.image(for: model.results[row]),
                  "Reopening restores cached glyph \(row + 1) into its existing row even when result identity is unchanged")
        }
    }

    @MainActor static func benchmarkCatalog(_ url: URL) async throws {
        let data = try Data(contentsOf: url)
        let model = EmojiModel(loader: { try EmojiCatalog(data: data) }, copier: { _ in })
        let start = DispatchTime.now().uptimeNanoseconds
        let view = EmojiView(model: model, onCopy: { _ in }, onBack: {})
        let firstView = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.onPreferredHeightChange = { [weak window] height in
            guard let window, window.frame.height != height else { return }
            var frame = window.frame
            frame.origin.y = frame.maxY - height
            frame.size.height = height
            window.setFrame(frame, display: false, animate: false)
        }
        defer { window.contentView = nil; window.close() }
        model.open()
        await eventually("The bundled catalog benchmark finishes background preparation") { !model.isLoading }
        await eventually("The bundled starter glyphs finish off-main preparation") { !model.glyphs.isLoading }
        check(model.errorMessage == nil && !model.results.isEmpty, "The shipped catalog loads into the native feature")
        let queries = ["smile", "heart", "家庭", "笑", "thumb", "flag", "貓", "👩🏽‍💻", "fire", "party", ""]
        var samples: [Double] = []
        for index in 0..<550 {
            let start = DispatchTime.now().uptimeNanoseconds
            view.searchField.stringValue = queries[index % queries.count]
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
            view.layoutSubtreeIfNeeded()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        samples.sort()
        print(String(format: "Bundled emoji offscreen search/layout (550 edits): p50 %.3f ms, p95 %.3f, p99 %.3f, max %.3f; native view creation %.3f ms. Excludes OS input delivery and visible composition.", samples[274], samples[521], samples[543], samples[549], firstView))
        let stableQueries = ["smile", "heart", "flag", "face", "愛心", "hand"].filter {
            model.setQuery($0)
            return model.results.count == 9
        }
        check(stableQueries.count >= 2, "The full catalog supplies multiple distinct nine-result queries for a stable-height comparison")
        var stableSamples: [Double] = []
        var eventSamples: [Double] = []
        var layoutSamples: [Double] = []
        for index in 0..<300 {
            let start = DispatchTime.now().uptimeNanoseconds
            view.searchField.stringValue = stableQueries[index % stableQueries.count]
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
            let afterEvent = DispatchTime.now().uptimeNanoseconds
            view.layoutSubtreeIfNeeded()
            let afterLayout = DispatchTime.now().uptimeNanoseconds
            stableSamples.append(Double(afterLayout - start) / 1_000_000)
            eventSamples.append(Double(afterEvent - start) / 1_000_000)
            layoutSamples.append(Double(afterLayout - afterEvent) / 1_000_000)
        }
        stableSamples.sort()
        eventSamples.sort()
        layoutSamples.sort()
        print(String(format: "Bundled emoji at stable nine-row height (300 edits): p50 %.3f ms, p95 %.3f, p99 %.3f, max %.3f. Includes local search and native table/layout, no panel resize.", stableSamples[149], stableSamples[284], stableSamples[296], stableSamples[299]))
        print(String(format: "Stable-height phases: input/search/table-update p50 %.3f ms, p99 %.3f; explicit native layout p50 %.3f ms, p99 %.3f.", eventSamples[149], eventSamples[296], layoutSamples[149], layoutSamples[296]))
        model.close()
        let entries = try EmojiCatalog(data: data).search("", limit: 162)
        let cache = EmojiGlyphCache()
        for start in stride(from: 0, to: entries.count, by: 9) {
            cache.prepare(Array(entries[start..<min(start + 9, entries.count)]))
            await eventually("A bounded glyph-cache batch completes") { !cache.isLoading }
            check(cache.cachedGlyphCount <= EmojiGlyphCache.maximumGlyphs, "Browsing more than 128 distinct glyphs keeps the cache bounded")
        }
        check(cache.image(for: entries[0]) == nil && cache.image(for: entries.last!) != nil,
              "Glyph eviction releases old entries while retaining the current visible targets")
        let lastImage = cache.image(for: entries.last!)
        cache.prepare(Array(entries.suffix(9)))
        check(cache.image(for: entries.last!) === lastImage && !cache.isLoading,
              "Revisiting ready glyphs preserves cached image identity without a blank loading frame")
        let staleCache = EmojiGlyphCache()
        var staleCallbacks = 0
        staleCache.onLoad = { staleCallbacks += 1 }
        staleCache.prepare(Array(entries.prefix(9)))
        staleCache.prepare(Array(entries.suffix(9)))
        staleCache.prepare(Array(entries.prefix(9)))
        staleCache.prepare([])
        await eventually("An already-running glyph batch drains after its page closes") { staleCache.cachedGlyphCount > 0 }
        check(staleCallbacks == 0 && !staleCache.isLoading && staleCache.cachedGlyphCount <= 9,
              "Rapid A-to-B-to-A queries followed by close coalesce work without publishing stale visible glyphs")
    }

    @MainActor static func checkController(_ data: Data, app: NSApplication, defaults: UserDefaults, board: NSPasteboard) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cue-emoji-controller-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clipboard = ClipboardModel(defaults: defaults, fileURL: folder.appendingPathComponent("clipboard.json"), pasteboardName: board.name)
        defer { clipboard.stop() }
        let emoji = EmojiModel(pasteboardName: board.name, loader: { try EmojiCatalog(data: data) })
        let store = SearchUsageStore(fileURL: folder.appendingPathComponent("usage.json"))
        let launcher = LauncherModel(usageStore: store, icons: AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil }))
        let controller = LauncherPanelController(clipboard: clipboard, model: launcher, emoji: emoji,
            performSystemAction: { _ in fatalError("Unexpected system action") },
            openApplication: { _, _ in fatalError("Unexpected application handoff") },
            webSearchPreferences: WebSearchPreferences(defaults: defaults),
            openWebURL: { _, _, _ in fatalError("Unexpected browser handoff") }, resolveBrowser: { _ in nil },
            frontmostProcess: { nil }, restoreSource: { _ in false })
        guard let window = app.windows.last(where: { $0.contentView is LauncherView }),
              let launcherView = window.contentView as? LauncherView else { fatalError("Missing hidden launcher") }
        defer { window.contentView = nil; window.close() }
        func openEmoji() {
            launcher.setQuery("emoji")
            _ = launcherView.control(launcherView.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        }
        controller.prepareEmojiSearch()
        await eventually("Controller prewarming prepares the injected catalog") { !emoji.isLoading }
        openEmoji()
        check(window.contentView is EmojiView && window.initialFirstResponder === (window.contentView as? EmojiView)?.searchField,
              "Executing the launcher command enters the emoji page and targets its input")
        let emojiView = window.contentView as! EmojiView
        _ = emojiView.control(emojiView.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        check(window.contentView === launcherView && launcher.query.isEmpty,
              "Escape returns from emoji search to the minimal empty launcher")
        openEmoji()
        emoji.setQuery("family")
        _ = emojiView.control(emojiView.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        await eventually("Copying from the feature dismisses back to the launcher") { window.contentView === launcherView }
        check(board.string(forType: .string) == "👨‍👩‍👧‍👦" && launcher.query.isEmpty && !window.isVisible,
              "The real controller copies the selected emoji once and resets its feature presentation")
        openEmoji()
        controller.dismiss(returnFocus: false)
        let before = board.changeCount
        emoji.copySelected { fatalError("Closed feature completed a stale copy") }
        check(board.changeCount == before && window.contentView === launcherView,
              "Controller dismissal closes the model so later stale copy requests cannot publish")
        await launcher.prepareForTermination()
        let saved = (try? String(contentsOf: folder.appendingPathComponent("usage.json"), encoding: .utf8)) ?? ""
        check(!saved.contains("family") && !saved.contains("👨‍👩‍👧‍👦"), "Emoji queries and copied glyphs stay out of launcher usage history")
        await clipboard.prepareForTermination()
    }
}
