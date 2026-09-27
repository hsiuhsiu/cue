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
        var submittedIDs: [String] = []
        let view = LauncherView(
            model: model,
            onSubmit: {
                otherActions += 1
                if let id = model.selectedResult?.id { submittedIDs.append(id) }
            },
            onCancel: { otherActions += 1 },
            onSettings: { settingsActions += 1 }
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

        if !failures.isEmpty {
            for failure in failures { print("FAIL: \(failure)") }
            print("Launcher keyboard regression failed: \(failures.count) failures / \(checks) checks.")
            exit(1)
        }
        print("Launcher keyboard regression passed: \(checks) checks; blank opening, immediate numbered execution, Settings, modifiers, repeats, normal editing, and marked text.")
    }
}
