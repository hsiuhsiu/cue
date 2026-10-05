import AppKit
import Carbon
import CueCore

/// Keeps canceled callbacks alive intentionally, so late metadata deliveries can
/// be tested without reading the user's Spotlight index or any real documents.
@MainActor
private final class FileSearchFixture: FileSearching {
    struct Request {
        let term: String
        let limit: Int
        let completion: @MainActor (FileSearchResponse) -> Void
    }
    private(set) var requests: [Request] = []
    private(set) var cancellations = 0

    func search(_ term: String, limit: Int, completion: @escaping @MainActor (FileSearchResponse) -> Void) {
        requests.append(Request(term: term, limit: limit, completion: completion))
    }

    func cancel() { cancellations += 1 }

    func finish(_ index: Int, results: [FileSearchResult] = [], error: FileSearchFailure? = nil) {
        requests[index].completion(FileSearchResponse(results: results, error: error))
    }
}

@main
struct CheckFileSearch {
    @MainActor static var checks = 0

    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    static func document(_ name: String, folder: String = "/Synthetic/Documents", isDirectory: Bool = false) -> FileSearchResult {
        FileSearchResult(url: URL(fileURLWithPath: folder).appendingPathComponent(name),
                         name: name, parentPath: folder, isDirectory: isDirectory)
    }

    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.mainMenu = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cue-file-search-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let domain = "com.yyhsiu.cue.tests.file-search.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        defer { defaults.removePersistentDomain(forName: domain) }
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("unrelated synthetic clipboard", forType: .string)
        let untouchedClipboard = board.changeCount
        let clipboard = ClipboardModel(defaults: defaults,
                                       fileURL: folder.appendingPathComponent("clipboard.json"),
                                       pasteboardName: board.name)
        defer { clipboard.stop() }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let browserPreferences = WebSearchPreferences(defaults: defaults)
        let fixture = FileSearchFixture()
        let usageURL = folder.appendingPathComponent("usage.json")
        let usage = SearchUsageStore(fileURL: usageURL)
        let syntheticApp = IndexedApplication(name: "Fixture", url: URL(fileURLWithPath: "/Synthetic/Fixture.app"))
        let icons = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil })
        let model = LauncherModel(applications: [syntheticApp], usageStore: usage,
                                  fileSearch: fixture, icons: icons)
        var opened: [URL] = []
        var openedApps = 0
        var openedBrowsers = 0
        let controller = LauncherPanelController(
            clipboard: clipboard, model: model,
            performSystemAction: { _ in fatalError("File search must not execute system commands") },
            openApplication: { _, completion in openedApps += 1; completion(nil) },
            openFile: { url, completion in opened.append(url); completion(nil) },
            webSearchPreferences: browserPreferences,
            openWebURL: { _, _, completion in openedBrowsers += 1; completion(nil) },
            resolveBrowser: { _ in nil },
            frontmostProcess: { nil }, restoreSource: { _ in true }
        )
        guard let window = app.windows.last(where: { $0.contentView is LauncherView }),
              let view = window.contentView as? LauncherView,
              let table = descendants(view).compactMap({ $0 as? NSTableView }).first else {
            fatalError("Missing offscreen launcher fixture")
        }
        defer { window.contentView = nil; window.close() }

        func type(_ query: String) {
            view.searchField.stringValue = query
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
            view.layoutSubtreeIfNeeded()
        }
        func key(_ code: UInt16, _ text: String, repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                            timestamp: 0, windowNumber: window.windowNumber, context: nil,
                            characters: text, charactersIgnoringModifiers: text,
                            isARepeat: repeated, keyCode: code)!
        }
        func submit() {
            _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        }
        func verifyOnlyFiles(_ message: String) {
            check(model.results.allSatisfy { if case .file = $0 { true } else { false } }, message)
        }

        controller.prepareInvocation()
        for input in ["", "f", "fixture", "ordinary words", "Fuzzy", "f\treport"] {
            type(input)
            check(!model.isFileSearch && fixture.requests.isEmpty, "Ordinary input does not start file searches: \(input)")
        }
        type("f ")
        check(model.isFileSearch && model.results.isEmpty && fixture.requests.isEmpty,
              "The prefix enters a quiet file mode without searching an empty term")
        type("F    ")
        check(model.isFileSearch && model.results.isEmpty && fixture.requests.isEmpty,
              "Uppercase F and whitespace-only terms do not start a broad scan")
        type("f " + String(repeating: "報", count: 1_024))
        check(model.isFileSearch && model.results.isEmpty && fixture.requests.isEmpty
              && model.fileSearchStatus != nil,
              "An oversized pasted filename stays local and never starts an unbounded search")

        type("f report")
        check(fixture.requests.count == 1 && fixture.requests[0].term == "report",
              "The first nonblank filename term starts a search immediately")
        check(fixture.requests[0].limit == 9 && model.results.isEmpty && model.fileSearchStatus != nil,
              "The index request is bounded and pending work is visible")
        check(!policy.allowsNetwork, "File search is usable while Cue networking is disabled")
        let report = document("report.pdf")
        let secondReport = document("report.pdf", folder: "/Synthetic/Archive")
        fixture.finish(0, results: [report, secondReport])
        check(model.results == [.file(report), .file(secondReport)],
              "Equal filenames in different directories remain distinct results")
        check(model.selectedResult == .file(report), "The first file is immediately keyboard-selectable")
        check(table.numberOfRows == 2, "Native rows update when asynchronous results arrive")
        let row = table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        let labels = row.map { descendants($0).compactMap { ($0 as? NSTextField)?.stringValue } } ?? []
        check(labels.contains(report.name) && labels.contains(report.parentPath),
              "Native file rows show a filename and parent path")
        check(icons.image(for: report) === icons.image(for: secondReport),
              "File icons reuse a prepared symbol without per-file discovery")
        check(row?.toolTip == report.url.path,
              "The complete file path is available without opening the file")
        let fields = row.map { descendants($0).compactMap { $0 as? NSTextField } } ?? []
        let title = fields.first(where: { $0.stringValue == report.name })
        let detail = fields.first(where: { $0.stringValue == report.parentPath })
        check(title != nil && detail != nil && detail!.frame.width > 300
              && !title!.frame.intersects(detail!.frame),
              "The parent path has its own wide line without overlapping the filename")
        check((row.map { descendants($0).compactMap { $0 as? NSButton } } ?? []).allSatisfy(\.isHidden),
              "A file row does not show app-only alias actions")
        check(view.subviews.compactMap { $0 as? NSButton }.allSatisfy(\.isHidden),
              "File mode hides the text Actions button")

        type("f report pending")
        let pendingRequest = fixture.requests.count - 1
        let previousCancellation = fixture.cancellations
        type("f invoice")
        let invoiceRequest = fixture.requests.count - 1
        check(model.results.isEmpty && fixture.cancellations > previousCancellation,
              "Editing a filename cancels the prior request and removes stale selectable rows")
        fixture.finish(pendingRequest, results: [report])
        check(model.results.isEmpty, "A late callback cannot replace a newer pending query")
        let invoice = document("invoice.txt")
        fixture.finish(invoiceRequest, results: [invoice])
        check(model.results == [.file(invoice)], "The current query accepts its own results")
        let completedCancellation = fixture.cancellations
        type("fixture")
        fixture.finish(invoiceRequest, results: [report])
        check(!model.isFileSearch && model.results.contains(.application(syntheticApp)),
              "Leaving file mode restores app search and ignores late metadata")
        type("fixt")
        type("fixture")
        check(fixture.cancellations == completedCancellation,
              "Normal app typing performs no backend cancellation after a completed file query")

        type("f missing")
        fixture.finish(fixture.requests.count - 1)
        check(model.results.isEmpty && model.fileSearchStatus != nil,
              "No filename match shows a local empty state, with no web fallback")
        _ = view.performKeyEquivalent(with: key(UInt16(kVK_ANSI_K), "k"))
        _ = view.performKeyEquivalent(with: key(UInt16(kVK_Return), "\r"))
        check(!model.isShowingSearchActions && openedBrowsers == 0,
              "Command-K and Command-Return cannot send a filename query to Google or GPT")
        verifyOnlyFiles("File mode offers only file results")

        type("f unavailable")
        fixture.finish(fixture.requests.count - 1, error: .unavailable)
        check(model.results.isEmpty && model.fileSearchStatus != nil,
              "A failed index request shows a local failure state")
        type("f recovered")
        fixture.finish(fixture.requests.count - 1, results: [report])
        check(model.results == [.file(report)], "A new query recovers after an index failure")

        type("f suspended")
        let suspendedRequest = fixture.requests.count - 1
        model.suspendFileSearch()
        fixture.finish(suspendedRequest, results: [report])
        check(model.results.isEmpty, "Suspended file searches reject late results")
        let beforeResume = fixture.requests.count
        model.resumeFileSearch()
        check(fixture.requests.count == beforeResume + 1 && fixture.requests.last?.term == "suspended",
              "Resuming a pending file query starts one fresh request")
        fixture.finish(fixture.requests.count - 1, results: [invoice])
        check(model.results == [.file(invoice)], "A resumed search can show fresh results")

        type("f reset")
        let resetRequest = fixture.requests.count - 1
        model.reset()
        fixture.finish(resetRequest, results: [report])
        check(model.query.isEmpty && model.results.isEmpty && !model.isFileSearch,
              "Reset removes the file mode and invalidates its callbacks")

        type("f bounded")
        let many = (1...30).map { document("bounded-\($0).txt") }
        fixture.finish(fixture.requests.count - 1, results: many)
        check(model.results.count == 9 && table.numberOfRows == 9,
              "Even an oversized backend response cannot exceed nine visible results")
        check(descendants(view).compactMap { $0 as? NSScrollView }.allSatisfy { !$0.hasVerticalScroller },
              "File results preserve the launcher's no-scrollbar layout")
        model.moveSelection(by: 1)
        submit()
        check(opened == [many[1].url] && model.query.isEmpty,
              "Down and Return open the selected file through the injected system opener")
        check(openedApps == 0 && openedBrowsers == 0, "Opening a file does not route through app or browser actions")

        controller.prepareInvocation()
        type("f numbered")
        fixture.finish(fixture.requests.count - 1, results: many)
        _ = view.performKeyEquivalent(with: key(UInt16(kVK_ANSI_9), "9"))
        check(opened.last == many[8].url && opened.count == 2,
              "Command-9 opens the current ninth file directly")
        _ = view.performKeyEquivalent(with: key(UInt16(kVK_ANSI_9), "9", repeated: true))
        check(opened.count == 2, "Held number shortcuts cannot open a file twice")

        controller.prepareInvocation()
        type("f folder")
        let directory = document("folder", isDirectory: true)
        fixture.finish(fixture.requests.count - 1, results: [directory])
        submit()
        check(opened.last == directory.url, "Folder results use the same explicit default-system open action")
        check(icons.image(for: directory) !== icons.image(for: report),
              "Folders and documents have distinct cached icons")

        // Rapid edits must not retain stale rows or introduce a debounce window.
        controller.prepareInvocation()
        let burstStart = fixture.requests.count
        var durations: [Double] = []
        for index in 0..<200 {
            let started = ContinuousClock.now
            type("f burst-\(index)")
            let elapsed = started.duration(to: .now).components
            durations.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        check(fixture.requests.count == burstStart + 200,
              "Each distinct rapid edit reaches the asynchronous service without a typing debounce")
        for request in burstStart..<(fixture.requests.count - 1) {
            fixture.finish(request, results: [report])
        }
        check(model.results.isEmpty, "Every superseded rapid-edit callback is rejected")
        fixture.finish(fixture.requests.count - 1, results: [invoice])
        check(model.results == [.file(invoice)], "Only the newest rapid-edit result is visible")
        let dismissedRequest = fixture.requests.count - 1
        controller.dismiss(returnFocus: false)
        fixture.finish(dismissedRequest, results: [report])
        check(model.results.isEmpty && model.query.isEmpty && !window.isVisible,
              "Dismissal invalidates file results without presenting any window")

        // Check both result-ID and query-mode privacy guards independently.
        model.recordSuccessfulAction(resultID: report.id, query: "ordinary")
        model.recordSuccessfulAction(resultID: LauncherResult.application(syntheticApp).id, query: "f private-name")
        model.recordSuccessfulAction(resultID: LauncherResult.application(syntheticApp).id, query: "fixture")
        await model.prepareForTermination()
        let saved = String(decoding: try Data(contentsOf: usageURL), as: UTF8.self)
        check(saved.contains("fixture") && !saved.contains("private-name") && !saved.contains("report.pdf")
              && !saved.contains("ordinary") && !saved.contains("file:"),
              "Only successful app queries persist; filenames and file actions are excluded from learning")
        check(board.changeCount == untouchedClipboard, "Searching and opening files never touches the clipboard")
        checkRefinementAndNotifications()
        check(!window.isVisible && !NSApp.isActive, "All checks remain offscreen with activation prohibited")
        durations.sort()
        print("File search passed \(checks) isolated checks; synthetic typing p95 \(String(format: "%.3f", durations[durations.count * 95 / 100])) ms, max \(String(format: "%.3f", durations.last!)) ms.")
    }

    /// A separate fixture keeps lifecycle request indices above independent
    /// from refinement, stable numbering, progress and notification checks.
    @MainActor static func checkRefinementAndNotifications() {
        let fixture = FileSearchFixture()
        let icons = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil })
        let model = LauncherModel(fileSearch: fixture, icons: icons)
        let view = LauncherView(model: model, onSubmit: {}, onCancel: {}, onSettings: {})
        view.onPreferredHeightChange = { [weak view] height in
            view?.setFrameSize(NSSize(width: 640, height: height))
        }
        guard let table = descendants(view).compactMap({ $0 as? NSTableView }).first,
              let progress = descendants(view).compactMap({ $0 as? NSProgressIndicator }).first else {
            fatalError("Missing native refinement table/progress fixture")
        }
        func type(_ query: String) {
            view.searchField.stringValue = query
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
            view.layoutSubtreeIfNeeded()
        }
        func finish(_ results: [FileSearchResult]) {
            fixture.finish(fixture.requests.count - 1, results: results)
            view.layoutSubtreeIfNeeded()
        }
        let draft = document("report-draft.pdf")
        let final = document("report-final.pdf")
        let reference = document("reference.txt")
        let newlyFound = document("report-000.pdf")
        check(!model.isSearchingFiles && progress.isHidden, "No file progress indicator runs before a request")
        type("f re")
        check(model.isSearchingFiles && !progress.isHidden, "A pending file request exposes native progress immediately")
        finish([final, draft, reference])
        check(!model.isSearchingFiles && progress.isHidden && table.numberOfRows == 3,
              "Completion hides progress and renders its file rows")
        let originalHeight = view.preferredHeight
        let requestCount = fixture.requests.count
        type("f report")
        check(fixture.requests.count == requestCount + 1 && model.isSearchingFiles,
              "A refined filename starts one fresh request without debounce")
        check(model.results == [.file(draft), .file(final)] && table.numberOfRows == 2,
              "Matching visible rows remain available while a refined query loads; nonmatching rows disappear")
        check(!progress.isHidden && view.preferredHeight == originalHeight,
              "Pending refinement retains panel height and shows progress without adding a status row")
        let retainedResults = model.results
        model.select(final.id)
        check(model.selectedResult == .file(final) && table.selectedRow == 1,
              "Keyboard selection can move to a retained result during an index request")
        finish([newlyFound, final, draft])
        check(model.results == retainedResults && model.selectedResult == .file(final) && table.selectedRow == 1,
              "Once a retained row is selected, completion cannot reorder rows or numbered shortcuts")
        check(!model.isSearchingFiles && progress.isHidden && view.preferredHeight < originalHeight,
              "The completed retained list hides progress and adopts its final height")

        let completedRequests = fixture.requests.count
        type("F   report   ")
        check(fixture.requests.count == completedRequests && !model.isSearchingFiles && progress.isHidden,
              "Changing prefix case or outer whitespace does not restart a completed filename request")
        type("f repor")
        let pendingRequests = fixture.requests.count
        type("F    repor  ")
        check(fixture.requests.count == pendingRequests && model.isSearchingFiles && !progress.isHidden,
              "Equivalent filename edits also reuse an in-flight request")
        finish([newlyFound, final, draft])
        check(model.results == [.file(newlyFound), .file(final), .file(draft)],
              "The next filename edit releases the pinned ordering and accepts fresh results")

        let settledHeight = view.preferredHeight
        type("f invoice")
        let supersededRequest = fixture.requests.count - 1
        check(model.results.isEmpty && table.numberOfRows == 0 && model.isSearchingFiles,
              "An unrelated filename never leaves old files selectable")
        check(view.preferredHeight == settledHeight && !progress.isHidden,
              "A pending query with no retained matches still avoids collapsing the panel")
        type("f invoices")
        fixture.finish(supersededRequest, results: [draft])
        check(model.results.isEmpty && model.isSearchingFiles && !progress.isHidden,
              "A stale callback cannot hide the active progress indicator or revive removed rows")
        let invoice = document("invoices-2026.txt")
        let nextInvoice = document("invoices-2027.txt")
        finish([invoice, nextInvoice])
        check(model.results == [.file(invoice), .file(nextInvoice)] && !model.isSearchingFiles && progress.isHidden,
              "The latest unrelated query replaces its pending state normally")

        type("f invoices-2")
        model.select(nextInvoice.id)
        let resetRequest = fixture.requests.count - 1
        check(!progress.isHidden && model.selectedResult == .file(nextInvoice),
              "A retained selection is pinned while progress is visible before reset")
        model.reset()
        fixture.finish(resetRequest, results: [invoice])
        check(model.query.isEmpty && model.results.isEmpty && !model.isSearchingFiles && progress.isHidden,
              "Reset clears retained rows, pinning and native progress, ignoring late callbacks")
        check(view.preferredHeight == 56, "Reset restores the compact empty launcher height")

        type("f annual")
        let suspendedRequest = fixture.requests.count - 1
        model.suspendFileSearch()
        check(!model.isSearchingFiles && progress.isHidden,
              "Suspending file search stops native progress immediately")
        fixture.finish(suspendedRequest, results: [invoice])
        check(model.results.isEmpty && !model.isSearchingFiles && progress.isHidden,
              "Suspended callbacks cannot restart progress or publish rows")
        let beforeResume = fixture.requests.count
        model.resumeFileSearch()
        model.resumeFileSearch()
        check(fixture.requests.count == beforeResume + 1 && model.isSearchingFiles && !progress.isHidden,
              "Resume creates exactly one fresh request and restarts progress")
        let annualPDF = document("annual-report.pdf")
        let annualText = document("annual-report.txt")
        finish([annualPDF, annualText])
        check(!model.isSearchingFiles && progress.isHidden && model.results == [.file(annualPDF), .file(annualText)],
              "Resumed completion restores files and stops the indicator")

        // Model callbacks cancel action work in the controller. Simulate that
        // callback explicitly so status clearing is part of one input update.
        let render = model.onChange
        var notifications = 0
        model.onChange = { notifications += 1; render?() }
        model.onQueryChange = { model.actionStatus = nil }
        model.launchError = "Synthetic previous launch error"
        model.actionStatus = "Synthetic pending action"
        notifications = 0
        type("f annual-report")
        check(notifications == 1 && model.launchError == nil && model.actionStatus == nil,
              "Typing clears launch/action statuses and publishes one coherent synchronous update")
        finish([annualPDF, annualText])
        model.onSelectionChange = { model.actionStatus = nil }
        model.actionStatus = "Synthetic pending copy"
        notifications = 0
        model.select(annualText.id)
        check(notifications == 1 && model.actionStatus == nil && model.selectedResult == .file(annualText),
              "Selection plus action cancellation also publishes a single coherent update")
        type("f annual-report.")
        type("ordinary application query")
        check(!model.isFileSearch && !model.isSearchingFiles && progress.isHidden,
              "Leaving file mode stops the indicator as well as the background request")
        model.onQueryChange = nil
        model.onSelectionChange = nil
        model.reset()
        check(view.window == nil, "Refinement checks never create or display a window")
    }
}
