import AppKit
import CueCore

/// Exercise AppKit's key-equivalent path using the real launcher, without a menu fallback.
/// All events stay in this process. No windows are shown, app preferences changed, or keys posted.
@main
struct CheckLauncherKeyboard {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.mainMenu = nil

        let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("cue-shortcut-fixtures-\(UUID().uuidString)")
        let applications = (1...10).map { number in
            IndexedApplication(name: String(format: "Shortcut Fixture %02d", number),
                               url: fixtureDirectory.appendingPathComponent("\(number).app"))
        }
        let model = LauncherModel(applications: applications)
        var settingsActions = 0
        var otherActions = 0
        var webActions: [String] = []
        var searchActions = 0
        var submittedIDs: [String] = []
        let view = LauncherView(
            model: model,
            onSubmit: {
                otherActions += 1
                if let id = model.selectedResult?.id { submittedIDs.append(id) }
            },
            onCancel: { if !model.closeSearchActions() { otherActions += 1 } },
            onSettings: { settingsActions += 1 },
            onWebSearch: { webActions.append(model.query) },
            onSearchActions: { searchActions += 1; model.toggleSearchActions() }
        )
        let window = NSPanel(
            contentRect: view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view

        var failures: [String] = []
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { failures.append(message) }
        }
        func key(
            _ characters: String = ",",
            modifiers: NSEvent.ModifierFlags = .command,
            keyCode: UInt16 = 43,
            repeated: Bool = false
        ) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: repeated, keyCode: keyCode
            )!
        }
        func route(_ event: NSEvent) -> Bool {
            // AppKit may create its default menu lazily when it starts field editing.
            // Remove it before every event so the view must handle the shortcut itself.
            application.mainMenu = nil
            return view.performKeyEquivalent(with: event)
        }
        func expectSettings(_ event: NSEvent, context: String) {
            let before = settingsActions
            let query = model.query
            let handled = route(event)
            expect(handled, "\(context): key equivalent must be consumed")
            expect(settingsActions == before + 1,
                   "\(context): Settings must fire exactly once before the handler returns")
            expect(model.query == query, "\(context): routing must not edit the query")
        }

        expect(model.query.isEmpty && model.results.isEmpty && model.selectedID == nil,
               "Initial launcher must be blank even with a populated application index")
        expect(view.searchField.placeholderString?.isEmpty != false,
               "The initial input must have no visible search prompt")
        expect(view.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden && !$0.stringValue.isEmpty }.isEmpty,
               "An idle launcher must not show branding, Escape, keyboard, or search instructions")
        expect(view.subviews.compactMap { $0 as? NSButton }.isEmpty,
               "The minimal launcher must not reserve a footer Settings button")
        expect(view.subviews.compactMap { $0 as? NSImageView }.isEmpty,
               "The initial input must not show a search icon")
        let idleHeight = view.preferredHeight
        model.shortcutError = "Synthetic shortcut error"
        expect(view.subviews.compactMap { $0 as? NSTextField }.contains { !$0.isHidden && $0.stringValue == "Synthetic shortcut error" },
               "Removing the idle footer must not hide an actionable shortcut error")
        expect(view.preferredHeight > idleHeight, "An actionable status must have room to render")
        model.shortcutError = nil
        expect(view.preferredHeight == idleHeight,
               "Clearing an actionable status must restore the compact input-only height")
        model.reset()
        expect(model.results.isEmpty && model.selectedResult == nil, "Reset must keep the initial launcher blank")
        model.setQuery(" \t\n")
        expect(model.results.isEmpty && model.selectedResult == nil, "Whitespace-only input must not show initial suggestions")
        model.setResultLimit(3)
        expect(model.results.isEmpty, "Changing the result limit must not populate a blank query")
        model.setResultLimit(20)

        for query in ["", "terminal", "更新索引"] {
            model.setQuery(query)
            expectSettings(key(), context: "Command-comma with query \(String(reflecting: query))")
        }
        expectSettings(key(modifiers: [.command, .capsLock]), context: "Command-comma with Caps Lock")
        expectSettings(key("，"), context: "Physical comma with input-method punctuation")
        expectSettings(key(keyCode: 47), context: "Comma character on a different keyboard-layout key")

        let beforeRepeat = settingsActions
        expect(route(key(repeated: true)),
               "Repeated Command-comma must be consumed")
        expect(settingsActions == beforeRepeat, "Repeated Command-comma must not open Settings again")

        let unrelated: [(String, NSEvent)] = [
            ("bare comma", key(modifiers: [])),
            ("Command-Shift-comma", key("<", modifiers: [.command, .shift])),
            ("Command-Shift with a comma character", key(modifiers: [.command, .shift])),
            ("Command-Option-comma", key(modifiers: [.command, .option])),
            ("Command-Control-comma", key(modifiers: [.command, .control])),
            ("Command-A", key("a", keyCode: 0)),
            ("Command-C", key("c", keyCode: 8)),
            ("Command-V", key("v", keyCode: 9)),
            ("ordinary letter", key("t", modifiers: [], keyCode: 17)),
        ]
        for (name, event) in unrelated {
            let before = settingsActions
            expect(!route(event), "\(name) must remain available to normal routing")
            expect(settingsActions == before, "\(name) must not open Settings")
        }

        // A real field editor can compose marked text even in an offscreen window.
        window.makeFirstResponder(view.searchField)
        if let editor = view.searchField.currentEditor() as? NSTextView {
            editor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            expect(editor.hasMarkedText(), "IME fixture must contain marked text")
            expectSettings(key(), context: "Command-comma during marked text composition")
            expect(editor.hasMarkedText(), "Shortcut routing must not commit or clear marked text itself")
            editor.unmarkText()
        } else {
            failures.append("AppKit could not create the offscreen field editor for the IME regression")
        }

        expect(!application.isActive, "The regression must not activate its application")
        expect(!window.isVisible, "The regression must not show a window")
        expect(otherActions == 0, "Settings shortcuts must not submit or cancel search")

        // Selection and execution stay in process: callbacks record IDs and never launch apps.
        let numberCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (index, code) in numberCodes.enumerated() {
            expect(ResultShortcut.index(for: key(String(index + 1), keyCode: code)) == index,
                   "Command-\(index + 1) must map to its own zero-based result index")
            expect(ResultShortcut.index(for: key("注", keyCode: code)) == index,
                   "Number-row shortcuts must keep their index with non-Latin input-method characters")
        }
        let keypadCodes: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]
        for (index, code) in keypadCodes.enumerated() {
            expect(ResultShortcut.index(for: key("", keyCode: code)) == index,
                   "Numeric keypad shortcuts must map to their matching result index")
        }
        let numberKeyUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: .command,
                                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                          characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
        expect(ResultShortcut.index(for: numberKeyUp) == nil, "Releasing a numbered shortcut must not trigger another action")
        model.reset()
        _ = route(key("1", keyCode: 18))
        expect(submittedIDs.isEmpty, "Command-1 on a blank launcher must execute nothing")
        model.setQuery("Shortcut Fixture")
        expect(model.results.count == 9, "An oversized result limit must still cap visible choices at nine")
        let first = model.results.first?.id
        let ninth = model.results.dropFirst(8).first?.id
        expect(route(key("1", keyCode: 18)), "Command-1 must be handled by the native result view")
        expect(submittedIDs.count == 1 && submittedIDs.last == first,
               "Command-1 must immediately select and execute the first result exactly once")
        expect(route(key("9", keyCode: 25)), "Command-9 must be handled by the native result view")
        expect(submittedIDs.count == 2 && submittedIDs.last == ninth,
               "Command-9 must immediately select and execute the ninth result exactly once")
        for event in [key("1", keyCode: 18, repeated: true), key("9", keyCode: 25, repeated: true)] {
            expect(view.handleNumberShortcut(event), "Repeated numbered shortcuts must be consumed")
            expect(submittedIDs.count == 2, "Holding a numbered shortcut must not execute more results")
        }
        expect(route(key("1", modifiers: [.command, .capsLock], keyCode: 18)), "Caps Lock must not disable Command-1")
        expect(submittedIDs.count == 3 && submittedIDs.last == first, "Command-1 with Caps Lock must execute once")
        let nearMisses: [NSEvent.ModifierFlags] = [[], [.command, .shift], [.command, .option], [.command, .control]]
        for modifiers in nearMisses {
            expect(!view.handleNumberShortcut(key("1", modifiers: modifiers, keyCode: 18)),
                   "Number typing and additional modifier combinations must not execute a result")
        }
        expect(!view.handleNumberShortcut(key("0", keyCode: 29)), "Command-0 must not select a nonexistent tenth shortcut")
        expect(submittedIDs.count == 3, "Unrelated number combinations must leave execution untouched")
        for row in 0..<9 {
            expect(ResultShortcut.label(for: row) == "⌘\(row + 1)", "The first nine result labels must advertise their matching shortcuts")
        }
        expect(ResultShortcut.label(for: 9) == "10", "Later results must keep numbering without implying a Command-10 shortcut")
        view.layoutSubtreeIfNeeded()
        if let scroll = view.subviews.compactMap({ $0 as? NSScrollView }).first,
           let table = scroll.documentView as? NSTableView {
            expect(!scroll.hasVerticalScroller && !scroll.hasHorizontalScroller,
                   "The launcher must never create a scrollbar, even when more matches exist")
            expect(table.numberOfRows == 9 && view.tableView(table, viewFor: table.tableColumns.first, row: 9) == nil,
                   "Only the nine numbered matches may be rendered")
            for row in [0, 8] {
                let cell = view.tableView(table, viewFor: table.tableColumns.first, row: row)
                expect(cell?.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == ResultShortcut.label(for: row) } == true,
                       "Rendered launcher row \(row + 1) must show its number label")
            }
        } else {
            expect(false, "The offscreen launcher must expose its result table for label checks")
        }
        model.setQuery("Shortcut Fixture 10")
        expect(model.results.count == 1 && model.selectedResult == .application(applications[9]),
               "Narrowing the query must still find an application outside the first nine matches")
        model.setQuery("Shortcut Fixture")
        model.setResultLimit(3)
        let beforeMissing = model.selectedID
        _ = view.handleNumberShortcut(key("9", keyCode: 25))
        expect(submittedIDs.count == 3 && model.selectedID == beforeMissing,
               "An out-of-range numbered shortcut must not execute or change selection")
        window.makeFirstResponder(view.searchField)
        if let editor = view.searchField.currentEditor() as? NSTextView {
            editor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            expect(editor.hasMarkedText(), "Number-key IME fixture must have marked text")
            expect(!view.handleNumberShortcut(key("1", keyCode: 18)), "Number shortcuts must not execute during marked text composition")
            expect(submittedIDs.count == 3 && editor.hasMarkedText(), "Number shortcuts must preserve IME composition and execution state")
            editor.unmarkText()
        } else {
            expect(false, "AppKit must create a field editor for the number-key IME check")
        }
        model.reset()
        expect(model.query.isEmpty && model.results.isEmpty && model.selectedID == nil,
               "Returning from results must clear the launcher completely")
        expect(!application.isActive && !window.isVisible, "Numbered execution checks must remain offscreen and inactive")

        // Web-search callbacks record the untouched query. These checks never
        // create a URL, open a browser, or change Cue's network preference.
        expect(webActions.isEmpty, "Existing launcher shortcuts must not invoke web search")
        for query in ["", " \t\n", "\u{00A0}\u{2003}\u{3000}"] {
            model.setQuery(query)
            expect(route(key("\r", keyCode: 36)), "Command-Return with blank input must be consumed")
            expect(webActions.isEmpty, "Command-Return with blank input must not invoke a search")
        }
        model.setQuery("  Shortcut  Fixture  ")
        let webQuery = model.query
        let selectedBeforeWeb = model.selectedID
        let otherActionsBeforeWeb = otherActions
        let settingsBeforeWeb = settingsActions
        let webEvents: [(String, NSEvent)] = [
            ("Command-Return", key("\r", keyCode: 36)),
            ("Command-keypad Enter", key("\u{0003}", keyCode: 76)),
            ("Command-Return with Caps Lock", key("\r", modifiers: [.command, .capsLock], keyCode: 36)),
            ("Command-keypad Enter with Caps Lock", key("\u{0003}", modifiers: [.command, .capsLock], keyCode: 76)),
        ]
        for (name, event) in webEvents {
            let before = webActions.count
            expect(route(event), "\(name) must route through the real view's key-equivalent handler")
            expect(webActions.count == before + 1 && webActions.last == webQuery,
                   "\(name) must invoke web search exactly once with the original query")
            expect(model.query == webQuery && model.selectedID == selectedBeforeWeb,
                   "\(name) must preserve the query and selected local result")
        }
        let searchesBeforeRepeat = webActions.count
        for event in [key("\r", keyCode: 36, repeated: true), key("\u{0003}", keyCode: 76, repeated: true)] {
            expect(route(event), "A held web-search shortcut must be consumed")
            expect(webActions.count == searchesBeforeRepeat, "A held web-search shortcut must never submit again")
        }
        for modifiers in nearMisses {
            for code in [UInt16(36), UInt16(76)] {
                expect(!view.handleWebSearchShortcut(key("\r", modifiers: modifiers, keyCode: code)),
                       "Plain Return and additional modifier combinations must remain available to normal routing")
            }
        }
        expect(!view.handleWebSearchShortcut(key("\r", keyCode: 0)),
               "A Return character on an unrelated physical key must not trigger web search")
        let returnKeyUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: .command,
                                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                          characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        expect(!view.handleWebSearchShortcut(returnKeyUp), "Releasing Command-Return must not submit again")
        expect(webActions.count == searchesBeforeRepeat, "Near matches and released keys must not invoke web search")
        expect(otherActions == otherActionsBeforeWeb && settingsActions == settingsBeforeWeb,
               "Web-search shortcuts must never submit the selected local result, cancel, or open Settings")

        window.makeFirstResponder(view.searchField)
        if let editor = view.searchField.currentEditor() as? NSTextView {
            let selectedBeforeReturn = model.selectedResult?.id
            let submissionsBeforeReturn = submittedIDs.count
            expect(view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))),
                   "An ordinary Return must still route through the native field-editor submit command")
            expect(submittedIDs.count == submissionsBeforeReturn + 1 && submittedIDs.last == selectedBeforeReturn,
                   "An ordinary Return must execute the selected local result exactly once")
            expect(webActions.count == searchesBeforeRepeat, "An ordinary Return must not invoke the explicit web-search action")

            editor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            expect(editor.hasMarkedText(), "Web-search IME fixture must contain marked text")
            let markedString = editor.string
            let markedRange = editor.markedRange()
            let selectedRange = editor.selectedRange()
            let queryDuringComposition = model.query
            for code in [UInt16(36), UInt16(76)] {
                expect(!view.handleWebSearchShortcut(key("\r", keyCode: code)),
                       "Command-Return must not trigger web search while IME text is provisional")
                _ = route(key("\r", keyCode: code))
                expect(webActions.count == searchesBeforeRepeat && editor.hasMarkedText(),
                       "Real key-equivalent routing must preserve composition without submitting web search")
            }
            expect(editor.string == markedString && editor.markedRange() == markedRange
                   && editor.selectedRange() == selectedRange && model.query == queryDuringComposition,
                   "Web-search shortcut routing must not alter marked text, selection, or the query")
            expect(!view.control(view.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))),
                   "Return during composition must remain available to the input method")
            expect(submittedIDs.count == submissionsBeforeReturn + 1,
                   "Return during composition must not launch the selected local result")
            editor.unmarkText()
        } else {
            expect(false, "AppKit must create a field editor for web-search and ordinary Return checks")
        }
        model.reset()
        expect(!application.isActive && !window.isVisible, "Web-search checks must remain offscreen and inactive")

        // Browser choices are a local action list. Opening or navigating it must
        // neither submit text nor lose the local query when Escape closes it.
        let browsers = [
            WebSearchBrowser(bundleIdentifier: "test.browser.first", name: "First Browser"),
            WebSearchBrowser(bundleIdentifier: "test.browser.second", name: "Second Browser")
        ]
        model.setResultLimit(9)
        model.setWebSearchPreferences(enabled: true, browsers: browsers)
        for query in ["", " \t\n", "\u{00A0}\u{2003}\u{3000}"] {
            model.setQuery(query)
            expect(route(key("k", keyCode: 40)), "Command-K with blank input must be consumed")
            expect(searchActions == 0 && !model.isShowingSearchActions && model.results.isEmpty,
                   "Command-K must keep blank input completely empty")
        }
        model.setQuery("Shortcut Fixture")
        let localResults = model.results
        let beforeChoicesWebActions = webActions.count
        let beforeChoicesOtherActions = otherActions
        let beforeChoicesSettings = settingsActions
        expect(route(key("k", keyCode: 40)), "Command-K must open browser choices through real key-equivalent routing")
        expect(searchActions == 1 && model.isShowingSearchActions
               && model.results == [.googleSearch] + browsers.map { .googleSearchIn($0) },
               "Command-K must show only the default and explicitly added browsers even when apps match")
        expect(model.query == "Shortcut Fixture", "Opening browser choices must preserve the original query")
        expect(route(key("k", keyCode: 40, repeated: true)), "A held Command-K must be consumed")
        expect(searchActions == 1 && model.isShowingSearchActions, "A held Command-K must not toggle repeatedly")
        let beforeBrowserNumber = submittedIDs.count
        expect(route(key("2", keyCode: 19)), "Curated browser choices must retain numbered execution")
        expect(submittedIDs.count == beforeBrowserNumber + 1
               && submittedIDs.last == LauncherResult.googleSearchIn(browsers[0]).id,
               "Command-2 must execute exactly the first curated browser choice")
        expect(view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))),
               "Escape must route through the action list's cancel callback")
        expect(!model.isShowingSearchActions && model.results == localResults && model.query == "Shortcut Fixture"
               && otherActions == beforeChoicesOtherActions + 1,
               "Escape must restore local results without dismissing or changing the query")
        model.setResultLimit(1)
        model.setQuery("unmatched browser-choice fixture")
        expect(model.results == [.googleSearch], "Ordinary fallback must honor the user's reduced result limit")
        expect(route(key("k", keyCode: 40)) && model.results == [.googleSearch] + browsers.map { .googleSearchIn($0) },
               "Explicit Command-K must expose every curated browser even with the app result limit set to one")
        _ = model.closeSearchActions()
        model.setResultLimit(9)
        model.setQuery("Shortcut Fixture")
        for (label, event) in [
            ("Caps Lock", key("K", modifiers: [.command, .capsLock], keyCode: 40)),
            ("input-method characters", key("注", keyCode: 40))
        ] {
            let before = searchActions
            expect(route(event) && searchActions == before + 1 && model.isShowingSearchActions,
                   "Command-K with \(label) must open the choices once")
            expect(route(key("k", keyCode: 40)) && searchActions == before + 2 && !model.isShowingSearchActions,
                   "A second Command-K must return to local results")
        }
        let beforeNearChoiceKeys = searchActions
        for modifiers in nearMisses {
            expect(!view.handleSearchActionsShortcut(key("k", modifiers: modifiers, keyCode: 40)),
                   "Plain K and additional modifier combinations must remain available to normal routing")
        }
        expect(!view.handleSearchActionsShortcut(key("k", keyCode: 0)),
               "A K character on an unrelated physical key must not open browser choices")
        let choiceKeyUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: .command,
                                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                          characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        expect(!view.handleSearchActionsShortcut(choiceKeyUp) && searchActions == beforeNearChoiceKeys,
               "Near matches and released Command-K keys must not change browser choices")
        expect(webActions.count == beforeChoicesWebActions && settingsActions == beforeChoicesSettings,
               "Opening, closing, or numbering browser choices must not invoke the default-search or Settings callbacks")
        model.setWebSearchPreferences(enabled: false, browsers: browsers)
        expect(route(key("k", keyCode: 40)) && model.isShowingSearchActions,
               "Disabled search remains discoverable so its own settings are reachable")
        expect(model.results == [.googleSearch] + browsers.map { .googleSearchIn($0) }
               && !model.allowsWebSearch && webActions.count == beforeChoicesWebActions,
               "Discovering disabled browser choices must not execute a search")
        _ = model.closeSearchActions()
        model.setWebSearchPreferences(enabled: true, browsers: browsers)
        window.makeFirstResponder(view.searchField)
        if let editor = view.searchField.currentEditor() as? NSTextView {
            editor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            let before = searchActions
            let text = editor.string
            let range = editor.markedRange()
            let selection = editor.selectedRange()
            let query = model.query
            expect(editor.hasMarkedText() && !view.handleSearchActionsShortcut(key("k", keyCode: 40)),
                   "Command-K must not replace results during provisional IME composition")
            _ = route(key("k", keyCode: 40))
            expect(searchActions == before && !model.isShowingSearchActions && editor.hasMarkedText()
                   && editor.string == text && editor.markedRange() == range && editor.selectedRange() == selection
                   && model.query == query, "Real Command-K routing must preserve marked text, selection, and query")
            editor.unmarkText()
        } else {
            expect(false, "AppKit must create a field editor for browser-choice IME checks")
        }
        _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        expect(otherActions == beforeChoicesOtherActions + 2, "Escape outside browser choices must retain normal dismissal")
        model.reset()
        expect(model.results.isEmpty && !model.isShowingSearchActions, "Reset must clear browser choices as well as local results")
        expect(!application.isActive && !window.isVisible, "Browser-choice checks must remain offscreen and inactive")

        if !failures.isEmpty {
            for failure in failures { print("FAIL: \(failure)") }
            print("Launcher keyboard regression failed: \(failures.count) failures / \(checks) checks.")
            exit(1)
        }
        print("Launcher keyboard regression passed: \(checks) checks; blank opening, numbered execution, explicit web search, curated browser choices, Escape, Settings, modifiers, repeats, normal Return, editing, and marked text.")
    }
}
