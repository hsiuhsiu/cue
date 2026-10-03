import AppKit
import Carbon
import CueCore

/// Exercise preference persistence, live results and native keyboard handling with
/// synthetic apps. No real app is opened and no user preferences/history are read.
@main
struct CheckAppAliases {
    @MainActor private static var checks = 0

    @MainActor private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else {
            print("FAIL: \(message)")
            exit(1)
        }
        checks += 1
    }

    private static func key(_ code: UInt16 = UInt16(kVK_ANSI_E), _ value: String = "e",
                            modifiers: NSEvent.ModifierFlags = .command,
                            repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                        timestamp: 0, windowNumber: 0, context: nil,
                        characters: value, charactersIgnoringModifiers: value,
                        isARepeat: repeated, keyCode: code)!
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.mainMenu = nil
        let domain = "com.yyhsiu.cue.tests.app-aliases.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let code = IndexedApplication(name: "Code", url: URL(fileURLWithPath: "/Synthetic/Visual Studio Code.app"),
                                      bundleIdentifier: "com.microsoft.VSCode", searchNames: ["Visual Studio Code"])
        let terminal = IndexedApplication(name: "iTerm2", url: URL(fileURLWithPath: "/Synthetic/iTerm.app"),
                                          bundleIdentifier: "com.googlecode.iterm2")
        let movedCode = IndexedApplication(name: "Code", url: URL(fileURLWithPath: "/Synthetic/Moved/Visual Studio Code.app"),
                                           bundleIdentifier: "COM.MICROSOFT.VSCODE", searchNames: ["Visual Studio Code"])
        let anonymous = IndexedApplication(name: "Utility", url: URL(fileURLWithPath: "/Synthetic/Other/../Utility.app"))
        check(code.aliasPreferenceID == movedCode.aliasPreferenceID,
              "A bundle-identified app retains its alias identity after moving or identifier case changes")
        check(anonymous.aliasPreferenceID == "path:/Synthetic/Utility.app",
              "An app without a bundle identifier uses its standardized local path")
        for query in ["code", "v", "visual", "vs", "vsc", "studio", "Visual Studio Code"] {
            let results = SearchEngine.search([code], query: query)
            check(results.map(\.id) == [code.id], "Display, full file name and initials find exactly one app for \(query)")
        }
        let decorated = code.withSearchAlias("  my editor  ")
        check(decorated.id == code.id && decorated.aliasPreferenceID == code.aliasPreferenceID
              && decorated.url == code.url && decorated.name == "Code",
              "An alias preserves launch target, visible name and existing history identity")
        check(SearchEngine.search([decorated], query: "my editor").first?.id == code.id,
              "The prepared alias is searchable")
        check(SearchEngine.search([decorated.withSearchAlias(nil)], query: "my editor").isEmpty,
              "Removing an alias removes only that extra search name")
        check(SearchEngine.search([decorated.withSearchAlias(nil)], query: "vs").first?.id == code.id,
              "Removing an alias preserves automatically collected names")

        let preferences = AppAliasPreferences(defaults: defaults)
        check(preferences.aliases.isEmpty, "A new isolated preference suite has no custom app aliases")
        var changes = 0
        preferences.onChange = { _ in changes += 1 }
        check(preferences.setAlias("ＶＳ", for: code, conversionAliases: .defaults) == nil,
              "Saving a valid alias succeeds")
        check(SearchEngine.normalize(preferences.alias(for: code)) == "vs",
              "Persisted aliases normalize case and width")
        check(changes == 1, "A successful alias save emits one preference change")
        let saved = preferences.aliases
        let reloaded = AppAliasPreferences(defaults: defaults)
        check(reloaded.aliases == saved && reloaded.alias(for: movedCode) == preferences.alias(for: code),
              "An alias survives restart and follows the app bundle after a move")
        check(preferences.setAlias(preferences.alias(for: code), for: code, conversionAliases: .defaults) == nil
              && changes == 1, "Saving an unchanged alias causes no unnecessary model update")
        check(preferences.setAlias("vs", for: terminal, conversionAliases: .defaults) != nil,
              "Two different apps cannot own normalized-equivalent aliases")
        check(preferences.aliases == saved && changes == 1,
              "A rejected duplicate changes neither disk-backed preferences nor live search")
        for reserved in ["st", " TS ", "ＳＴ"] {
            check(preferences.setAlias(reserved, for: terminal, conversionAliases: .defaults) != nil,
                  "App aliases cannot collide with a conversion command: \(reserved)")
        }
        let conflictingConversion = try ChineseConversionAliases(traditional: "vs", simplified: "ts")
        check(preferences.conflict(with: conflictingConversion) != nil,
              "Changing a conversion alias checks existing app aliases in the reverse direction")
        let conversionPreferences = ChineseConversionPreferences(defaults: defaults)
        conversionPreferences.validateAliases = { preferences.conflict(with: $0) }
        do {
            try conversionPreferences.save(traditional: "ＶＳ", simplified: "ts")
            check(false, "The conversion preference save must reject an existing app alias")
        } catch {
            check(conversionPreferences.aliases == .defaults
                  && ChineseConversionPreferences(defaults: defaults).aliases == .defaults,
                  "A conversion/app collision changes neither active nor persisted conversion aliases")
        }
        let availableConversion = try ChineseConversionAliases(traditional: "zt", simplified: "zs")
        check(preferences.conflict(with: availableConversion) == nil,
              "Unrelated conversion aliases remain valid")
        for invalid in ["new\nline", "new\tline", "escape\u{1B}", " leading", "two words", "2+2", "1m", "hello/there", String(repeating: "a", count: 33)] {
            check(preferences.setAlias(invalid, for: terminal, conversionAliases: .defaults) != nil,
                  "Invalid aliases are rejected without partial persistence")
        }
        check(preferences.aliases == saved && AppAliasPreferences(defaults: defaults).aliases == saved,
              "Every rejected edit leaves the saved map unchanged")
        check(preferences.setAlias("", for: code, conversionAliases: .defaults) == nil
              && preferences.alias(for: code).isEmpty,
              "An empty alias removes the override")
        check(AppAliasPreferences(defaults: defaults).aliases.isEmpty,
              "Alias removal persists across restart")
        let disabledTraditional = try ChineseConversionAliases(traditional: "", simplified: "ts")
        check(preferences.setAlias("st", for: code, conversionAliases: disabledTraditional) == nil,
              "A disabled conversion alias becomes available to an app")
        check(preferences.conflict(with: .defaults) != nil,
              "Restoring conversion defaults reports an app alias collision")
        _ = preferences.setAlias("", for: code, conversionAliases: .defaults)

        let malformed: [String: Any] = [
            "bundle:valid.app": "Alpha", "bundle:second.app": "ＢＥＴＡ",
            "bundle:duplicate.app": "alpha", "bundle:number.app": 42,
            "broken": "bad", "bundle:UPPERCASE": "upper", "path:/": "root",
            "bundle:bad-alias.app": "not valid", "bundle:empty.app": ""
        ]
        defaults.set(malformed, forKey: AppAliasPreferences.storageKey)
        let sanitized = AppAliasPreferences(defaults: defaults)
        check(sanitized.aliases.count == 2
              && Set(sanitized.aliases.values.map(SearchEngine.normalize)) == ["alpha", "beta"],
              "Malformed stored entries and normalized duplicates cannot leak into search")
        let oversized = Dictionary(uniqueKeysWithValues: (0...AppAliasPreferences.maximumAliases).map {
            ("bundle:app\($0)", "app\($0)")
        })
        defaults.set(oversized, forKey: AppAliasPreferences.storageKey)
        check(AppAliasPreferences(defaults: defaults).aliases.isEmpty,
              "An oversized stored map is ignored before costly startup processing")
        let full = Dictionary(uniqueKeysWithValues: (0..<AppAliasPreferences.maximumAliases).map {
            ("bundle:app\($0)", "app\($0)")
        })
        defaults.set(full, forKey: AppAliasPreferences.storageKey)
        let bounded = AppAliasPreferences(defaults: defaults)
        check(bounded.aliases.count == AppAliasPreferences.maximumAliases,
              "The supported preference capacity survives loading")
        check(bounded.setAlias("newapp", for: code, conversionAliases: .defaults) != nil
              && bounded.aliases.count == AppAliasPreferences.maximumAliases,
              "A full alias map refuses one more app without dropping saved choices")
        let existing = IndexedApplication(name: "Existing", url: URL(fileURLWithPath: "/Synthetic/Existing.app"),
                                          bundleIdentifier: "app0")
        check(bounded.setAlias("renamed", for: existing, conversionAliases: .defaults) == nil,
              "Existing aliases remain editable at the capacity limit")
        check(bounded.setAlias("", for: existing, conversionAliases: .defaults) == nil
              && bounded.setAlias("newapp", for: code, conversionAliases: .defaults) == nil,
              "Removing one saved alias frees capacity for a new explicit app choice")
        defaults.removeObject(forKey: AppAliasPreferences.storageKey)

        // Model updates must invalidate both previously matched and unmatched
        // queries without clearing the user's input or selection unnecessarily.
        let model = LauncherModel(applications: [code, terminal])
        model.setQuery("quickterm")
        check(model.results == [.googleSearch, .askGPT, .translateGPT], "The unknown alias begins as a cached web fallback")
        model.setApplicationAliases([terminal.aliasPreferenceID: "quickterm"])
        check(model.query == "quickterm" && model.results.first?.id == LauncherResult.application(terminal).id,
              "Saving an alias replaces the currently visible cached fallback immediately")
        model.setQuery("iTerm")
        model.select(LauncherResult.application(terminal).id)
        model.setApplicationAliases([terminal.aliasPreferenceID: "newterm"])
        check(model.selectedID == LauncherResult.application(terminal).id && model.query == "iTerm",
              "An alias edit preserves a selected app that still matches the current query")
        model.setQuery("quickterm")
        check(model.results == [.googleSearch, .askGPT, .translateGPT], "An old cached alias match disappears immediately after renaming")
        model.setQuery("newterm")
        check(model.selectedResult?.id == LauncherResult.application(terminal).id, "The replacement alias selects the same launch target")
        model.setApplicationAliases([:])
        check(model.results == [.googleSearch, .askGPT, .translateGPT] && model.query == "newterm",
              "Deleting an active alias refreshes the result without deleting the user's query")
        model.setQuery("vs")
        check(model.results.contains { $0.id == LauncherResult.application(code).id },
              "Clearing the preferences map does not remove automatic full names")
        let restarted = LauncherModel(applications: [movedCode, terminal],
                                      applicationAliases: [code.aliasPreferenceID: "quickcode"])
        restarted.setQuery("quickcode")
        check(restarted.selectedResult?.id == LauncherResult.application(movedCode).id,
              "Model startup reapplies persisted aliases to a moved app's current launch path")

        var learned = SearchUsage()
        for _ in 0..<20 { learned.record(resultID: LauncherResult.sleep.id, query: "sleep") }
        let ranked = LauncherModel(applications: [code, terminal], usage: learned.snapshot(),
                                   applicationAliases: [terminal.aliasPreferenceID: "sleep"])
        ranked.setQuery("sleep")
        check(ranked.results.first?.id == LauncherResult.application(terminal).id
              && ranked.results.contains(.sleep),
              "An exact explicit app alias beats a popular ordinary command without removing that command")
        ranked.setQuery("sl")
        check(ranked.results.contains { $0.id == LauncherResult.application(terminal).id },
              "A partially typed app alias remains discoverable")
        ranked.setConversionAliases(try ChineseConversionAliases(traditional: "convertme", simplified: "simplifyme"))
        ranked.setQuery("convertme")
        check(ranked.results.first == .convertToTraditional, "An unrelated explicit conversion alias keeps first priority")
        ranked.reset()
        check(ranked.query.isEmpty && ranked.results.isEmpty, "Aliases do not create suggestions in the empty launcher")

        // Real AppKit view/event path: editing is explicit and does not launch.
        var edits: [IndexedApplication] = []
        var submissions = 0
        let native = LauncherModel(applications: [code, terminal])
        let view = LauncherView(model: native, onSubmit: { submissions += 1 }, onCancel: {}, onSettings: {},
                                onAppAlias: { edits.append($0) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        native.setQuery("vs")
        check(view.handleAppAliasShortcut(key()) && edits.map(\.id) == [code.id],
              "Command-E edits the selected app via the native launcher's callback")
        _ = view.handleAppAliasShortcut(key(repeated: true))
        check(edits.count == 1 && submissions == 0, "A held alias shortcut neither reopens the editor nor launches an app")
        for modifiers: NSEvent.ModifierFlags in [[], .option, [.command, .shift], [.command, .control]] {
            check(!view.handleAppAliasShortcut(key(modifiers: modifiers)),
                  "Other modifier combinations retain their normal text editing behavior")
        }
        check(view.performKeyEquivalent(with: key()) && edits.count == 2,
              "The window's key-equivalent route also invokes app alias editing")
        native.setQuery("sleep")
        check(!view.handleAppAliasShortcut(key()) && edits.count == 2,
              "Command-E cannot edit an ordinary command as an app")
        native.setQuery("zzzzunmatched")
        check(!view.handleAppAliasShortcut(key()), "A Google fallback is not treated as an app alias target")
        native.reset()
        check(!view.handleAppAliasShortcut(key()), "An empty launcher has no alias target")
        native.setQuery("vs")
        window.makeFirstResponder(view.searchField)
        guard let editor = view.searchField.currentEditor() as? NSTextView else { fatalError("Missing app alias field editor") }
        editor.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.string
        let range = editor.markedRange()
        check(!view.handleAppAliasShortcut(key()) && edits.count == 2,
              "Command-E remains with the input method while text is marked")
        check(editor.string == marked && editor.markedRange() == range,
              "Alias keyboard handling preserves in-progress IME composition")
        editor.unmarkText()
        window.makeFirstResponder(nil)
        native.setQuery("code")
        view.frame.size = NSSize(width: 640, height: 300)
        view.layoutSubtreeIfNeeded()
        guard let table = descendants(view).compactMap({ $0 as? NSTableView }).first,
              let appRow = native.results.firstIndex(where: { $0.id == LauncherResult.application(code).id }) else {
            fatalError("Missing native app row for alias actions")
        }
        let contextLocation = table.convert(NSPoint(x: 20, y: table.rect(ofRow: appRow).midY), to: nil)
        let contextEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: contextLocation, modifierFlags: [],
                                             timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1)!
        guard let menu = table.menu(for: contextEvent), let item = menu.items.first, let action = item.action else {
            fatalError("Missing app alias context menu")
        }
        check(menu.items.count == 1 && item.keyEquivalent == "e" && item.keyEquivalentModifierMask == .command,
              "The app context menu exposes the same explicit Command-E alias action")
        check(NSApp.sendAction(action, to: item.target, from: item) && edits.count == 3 && edits.last?.id == code.id,
              "The app context menu invokes the same selected-app editor callback")
        native.setQuery("iTerm")
        _ = NSApp.sendAction(action, to: item.target, from: item)
        check(edits.count == 3 && native.selectedResult?.id == LauncherResult.application(terminal).id,
              "A stale context menu cannot edit a different app that has replaced its old row")
        native.setQuery("code")
        view.layoutSubtreeIfNeeded()
        guard let cell = table.view(atColumn: 0, row: appRow, makeIfNecessary: true),
              let button = descendants(cell).compactMap({ $0 as? NSButton }).first,
              let buttonAction = button.action else { fatalError("Missing inline alias action") }
        check(!button.isHidden && button.toolTip?.contains("⌘E") == true,
              "The selected app exposes its alias action and keyboard hint")
        check(NSApp.sendAction(buttonAction, to: button.target, from: button)
              && edits.count == 4 && edits.last?.id == code.id,
              "The inline action edits the corresponding app without submitting a result")
        native.setQuery("sleep")
        view.layoutSubtreeIfNeeded()
        let commandLocation = table.convert(NSPoint(x: 20, y: table.rect(ofRow: 0).midY), to: nil)
        let commandEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: commandLocation, modifierFlags: [],
                                             timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1)!
        check(table.menu(for: commandEvent) == nil, "Commands do not expose an app-only alias context menu")
        check(submissions == 0, "Alias navigation and editing never launch an app")
        print("App alias checks passed (\(checks) checks).")
    }
}
