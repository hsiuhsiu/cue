import AppKit
import CueCore

/// Models an asynchronous clipboard writer without touching the general board.
/// Cancellation is checked at the actual write boundary, just as in production.
private actor CalculatorCopyFixture {
    private let name: NSPasteboard.Name
    private var suspended = false
    private var failure = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var attempts = 0
    private(set) var completed = 0
    private(set) var writes: [String] = []

    init(name: NSPasteboard.Name) { self.name = name }

    func configure(suspended: Bool = false, failure: Bool = false) {
        self.suspended = suspended
        self.failure = failure
    }

    func copy(_ value: String) async throws {
        attempts += 1
        defer { completed += 1 }
        let failure = failure
        if suspended { await withCheckedContinuation { waiters.append($0) } }
        try Task.checkCancellation()
        if failure { throw CocoaError(.fileWriteUnknown) }
        let item = NSPasteboardItem()
        guard item.setString(value, forType: .string) else { throw CocoaError(.fileWriteUnknown) }
        let board = NSPasteboard(name: name)
        try Task.checkCancellation()
        board.clearContents()
        guard board.writeObjects([item]) else { throw CocoaError(.fileWriteUnknown) }
        writes.append(value)
    }

    func resume() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

/// The mathematical grammar is covered by CueCore tests. This harness covers
/// immediate native result updates and the explicit, cancellable copy action.
@main struct CheckCalculator {
    @MainActor static var checks = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor static func eventually(_ message: String, _ condition: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await condition() { check(true, message); return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(false, message)
    }

    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    static func calculation(_ result: LauncherResult?) -> CalculatorResult? {
        guard case .calculation(let value) = result else { return nil }
        return value
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.mainMenu = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cue-calculator-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let domain = "com.yyhsiu.cue.tests.calculator.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        try await checkCopyService(board)
        let clipboard = ClipboardModel(defaults: defaults, fileURL: folder.appendingPathComponent("clipboard.json"), pasteboardName: board.name)
        defer { clipboard.stop() }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let webPreferences = WebSearchPreferences(defaults: defaults)
        webPreferences.setEnabled(false)
        let copy = CalculatorCopyFixture(name: board.name)
        let password = IndexedApplication(name: "1Password", url: URL(fileURLWithPath: "/Synthetic/1Password.app"))
        let alternatives = (1...2).map {
            IndexedApplication(name: "1+1 Fixture \($0)", url: URL(fileURLWithPath: "/Synthetic/MathFixture\($0).app"))
        }
        let usageURL = folder.appendingPathComponent("usage.json")
        let store = SearchUsageStore(fileURL: usageURL)
        let icons = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil })
        let model = LauncherModel(applications: [password] + alternatives, usageStore: store, icons: icons)
        var opened: [IndexedApplication] = []
        var settings = 0
        var restored: [Int32] = []
        let controller = LauncherPanelController(
            clipboard: clipboard, model: model,
            performSystemAction: { _ in fatalError("Unexpected system action") },
            openApplication: { app, completion in opened.append(app); completion(nil) },
            webSearchPreferences: webPreferences,
            openWebURL: { _, _, _ in fatalError("A calculator result must not open a browser") },
            resolveBrowser: { _ in fatalError("A calculator result must not resolve a browser") },
            copyCalculation: { try await copy.copy($0) },
            frontmostProcess: { nil }, restoreSource: { restored.append($0); return true }
        )
        controller.onSettings = { settings += 1 }
        guard let window = application.windows.last(where: { $0.contentView is LauncherView }),
              let view = window.contentView as? LauncherView,
              let table = descendants(view).compactMap({ $0 as? NSTableView }).first else {
            fatalError("Missing native launcher fixture")
        }
        defer { window.contentView = nil; window.close() }
        func key(_ code: UInt16, _ text: String, repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: text,
                             charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: code)!
        }
        func submit() {
            _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        }
        func type(_ query: String) {
            view.searchField.stringValue = query
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
            view.layoutSubtreeIfNeeded()
        }
        func firstCell() -> NSTableCellView {
            guard let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView else {
                fatalError("Missing calculator result cell")
            }
            return cell
        }

        board.clearContents()
        board.setString("untouched synthetic clipboard", forType: .string)
        let untouched = board.changeCount
        type("")
        check(model.results.isEmpty && view.preferredHeight == 56, "An empty invocation remains minimal")
        for query in ["42", "1", "1Password"] {
            type(query)
            check(!model.results.contains { calculation($0) != nil }, "Bare numbers and digit-prefixed app names are not calculations")
        }
        check(model.results.contains(.application(password)), "1Password remains a normal searchable app")
        let pending = LauncherModel(awaitingInitialIndex: true, icons: icons)
        pending.setAllowsWebSearch(false)
        pending.setQuery("(2 + 3) * 4")
        check(calculation(pending.selectedResult)?.value == "20", "Calculations are immediately available before the initial app index")
        pending.setQuery("ordinary unindexed app")
        check(pending.results.isEmpty, "Initial-index waiting still suppresses unmatched browser fallbacks")

        type("1+1")
        check(calculation(model.selectedResult)?.value == "2" && model.results.first?.id == "action:calculate",
              "A valid expression synchronously selects the stable calculator action")
        check(!policy.allowsNetwork && !model.allowsWebSearch && !model.results.contains(where: \.isWebSearch),
              "The calculator works with networking and browser search disabled")
        check(model.results.dropFirst() == alternatives.map(LauncherResult.application)[...],
              "Matching local applications remain available below the calculation")
        let originalID = model.selectedID
        check(firstCell().textField?.stringValue == "= 2", "The native row displays the exact calculation result")
        type("1+2")
        check(model.selectedID == originalID && firstCell().textField?.stringValue == "= 3",
              "Changing a result with the same action ID refreshes its visible value immediately")
        type("1/3")
        check(calculation(model.selectedResult)?.isApproximate == true
              && firstCell().textField?.stringValue.hasPrefix("≈ ") == true,
              "Approximate results are explicitly distinguished in the native row")
        for (expression, expected) in [("2^3", "8"), ("2**3", "8"), ("2^-3", "0.125"),
                                       ("2^3^2", "512"), ("(-2)^2", "4")] {
            type(expression)
            check(calculation(model.selectedResult)?.value == expected
                  && calculation(model.selectedResult)?.isApproximate == false
                  && firstCell().textField?.stringValue == "= " + expected,
                  "Power expression \(expression) updates its exact native result synchronously")
        }
        type("2^")
        check(!model.results.contains { calculation($0) != nil },
              "An unfinished exponent immediately removes the previous power result")
        type("2^3")
        check(calculation(model.selectedResult)?.value == "8" && firstCell().textField?.stringValue == "= 8",
              "Returning to a cached power expression restores its correct native value")
        type("2^0.5")
        guard let fractionalPower = calculation(model.selectedResult) else { fatalError("Missing fractional power fixture") }
        check(fractionalPower.isApproximate && fractionalPower.value.hasPrefix("1.4142")
              && firstCell().textField?.stringValue == "≈ " + fractionalPower.value,
              "A fractional power is visibly approximate instead of appearing as an exact decimal")
        let longExpression = "1.2345678901234567890123456789012345678+0"
        type(longExpression)
        guard let longResult = calculation(model.selectedResult) else { fatalError("Missing long exact result fixture") }
        let longTitle = "= " + longResult.value
        let longCell = firstCell()
        check(longResult.value.count > 30 && longCell.textField?.stringValue == longTitle
              && longCell.toolTip == longTitle,
              "A long value retains its complete native label and hover text even when visual space is limited")
        check(longCell.textField?.accessibilityValue() as? String == longTitle,
              "The full calculation value remains available to native accessibility")
        check(view.frame.width <= 640 && (longCell.textField?.frame.width ?? 0) > 0,
              "A long value does not enlarge the launcher or collapse its title area")
        for incomplete in ["1+", "1/0", "(2+3", "1+hello"] {
            type(incomplete)
            check(!model.results.contains { calculation($0) != nil }, "Invalid or incomplete edits remove the previous calculated value immediately")
        }
        type("1+2")
        check(calculation(model.selectedResult)?.value == "3" && firstCell().textField?.stringValue == "= 3",
              "Backspacing to a cached expression restores the correct native value")
        check(await copy.attempts == 0 && board.changeCount == untouched,
              "Typing and result rendering never read or write clipboard data")

        // A real field editor verifies provisional text does not execute a copy.
        window.makeFirstResponder(view.searchField)
        guard let editor = view.searchField.currentEditor() as? NSTextView else { fatalError("Missing calculator field editor") }
        editor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.string
        let range = editor.markedRange()
        check(!view.handleNumberShortcut(key(18, "1")), "Command-number does not execute a provisional IME expression")
        check(!view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))),
              "Return remains with the input method while text is marked")
        let attemptsDuringIME = await copy.attempts
        check(editor.string == marked && editor.markedRange() == range && attemptsDuringIME == 0,
              "Calculator keyboard handling preserves marked text and makes no copy request")
        editor.unmarkText()
        window.makeFirstResponder(nil)

        controller.prepareInvocation()
        type("(2 + 3) * 4")
        submit()
        await eventually("Return copies the result and dismisses the launcher") { await copy.writes == ["20"] && model.query.isEmpty }
        check(board.string(forType: .string) == "20" && board.data(forType: .html) == nil
              && board.data(forType: .URL) == nil, "The copy contains only the numeric result as plain text")
        check(opened.isEmpty && restored.isEmpty, "A hidden calculator submission performs no app launch, paste, or focus activation")
        check(await store.load() == .empty, "Calculator execution does not record the expression or result in ranking history")

        controller.prepareInvocation()
        type("1+2")
        check(view.handleNumberShortcut(key(18, "1")), "Command-1 routes through the same calculator copy action")
        await eventually("Command-1 copies the current result") { await copy.writes == ["20", "3"] && model.query.isEmpty }

        controller.prepareInvocation()
        type("1+1")
        await copy.configure(suspended: true)
        let beforeRepeat = await copy.attempts
        submit()
        await eventually("The repeat fixture begins one suspended copy") { await copy.attempts == beforeRepeat + 1 }
        submit()
        _ = view.handleNumberShortcut(key(18, "1"))
        _ = view.handleNumberShortcut(key(18, "1", repeated: true))
        check(await copy.attempts == beforeRepeat + 1, "Repeated Return and Command-1 cannot overlap a pending copy")
        await copy.resume()
        await eventually("The single pending copy completes") { model.query.isEmpty }
        check(await copy.writes == ["20", "3", "2"], "A repeated submission writes once")

        for reason in ["query", "dismiss", "new invocation", "selection", "settings", "browser actions", "focus loss"] {
            controller.prepareInvocation()
            type("1+1")
            await copy.configure(suspended: true)
            let attempts = await copy.attempts
            let completions = await copy.completed
            let writes = await copy.writes
            submit()
            await eventually("\(reason): a copy starts") { await copy.attempts == attempts + 1 }
            switch reason {
            case "query": type("8+1")
            case "dismiss": controller.dismiss(returnFocus: false)
            case "new invocation": controller.prepareInvocation()
            case "selection": model.moveSelection(by: 1)
            case "settings": _ = view.handleSettingsShortcut(key(43, ","))
            case "browser actions": model.toggleSearchActions()
            default:
                controller.apply(LauncherPreferences(dismissOnFocusLoss: false))
                window.orderFront(nil)
                controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
                window.orderOut(nil)
            }
            let query = model.query
            let selection = model.selectedID
            await copy.resume()
            await eventually("\(reason): the cancelled write settles") { await copy.completed == completions + 1 }
            check(await copy.writes == writes && model.query == query && model.selectedID == selection,
                  "\(reason): a cancelled copy never overwrites the clipboard or newer launcher state")
            check(model.launchError == nil && model.actionStatus == nil,
                  "\(reason): a cancelled copy publishes no stale failure or progress")
        }
        check(settings == 1, "Command-comma still opens the Cue-wide Settings callback")

        controller.prepareInvocation()
        type("1+1")
        await copy.configure(failure: true)
        let failedAttempts = await copy.attempts
        submit()
        await eventually("Clipboard failures produce visible feedback") { model.launchError?.isEmpty == false }
        check(await copy.attempts == failedAttempts + 1 && model.query == "1+1" && calculation(model.selectedResult)?.value == "2",
              "A failed copy keeps the expression and result available for retry")
        await copy.configure()
        submit()
        await eventually("Retrying a failed copy succeeds") { model.query.isEmpty }

        controller.prepareInvocation()
        type("1+1")
        let beforeApp = await copy.attempts
        check(view.handleNumberShortcut(key(19, "2")), "Numbered local-app alternatives remain executable after the calculator row")
        let afterApp = await copy.attempts
        check(opened == [alternatives[0]] && afterApp == beforeApp,
              "Command-2 opens its local app without copying the calculation")

        controller.prepareInvocation()
        type("2^3^2")
        let beforePowerCopy = await copy.writes
        check(view.handleNumberShortcut(key(18, "1")), "A numbered power result uses the explicit copy action")
        await eventually("The power result copies exactly and dismisses") {
            await copy.writes == beforePowerCopy + ["512"] && model.query.isEmpty
        }
        check(board.string(forType: .string) == "512" && board.data(forType: .html) == nil,
              "Copying a power writes only its evaluated value, not the expression or equality symbol")

        measureTyping(model: model, view: view)
        await model.prepareForTermination()
        check(await store.load() == .empty,
              "Choosing a matching app below the answer also leaves its calculation query out of usage history")
        if let bytes = try? Data(contentsOf: usageURL), let json = String(data: bytes, encoding: .utf8) {
            check(!json.contains("action:calculate") && !json.contains("(2 + 3) * 4")
                  && !json.contains("8+1") && !json.contains("2^3^2") && !json.contains("1+1"),
                  "Persisted usage excludes calculator actions and private expression-only searches")
        }
        await clipboard.prepareForTermination()
        controller.dismiss(returnFocus: false)
        check(!application.isActive && application.windows.allSatisfy { !$0.isVisible },
              "The integration harness finishes without an active or visible application window")
        print("Calculator passed: \(checks) checks; synchronous local/native results, keyboard and IME, private clipboard copy/cancellation, and no expression history. No general clipboard, browser, network, or synthetic paste.")
    }

    @MainActor private static func checkCopyService(_ board: NSPasteboard) async throws {
        let service = CalculatorCopyService(pasteboardName: board.name)
        let oldItem = NSPasteboardItem()
        oldItem.setString("old fixture", forType: .string)
        oldItem.setString("<b>old fixture</b>", forType: .html)
        board.clearContents()
        check(board.writeObjects([oldItem]), "The private pasteboard fixture contains stale rich content")
        try await service.copy("123.456")
        check(board.string(forType: .string) == "123.456" && board.pasteboardItems?.count == 1,
              "The real copy service writes exactly one numeric result to the injected pasteboard")
        check(board.data(forType: .html) == nil && board.data(forType: .URL) == nil,
              "The real copy service removes stale rich and URL representations")
        let changeCount = board.changeCount
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await service.copy("999")
        }
        do { try await cancelled.value; check(false, "A pre-cancelled copy must not commit") }
        catch is CancellationError { check(true, "A pre-cancelled copy must not commit") }
        catch { check(false, "Unexpected cancelled-copy error: \(error)") }
        check(board.changeCount == changeCount && board.string(forType: .string) == "123.456",
              "Cancellation at the real writer leaves newer clipboard content untouched")
    }

    @MainActor private static func measureTyping(model: LauncherModel, view: LauncherView) {
        // Same native path and work count, with distinct strings to include cold
        // parser/search/cache work. No brittle performance threshold assertions.
        func measure(_ name: String, expressions: Bool) {
            var input: [Double] = []
            var layout: [Double] = []
            for index in 0..<500 {
                let query: String
                if expressions {
                    switch index % 5 {
                    case 0: query = "(\(index + 1000)+3)*7/2"
                    case 1: query = "(\(index + 1000))^3"
                    case 2: query = "2^-3+\(index)"
                    case 3: query = "2^3^2+\(index)"
                    default: query = "(\(index + 2))^0.5"
                    }
                } else {
                    query = "synthetic ordinary app \(index)"
                }
                let start = DispatchTime.now().uptimeNanoseconds
                view.searchField.stringValue = query
                view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
                let updated = DispatchTime.now().uptimeNanoseconds
                view.layoutSubtreeIfNeeded()
                let finished = DispatchTime.now().uptimeNanoseconds
                input.append(Double(updated - start) / 1_000_000)
                layout.append(Double(finished - start) / 1_000_000)
            }
            input.sort(); layout.sort()
            print(String(format: "%@ (500 cold-query edits): input/search/table p50 %.3f ms, p95 %.3f, p99 %.3f, max %.3f; with forced AppKit layout p50 %.3f, p99 %.3f, max %.3f. Excludes OS input delivery and visible composition.", name, input[249], input[474], input[494], input[499], layout[249], layout[494], layout[499]))
            check(expressions ? calculation(model.selectedResult) != nil : calculation(model.selectedResult) == nil,
                  "The typing measurement completes with the correct final result kind")
        }
        measure("Calculator-gate bypass for ordinary text", expressions: false)
        measure("Valid arithmetic and power expressions", expressions: true)
    }
}
