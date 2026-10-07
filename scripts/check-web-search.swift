import AppKit
import CueCore

/// A controllable Launch Services substitute. Never reads installed apps or opens a browser.
private final class BrowserResolverFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var result: URL?
    private var gate: DispatchSemaphore?
    private var identifiers: [String] = []
    private var finished = 0
    private var usedMainThread = false

    func configure(result: URL?, suspended: Bool = false) -> DispatchSemaphore? {
        lock.lock()
        defer { lock.unlock() }
        self.result = result
        gate = suspended ? DispatchSemaphore(value: 0) : nil
        return gate
    }

    func resolve(_ identifier: String) -> URL? {
        lock.lock()
        identifiers.append(identifier)
        usedMainThread = usedMainThread || Thread.isMainThread
        let result = result
        let gate = gate
        lock.unlock()
        if let gate { _ = gate.wait(timeout: .now() + 5) }
        lock.lock()
        finished += 1
        lock.unlock()
        return result
    }

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return identifiers
    }
    var completed: Int {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
    var ranOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return usedMainThread
    }
}

/// Real launcher routing with synthetic apps, an isolated pasteboard/defaults, and injected handoffs.
@main struct CheckWebSearch {
    @MainActor static var checks = 0
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor static func eventually(_ message: String, _ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { check(true, message); return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(false, message)
    }

    @MainActor static func checkSettingsLayout(_ preferences: WebSearchPreferences,
                                              defaults: UserDefaults, domain: String) {
        let savedBefore = NSDictionary(dictionary: defaults.persistentDomain(forName: domain) ?? [:])
        let browsersBefore = preferences.browsers
        let enabledBefore = preferences.isEnabled
        let controller = WebSearchSettingsController(preferences: preferences)
        guard let window = controller.window, let content = window.contentView else {
            check(false, "Search settings must create their native window and content")
            return
        }
        defer { window.contentView = nil; window.close() }
        content.layoutSubtreeIfNeeded()
        let windowContentSize = window.contentRect(forFrameRect: window.frame).size
        let fittingSize = content.fittingSize
        check(windowContentSize == NSSize(width: 540, height: 500)
              && content.frame.size == NSSize(width: 540, height: 500),
              "Search settings retain a bounded 540×500 content area after native hosting layout")
        check(fittingSize.width.isFinite && fittingSize.height.isFinite
              && fittingSize.width > 0 && fittingSize.height > 0
              && fittingSize.width <= 540 && fittingSize.height <= 500,
              "SwiftUI settings must not report an unbounded intrinsic size to AppKit")
        check(!window.isVisible && !NSApp.isActive,
              "Constructing and measuring feature settings stays hidden and inactive")
        check(preferences.browsers == browsersBefore && preferences.isEnabled == enabledBefore
              && savedBefore.isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]),
              "Constructing and laying out feature settings must not mutate saved or in-memory preferences")
    }

    @MainActor static func checkPreferences(_ defaults: UserDefaults, domain: String) throws {
        func clear() {
            defaults.removeObject(forKey: WebSearchPreferences.enabledKey)
            defaults.removeObject(forKey: WebSearchPreferences.browsersKey)
        }
        clear()
        let fresh = WebSearchPreferences(defaults: defaults)
        check(fresh.isEnabled && fresh.browsers.isEmpty, "Fresh search is enabled with no automatically added browsers")
        checkSettingsLayout(fresh, defaults: defaults, domain: domain)
        var changes = 0
        fresh.onChange = { changes += 1 }
        fresh.setEnabled(true)
        check(changes == 0, "Saving an unchanged feature switch must not invalidate pending state")
        fresh.setEnabled(false)
        check(!WebSearchPreferences(defaults: defaults).isEnabled && changes == 1,
              "An explicit disabled choice persists and notifies once")
        fresh.setEnabled(false)
        check(changes == 1, "Repeated disabled writes must not emit redundant changes")
        for malformed in ["false", 0, 1, [false], ["enabled": false]] as [Any] {
            defaults.set(malformed, forKey: WebSearchPreferences.enabledKey)
            check(WebSearchPreferences(defaults: defaults).isEnabled, "Malformed stored switches must use the enabled feature default")
        }
        defaults.set(false, forKey: WebSearchPreferences.enabledKey)
        check(!WebSearchPreferences(defaults: defaults).isEnabled, "Only an actual saved Boolean false disables the feature")
        clear()
        let preferences = WebSearchPreferences(defaults: defaults)
        preferences.onChange = { changes += 1 }
        try preferences.add(WebSearchBrowser(bundleIdentifier: "  test.browser.first  ", name: "  第一個 Browser  "))
        check(preferences.browsers == [WebSearchBrowser(bundleIdentifier: "test.browser.first", name: "第一個 Browser")],
              "Added browser identifiers and display names are trimmed while Unicode names are retained")
        let afterAdd = changes
        try preferences.add(WebSearchBrowser(bundleIdentifier: "TEST.BROWSER.FIRST", name: "Duplicate"))
        preferences.remove(id: "test.missing")
        check(changes == afterAdd && preferences.browsers.count == 1, "Case-insensitive duplicates and unknown removals are no-ops")
        let invalid = [
            WebSearchBrowser(bundleIdentifier: "", name: "Browser"),
            WebSearchBrowser(bundleIdentifier: "test browser", name: "Browser"),
            WebSearchBrowser(bundleIdentifier: "test/browser", name: "Browser"),
            WebSearchBrowser(bundleIdentifier: "test.瀏覽器", name: "Browser"),
            WebSearchBrowser(bundleIdentifier: String(repeating: "x", count: 256), name: "Browser"),
            WebSearchBrowser(bundleIdentifier: "test.empty", name: " \n"),
            WebSearchBrowser(bundleIdentifier: "test.control", name: "Browser\u{0000}Name"),
            WebSearchBrowser(bundleIdentifier: "test.long", name: String(repeating: "界", count: 86))
        ]
        for browser in invalid {
            do { try preferences.add(browser); check(false, "Invalid browser metadata must be rejected") }
            catch { check(error as? WebSearchPreferences.ValidationError == .invalidBrowser, "Invalid metadata has a specific validation error") }
        }
        check(changes == afterAdd && preferences.browsers.count == 1, "Rejected entries leave preferences and callbacks unchanged")
        for index in 1..<WebSearchPreferences.maximumBrowsers {
            try preferences.add(WebSearchBrowser(bundleIdentifier: "test.browser.\(index)", name: "Browser \(index)"))
        }
        check(preferences.browsers.count == 8, "Curated choices are bounded at eight additional browsers")
        checkSettingsLayout(preferences, defaults: defaults, domain: domain)
        do {
            try preferences.add(WebSearchBrowser(bundleIdentifier: "test.browser.ninth", name: "Ninth"))
            check(false, "A ninth browser must be rejected")
        } catch { check(error as? WebSearchPreferences.ValidationError == .browserLimit, "The browser cap reports its specific validation error") }
        check(WebSearchPreferences(defaults: defaults).browsers == preferences.browsers, "Curated browser order survives reloading preferences")
        let stored = defaults.array(forKey: WebSearchPreferences.browsersKey) as? [[String: String]]
        check(stored?.first == ["bundleIdentifier": "test.browser.first", "name": "第一個 Browser"],
              "Storage contains stable identifiers and names, not local application paths")
        preferences.remove(id: "TEST.BROWSER.FIRST")
        check(preferences.browsers.count == 7 && !WebSearchPreferences(defaults: defaults).browsers.contains { $0.id == "test.browser.first" },
              "Case-insensitive removal persists immediately")
        var malformedEntries: [Any] = [
            "junk", 5, ["name": "No ID"], ["bundleIdentifier": "test.blank", "name": ""],
            ["bundleIdentifier": "test.good", "name": "First valid"],
            ["bundleIdentifier": "TEST.GOOD", "name": "Duplicate"],
            ["bundleIdentifier": "test.bad", "name": 7]
        ]
        malformedEntries += (0..<12).map { ["bundleIdentifier": "test.loaded.\($0)", "name": "Loaded \($0)"] }
        defaults.set(malformedEntries, forKey: WebSearchPreferences.browsersKey)
        let loaded = WebSearchPreferences(defaults: defaults)
        check(loaded.browsers.count == 8 && loaded.browsers.first?.name == "First valid"
              && loaded.browsers.last?.id == "test.loaded.6", "Malformed/duplicate stored entries are skipped and valid stored choices remain ordered and capped")
        clear()
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.mainMenu = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cue-web-search-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let domain = "com.yyhsiu.cue.tests.web-search.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        try checkPreferences(defaults, domain: domain)
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        let clipboard = ClipboardModel(defaults: defaults, fileURL: folder.appendingPathComponent("clipboard.json"), pasteboardName: board.name)
        defer { clipboard.stop() }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let preferences = WebSearchPreferences(defaults: defaults)
        let firstBrowser = WebSearchBrowser(bundleIdentifier: "test.browser.first", name: "First Browser")
        let secondBrowser = WebSearchBrowser(bundleIdentifier: "test.browser.second", name: "Second Browser")
        try preferences.add(firstBrowser)
        try preferences.add(secondBrowser)
        let store = SearchUsageStore(fileURL: folder.appendingPathComponent("usage.json"))
        let app = IndexedApplication(name: "Safari", url: URL(fileURLWithPath: "/Synthetic/Safari.app"))
        let boundedModel = LauncherModel(applications: [app])
        let oversizedChoices = (0..<12).map {
            WebSearchBrowser(bundleIdentifier: "test.bounded.\($0)", name: "Browser \($0)")
        }
        boundedModel.setWebSearchPreferences(enabled: true, browsers: oversizedChoices)
        boundedModel.setQuery("unmatched bounded browser choices")
        check(boundedModel.results == [.googleSearch, .askGPT, .translateGPT, .chooseSearchBrowser],
              "Many browser choices use a submenu without crowding out GPT or exceeding nine rows")
        boundedModel.setResultLimit(1)
        check(boundedModel.results == [.googleSearch], "The ordinary browser fallback respects a reduced result limit")
        boundedModel.toggleSearchActions()
        boundedModel.showSearchBrowsers()
        check(boundedModel.results.count == 9, "Explicit browser choices expose all eight curated browsers despite a reduced app result limit")
        check(boundedModel.results.last == .googleSearchIn(oversizedChoices[7]), "The last curated browser stays reachable")
        check(boundedModel.closeSearchActions() && boundedModel.isShowingSearchActions
              && boundedModel.results == [.googleSearch, .askGPT, .translateGPT, .chooseSearchBrowser],
              "Escape from browser choices preserves the query and returns to all text actions")
        let model = LauncherModel(applications: [app], usageStore: store)
        let resolver = BrowserResolverFixture()
        let browserURL = URL(fileURLWithPath: "/Synthetic/First Browser.app")
        var opened: [(url: URL, application: URL?)] = []
        var completions: [@MainActor (Error?) -> Void] = []
        var appLaunches = 0
        var sourceRestores = 0
        var searchSettings = 0
        var globalSettings = 0
        var gptSettings = 0
        var gptRequests: [(String, GPTMode)] = []
        let gpt = GPTModel(configuration: { GPTConfiguration() }, stream: { input, mode, _, delta in
            gptRequests.append((input, mode))
            delta("Synthetic reply / 測試回答")
        }, copier: { _ in })
        let controller = LauncherPanelController(
            clipboard: clipboard, model: model, gpt: gpt,
            performSystemAction: { _ in fatalError("Unexpected system action") },
            openApplication: { _, completion in appLaunches += 1; completion(nil) },
            webSearchPreferences: preferences,
            openWebURL: { url, appURL, completion in opened.append((url, appURL)); completions.append(completion) },
            resolveBrowser: { resolver.resolve($0) },
            frontmostProcess: { nil }, restoreSource: { _ in sourceRestores += 1; return true }
        )
        controller.onWebSearchSettings = {
            searchSettings += 1
            check(controller.suspendForSettings(), "Browser settings preserve the current invocation")
        }
        controller.onSettings = {
            globalSettings += 1
            check(controller.suspendForSettings(), "General settings preserve the current invocation")
        }
        controller.onGPTSettings = {
            gptSettings += 1
            check(controller.suspendForSettings(), "Opening GPT settings suspends the current invocation")
        }
        guard let window = application.windows.last(where: { $0.contentView is LauncherView }),
              let view = window.contentView as? LauncherView else { fatalError("Missing hidden launcher") }
        defer { window.contentView = nil; window.close() }
        func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = .command) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: characters,
                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        func submit() {
            _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        }
        func selectBrowser() {
            model.select(LauncherResult.googleSearchIn(firstBrowser).id)
            submit()
        }
        let pending = LauncherModel(awaitingInitialIndex: true)
        pending.setQuery("not indexed yet")
        check(pending.results.isEmpty, "An unknown initial index must not turn expected apps into external queries")
        check(!policy.allowsNetwork && model.allowsWebSearch, "Manual browser search is available while Cue-owned networking is disabled")
        let choices: [LauncherResult] = [.googleSearch, .askGPT, .translateGPT, .googleSearchIn(firstBrowser), .googleSearchIn(secondBrowser)]
        for value in ["", " ", "\n\t", "Cue Google 測試", "C++ & Swift #保留"] { model.setQuery(value) }
        check(opened.isEmpty && resolver.calls.isEmpty, "Typing and rendering never resolve a browser or hand text to one")
        check(model.results == choices && model.selectedResult == .googleSearch, "Unmatched queries show Google, GPT actions, and explicitly added browsers")
        model.select(LauncherResult.googleSearchIn(secondBrowser).id)
        preferences.remove(id: firstBrowser.id)
        check(model.results == [.googleSearch, .askGPT, .translateGPT, .googleSearchIn(secondBrowser)] && model.selectedResult == .googleSearchIn(secondBrowser),
              "Removing another browser invalidates cached fallback rows without shuffling the selected browser")
        try preferences.add(firstBrowser)
        check(model.results == [.googleSearch, .askGPT, .translateGPT, .googleSearchIn(secondBrowser), .googleSearchIn(firstBrowser)],
              "Re-added browser choices follow their newly saved order")
        preferences.remove(id: secondBrowser.id)
        try preferences.add(secondBrowser)
        let query = "  C++ & Swift #台灣  A+B  "
        model.setQuery(query)
        submit()
        check(opened.count == 1 && opened[0].application == nil && model.query.isEmpty,
              "Return hands the query to the system default exactly once and clears the launcher immediately")
        let components = URLComponents(url: opened[0].url, resolvingAgainstBaseURL: false)!
        check(components.queryItems == [URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespacesAndNewlines))],
              "The handoff retains original query text, not its normalized matching key")
        check(opened[0].url.absoluteString.contains("%2B") && !opened[0].url.absoluteString.contains("+"),
              "Google receives literal plus signs instead of spaces")
        check(sourceRestores == 0 && resolver.calls.isEmpty, "Default search neither restores the source app nor resolves a named browser")
        completions[0](nil)
        policy.setAllowsNetwork(true)
        policy.setAllowsNetwork(false)
        check(model.allowsWebSearch && preferences.isEnabled, "Changing Cue's network switch does not alter manual search preferences")
        model.setQuery("safari")
        check(model.selectedResult == .application(app), "Local app matches retain ordinary Return semantics")
        check(view.handleWebSearchShortcut(key(36, "\r")), "Command-Return is available even with an app selected")
        check(opened.count == 2 && opened.last?.application == nil && appLaunches == 0, "Explicit default search must not launch the selected app")
        model.setQuery("safari")
        submit()
        check(appLaunches == 1 && opened.count == 2, "Normal Return still launches the matching app")
        model.setQuery("unmatched private search phrase")
        check(view.handleNumberShortcut(key(18, "1")) && opened.count == 3, "Command-1 executes exactly one default-browser handoff")
        controller.prepareInvocation()
        model.setQuery("newer query must remain")
        completions[2](NSError(domain: "CueWebSearchFixture", code: 1))
        check(model.query == "newer query must remain" && model.launchError == nil && !window.isVisible,
              "A stale failure cannot replace input from a newer invocation or reopen the panel")

        // Feature-local settings, independent of Cue-wide networking, are authoritative.
        preferences.setEnabled(false)
        check(!model.allowsWebSearch && model.results == choices, "Disabling search refreshes the cached choices without removing access to their settings")
        model.setWebSearchPreferences(enabled: true, browsers: preferences.browsers)
        submit()
        _ = view.handleWebSearchShortcut(key(36, "\r"))
        _ = view.handleNumberShortcut(key(21, "4"))
        check(opened.count == 3 && resolver.calls.isEmpty && model.launchError == LauncherText.shared.webSearchDisabled,
              "A stale presentation flag cannot bypass the authoritative feature switch through any execution path")
        check(view.handleSettingsShortcut(key(43, ",")) && searchSettings == 1 && globalSettings == 0,
              "Command-comma on a disabled browser choice opens feature settings")
        preferences.setEnabled(true)
        check(model.allowsWebSearch && model.launchError == nil, "Re-enabling the feature clears its disabled state")
        check(controller.restoreSettingsContext() && model.query == "newer query must remain",
              "Returning from browser settings preserves the original query without a browser handoff")
        model.setQuery("google search settings")
        check(model.selectedResult == .webSearchSettings, "Feature settings remain searchable as a command")
        submit()
        check(searchSettings == 2 && opened.count == 3, "The settings command opens its own page without a browser handoff")
        check(controller.restoreSettingsContext() && model.query == "google search settings",
              "Closing searchable browser settings restores its invocation")
        model.setQuery("safari")
        _ = view.handleSettingsShortcut(key(43, ","))
        check(globalSettings == 1 && searchSettings == 2, "Command-comma on local apps keeps Cue-wide Settings")
        check(controller.restoreSettingsContext() && model.selectedResult == .application(app),
              "General settings return keeps the selected application")

        // Named browser resolution is asynchronous, explicit, and cancellable.
        _ = resolver.configure(result: browserURL)
        model.setQuery(query)
        selectBrowser()
        check(model.actionStatus == LauncherText.shared.openingBrowser && opened.count == 3,
              "Named searches acknowledge the action before background resolution completes")
        await eventually("Named browser handoff completes", { opened.count == 4 })
        check(opened[3].application == browserURL && opened[3].url == opened[0].url && resolver.calls == [firstBrowser.id],
              "A curated action hands the original query to exactly its resolved app")
        check(!resolver.ranOnMainThread && model.actionStatus == nil && model.query.isEmpty,
              "Browser resolution stays off the input thread and clears its progress after handoff")
        completions[3](nil)
        _ = resolver.configure(result: nil)
        model.setQuery("missing browser search")
        selectBrowser()
        await eventually("Missing browser resolution finishes", { model.actionStatus == nil })
        check(opened.count == 4 && model.query == "missing browser search"
              && model.launchError == L10n.format(LauncherText.shared.browserUnavailable, firstBrowser.name),
              "An unavailable curated browser shows a useful error without silently falling back or losing the query")

        for cancellation in ["query", "remove", "disable", "dismiss", "invocation", "actions", "browser back"] {
            if !preferences.isEnabled { preferences.setEnabled(true) }
            if !preferences.browsers.contains(firstBrowser) { try preferences.add(firstBrowser) }
            controller.prepareInvocation()
            model.setQuery("cancel \(cancellation) browser search")
            if cancellation == "browser back" { model.showSearchBrowsers() }
            let beforeCalls = resolver.calls.count
            let beforeFinished = resolver.completed
            let beforeOpened = opened.count
            let gate = resolver.configure(result: browserURL, suspended: true)!
            selectBrowser()
            await eventually("\(cancellation): background resolution starts", { resolver.calls.count == beforeCalls + 1 })
            submit()
            check(resolver.calls.count == beforeCalls + 1, "\(cancellation): repeated submit must not create a second resolver")
            switch cancellation {
            case "query": model.setQuery("newer typed query")
            case "remove": preferences.remove(id: firstBrowser.id)
            case "disable": preferences.setEnabled(false)
            case "dismiss": controller.dismiss(returnFocus: false)
            case "invocation": controller.prepareInvocation()
            case "browser back": _ = model.closeSearchActions()
            default: model.toggleSearchActions()
            }
            let preservedQuery = model.query
            check(model.actionStatus == nil, "\(cancellation): cancelling a pending handoff clears its progress immediately")
            gate.signal()
            await eventually("\(cancellation): blocked fixture exits", { resolver.completed == beforeFinished + 1 })
            // Only this synthetic worker is delayed; allow its cancelled main-actor continuation to drain.
            try await Task.sleep(for: .milliseconds(25))
            check(opened.count == beforeOpened && model.query == preservedQuery && model.launchError == nil,
                  "\(cancellation): late resolution must not open a browser, overwrite input, or report a stale error")
        }
        check(!resolver.ranOnMainThread, "Every named-browser lookup ran outside the main thread")
        preferences.setEnabled(true)
        controller.prepareInvocation()
        model.setQuery("stale completion before new typing")
        _ = view.handleWebSearchShortcut(key(36, "\r"))
        let lastCompletion = completions.last!
        model.setQuery("preserve newer direct typing")
        lastCompletion(NSError(domain: "CueWebSearchFixture", code: 2))
        check(model.query == "preserve newer direct typing" && model.launchError == nil && !window.isVisible,
              "A failed browser completion cannot overwrite newer typing in the same invocation")
        model.setQuery("stale completion before disabling")
        _ = view.handleWebSearchShortcut(key(36, "\r"))
        let disabledCompletion = completions.last!
        preferences.setEnabled(false)
        disabledCompletion(NSError(domain: "CueWebSearchFixture", code: 3))
        check(model.query.isEmpty && model.launchError == nil && !window.isVisible,
              "Disabling search also invalidates pending browser failure callbacks")
        model.setQuery("safari")
        submit()
        check(appLaunches == 2, "Disabling web search leaves local app launching available")
        for value in ["", "  \n", "\u{3000}"] {
            model.setQuery(value)
            _ = view.handleWebSearchShortcut(key(36, "\r"))
            _ = view.handleSearchActionsShortcut(key(40, "k"))
            submit()
            check(model.results.isEmpty && model.launchError == nil && !model.isShowingSearchActions,
                  "Blank queries neither offer nor execute web actions")
        }

        // Shared text actions route to the native answer page only on execution.
        model.setQuery("Private GPT fixture text"); model.toggleSearchActions()
        check(gptRequests.isEmpty, "Typing and opening text actions never starts GPT work")
        check(view.handleNumberShortcut(key(19, "2")), "Command-2 executes the GPT answer action")
        await eventually("Explicit answer reaches the injected GPT worker once") { gptRequests.count == 1 && !gpt.isLoading }
        check(gptRequests[0].0 == "Private GPT fixture text" && gptRequests[0].1 == .answer,
              "The answer receives the exact original query and explicit question mode")
        guard let answerView = window.contentView as? GPTView else { fatalError("Missing native GPT answer view") }
        check(answerView.handleKeyEquivalent(key(53, "", modifiers: [])) && window.contentView === view
              && model.query == "Private GPT fixture text" && gpt.output.isEmpty,
              "Escape clears the answer and returns to the unchanged original query")
        check(view.handleNumberShortcut(key(20, "3")), "Command-3 executes translation")
        await eventually("Explicit translation reaches the GPT worker once") { gptRequests.count == 2 && !gpt.isLoading }
        check(gptRequests[1].1 == .translate, "Translation uses its own mode, not question answering")
        check(answerView.handleKeyEquivalent(key(43, ",")) && gptSettings == 1,
              "Command-comma from the answer opens GPT-specific settings")
        check(controller.isSuspendedForSettings && !gpt.isPresented
              && model.query == "Private GPT fixture text" && gpt.output == "Synthetic reply / 測試回答",
              "Settings preserve exact question and reply without a visible panel")
        check(controller.restoreSettingsContext() && gpt.isPresented && window.contentView === answerView
              && gptRequests.count == 2,
              "Returning from settings restores the reply page without another request or activation")
        check(!controller.restoreSettingsContext(), "An old settings close cannot reopen an already restored context")
        controller.dismiss(returnFocus: false)
        check(!gpt.isPresented && gpt.input.isEmpty && gpt.output.isEmpty,
              "Dismissing Cue clears both GPT input and response")
        model.setQuery("gpt settings")
        check(model.selectedResult == .gptSettings, "GPT settings is locally searchable")
        submit()
        check(gptSettings == 2 && gptRequests.count == 2, "Opening GPT settings does not submit a question")
        controller.prepareInvocation()
        check(!controller.restoreSettingsContext() && model.query.isEmpty,
              "A new invocation invalidates an older settings return")

        // Guard future call sites as well as the actual controller handoff path.
        let privateStore = SearchUsageStore(fileURL: folder.appendingPathComponent("private-usage.json"))
        let privateModel = LauncherModel(usageStore: privateStore)
        for result in choices {
            privateModel.recordSuccessfulAction(resultID: result.id, query: "private web-only phrase")
        }
        await privateModel.prepareForTermination()
        let privateUsage = await privateStore.load()
        check(privateUsage == .empty, "Google and GPT actions stay out of learned usage history")
        await model.prepareForTermination()
        if let data = try? Data(contentsOf: folder.appendingPathComponent("usage.json")), let text = String(data: data, encoding: .utf8) {
            check(!text.contains("private search") && !text.contains("C++") && !text.contains("action:google-search"),
                  "The actual handoff flow never persists arbitrary Google queries in search-learning data")
        }
        // Cold synthetic queries exercise real AppKit field/model/table updates.
        // This reports computation only, without timing-based pass/fail assertions.
        let handoffsBeforeTyping = opened.count
        let resolutionsBeforeTyping = resolver.calls.count
        var times: [Double] = []
        for index in 0..<500 {
            let start = DispatchTime.now().uptimeNanoseconds
            view.searchField.stringValue = "臺灣 C++ question \(index)"
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
            view.layoutSubtreeIfNeeded()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        times.sort()
        check(opened.count == handoffsBeforeTyping && resolver.calls.count == resolutionsBeforeTyping,
              "Typing/rendering with curated browsers performs neither external handoffs nor browser discovery")
        check(!application.isActive && !window.isVisible, "Checks remain hidden and never take focus")
        await clipboard.prepareForTermination()
        print("Web search passed: \(checks) checks; curated preferences, offline-independent manual handoffs, async cancellation, and private usage; zero real browser requests.")
        print(String(format: "Offscreen AppKit input/render (500 edits): p95 %.3f ms, p99 %.3f ms, max %.3f ms. Excludes OS input delivery and visible composition.", times[474], times[494], times[499]))
    }
}
