import AppKit
import Carbon
import CueCore

@MainActor private final class HistoryFileSearch: FileSearching {
    var completion: (@MainActor (FileSearchResponse) -> Void)?
    func search(_ term: String, limit: Int, completion: @escaping @MainActor (FileSearchResponse) -> Void) {
        self.completion = completion
    }
    func cancel() {}
}

@main struct CheckCommandHistory {
    @MainActor static var checks = 0
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else {
            FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
            exit(1)
        }
        checks += 1
    }
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.mainMenu = nil
        let domain = "com.yyhsiu.cue.tests.history.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        defer { defaults.removePersistentDomain(forName: domain) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        let clipboard = ClipboardModel(defaults: defaults, fileURL: directory.appendingPathComponent("clipboard.json"),
                                       pasteboardName: board.name)
        defer { clipboard.stop() }
        let history = CommandHistoryModel(defaults: defaults)
        let apps = ["Fixture Alpha", "Fixture Beta"].map {
            IndexedApplication(name: $0, url: directory.appendingPathComponent($0 + ".app"))
        }
        let model = LauncherModel(applications: apps)
        var launched: [String] = []
        var handedOff: [URL] = []
        let controller = LauncherPanelController(
            clipboard: clipboard, model: model, commandHistory: history,
            performSystemAction: { _ in },
            openApplication: { application, done in launched.append(application.name); done(nil) },
            openFile: { _, done in done(nil) },
            webSearchPreferences: WebSearchPreferences(defaults: defaults),
            openWebURL: { url, _, done in handedOff.append(url); done(nil) },
            resolveBrowser: { _ in nil }, frontmostProcess: { nil }, restoreSource: { _ in false })
        let panel = app.windows.first { $0.contentView is LauncherView }!
        let view = panel.contentView as! LauncherView
        let editor = NSTextView()
        func key(_ code: UInt16, characters: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                            windowNumber: panel.windowNumber, context: nil, characters: characters,
                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        func submit() { _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) }
        controller.prepareInvocation()
        model.setQuery("draft never executed")
        controller.dismiss(returnFocus: false)
        check(history.history.entries.isEmpty, "Draft/cancel must never be recorded")
        model.setQuery("Fixture")
        model.select(LauncherResult.application(apps[1]).id)
        submit()
        check(launched == ["Fixture Beta"], "Injected app launch must execute once")
        check(history.history.entries.first?.query == "Fixture", "Executed input must be recorded")
        controller.prepareInvocation()
        check(model.query.isEmpty && model.results.isEmpty, "Reopening stays completely blank")
        _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
        check(model.query == "Fixture" && model.selectedResult == .application(apps[1]),
              "Up must restore the selected app, not the new first match")
        _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        check(model.query.isEmpty, "Down past newest returns to the blank input")
        _ = controller.recallPreviousCommand()
        var editRenders = 0
        let render = model.onChange
        model.onChange = { editRenders += 1; render?() }
        view.searchField.stringValue = "Fixture A"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        model.onChange = render
        check(editRenders == 1, "The first edit must render once without restoring the old query or caret")
        check(!model.isRecallingHistory, "Typing must end recall")
        _ = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
        check(model.query == "Fixture A", "Normal arrows must continue selecting search results")
        model.reset()
        editor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let consumed = view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
        check(!consumed && model.query.isEmpty, "IME composition must own arrow keys")
        editor.unmarkText()

        model.setQuery("private fixture search")
        check(view.handleWebSearchShortcut(key(UInt16(kVK_Return), characters: "\r")), "Google shortcut routes")
        check(handedOff.count == 1 && history.history.entries.first?.query == "private fixture search",
              "Explicit Google handoff records its input without real networking")
        let countBefore = history.history.entries.count
        history.setEnabled(false)
        model.setQuery("Fixture A"); submit()
        check(history.history.entries.count == countBefore, "Recording off excludes all new actions")
        check(!CommandHistoryModel(defaults: defaults).isEnabled, "Recording preference persists independently")
        history.setEnabled(true)
        history.record(.translateGPT, query: "Synthetic GPT text")
        _ = controller.recallPreviousCommand()
        check(model.selectedResult == .translateGPT, "GPT recall must restore translation without calling an API")
        model.recall(CommandHistoryEntry(query: "missing fixture", actionID: "app:missing", title: "Missing"))
        check(model.selectedResult == nil && model.historyStatus != nil,
              "A missing action must not silently fall back to Google")
        model.moveSelection(by: 1)
        check(model.selectedResult == model.results.first, "User can explicitly choose the first replacement")

        let files = HistoryFileSearch()
        let fileModel = LauncherModel(fileSearch: files)
        let first = FileSearchResult(url: directory.appendingPathComponent("first.txt"), name: "first.txt",
                                     parentPath: directory.path, isDirectory: false)
        let original = FileSearchResult(url: directory.appendingPathComponent("original.txt"), name: "original.txt",
                                        parentPath: directory.path, isDirectory: false)
        fileModel.recall(CommandHistoryEntry(query: "f txt", actionID: original.id, title: original.name))
        check(fileModel.selectedResult == nil, "Pending file recall must not execute stale results")
        files.completion?(FileSearchResponse(results: [first, original], error: nil))
        check(fileModel.selectedResult == .file(original), "Async file recall selects the original file, not row one")
        fileModel.recall(CommandHistoryEntry(query: "f gone", actionID: original.id, title: original.name))
        files.completion?(FileSearchResponse(results: [first], error: nil))
        check(fileModel.selectedResult == nil, "Missing files must stay unselected after async results arrive")
        model.setQuery("history")
        check(model.results.first == .commandHistory, "History command must be discoverable")
        submit()
        check(panel.contentView is CommandHistoryView, "History page must open")
        check(history.history.entries.count == countBefore + 1, "Opening history must not record itself")

        var recalled: CommandHistoryEntry?
        let historyPage = CommandHistoryView(model: history, onUse: { recalled = $0 }, onBack: {})
        let testWindow = NSPanel(contentRect: historyPage.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        testWindow.isReleasedWhenClosed = false; testWindow.contentView = historyPage
        historyPage.open()
        testWindow.setContentSize(NSSize(width: 640, height: historyPage.preferredHeight))
        historyPage.layoutSubtreeIfNeeded()
        for scroll in historyPage.subviews.compactMap({ $0 as? NSScrollView }) {
            check(!scroll.hasVerticalScroller, "History never displays a scrollbar")
            check((scroll.documentView as? NSTableView)?.numberOfRows ?? 10 <= 9, "At most nine history rows")
        }
        check(historyPage.handleKeyEquivalent(key(UInt16(kVK_ANSI_1), characters: "1")), "Number shortcut selects a history row")
        check(recalled?.query == "Synthetic GPT text", "History row restores input without executing it")
        historyPage.searchField.stringValue = "private fixture"
        historyPage.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        _ = historyPage.handleKeyEquivalent(key(UInt16(kVK_ANSI_1), characters: "1"))
        check(recalled?.query == "private fixture search", "History search uses executed query text")
        _ = historyPage.handleKeyEquivalent(key(UInt16(kVK_Delete)))
        check(!history.history.entries.contains { $0.query == "private fixture search" }, "Delete removes only selected history")
        historyPage.searchField.stringValue = ""
        historyPage.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        try snapshot(historyPage, name: "history")
        _ = historyPage.handleKeyEquivalent(key(UInt16(kVK_ANSI_Comma), characters: ","))
        testWindow.setContentSize(NSSize(width: 640, height: historyPage.preferredHeight))
        historyPage.layoutSubtreeIfNeeded()
        try snapshot(historyPage, name: "history-settings")
        historyPage.close()
        controller.dismiss(returnFocus: false)
        history.clear()
        check(history.history.entries.isEmpty, "Clear all removes cached history too")
        await history.finish()

        let pages = CommandHistoryModel()
        for index in 0..<12 { pages.record(.googleSearch, query: "page \(index)") }
        let pagedView = CommandHistoryView(model: pages, onUse: { recalled = $0 }, onBack: {})
        pagedView.open()
        for _ in 0..<9 {
            _ = pagedView.control(pagedView.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        }
        _ = pagedView.handleKeyEquivalent(key(UInt16(kVK_ANSI_1), characters: "1"))
        check(recalled?.query == "page 2", "Down past nine rows moves to the next page")
        _ = pagedView.control(pagedView.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
        _ = pagedView.control(pagedView.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check(recalled?.query == "page 3", "Up at the next page returns to the previous page's last row")
        _ = pagedView.control(pagedView.searchField, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
        check(!pages.history.entries.contains { $0.query == "page 3" }, "Plain Delete removes a row when history search is empty")
        pagedView.close()

        let store = CommandHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        let pending = CommandHistoryModel(store: store)
        pending.start()
        pending.record(.googleSearch, query: "synthetic before clear")
        pending.clear()
        pending.record(.translateGPT, query: "synthetic after clear")
        await pending.finish()
        let saved = await store.load()
        check(saved.entries.map(\.query) == ["synthetic after clear"]
              && pending.history == saved, "Pending load/write operations must not resurrect cleared history")
        check(!app.isActive && app.windows.allSatisfy { !$0.isVisible }, "Checks must never activate/show windows")
        print("Command history passed: \(checks) isolated routing, recall, privacy, IME, search and deletion checks.")
    }

    @MainActor private static func snapshot(_ view: NSView, name: String) throws {
        guard let destination = ProcessInfo.processInfo.environment["CUE_HISTORY_PREVIEW_DIRECTORY"] else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let directory = URL(fileURLWithPath: destination).appendingPathComponent(Bundle.main.preferredLocalizations.first ?? "en")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
