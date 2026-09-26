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

        let model = LauncherModel()
        var settingsActions = 0
        var otherActions = 0
        let view = LauncherView(
            model: model,
            onSubmit: { otherActions += 1 },
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

        if !failures.isEmpty {
            for failure in failures { print("FAIL: \(failure)") }
            print("Launcher keyboard regression failed: \(failures.count) failures / \(checks) checks.")
            exit(1)
        }
        print("Launcher keyboard regression passed: \(checks) checks; immediate Settings, modifiers, repeats, normal editing, and marked text.")
    }
}
