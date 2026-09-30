import AppKit
import CueCore

/// Real launcher/controller with synthetic apps, isolated storage and injected actions.
/// Never opens another app, changes login items, or reads the system clipboard.
@main
struct CheckAdaptiveSearch {
    @MainActor private static var checks = 0

    @MainActor private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() {
            print("FAIL: \(message)")
            exit(1)
        }
        checks += 1
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.mainMenu = nil
        let apps = ["Codium", "Codium Pro", "Codium Beta"].map {
            IndexedApplication(name: $0, url: URL(fileURLWithPath: "/Synthetic/\($0).app"))
        }
        let now = Date()
        var learned = SearchUsage()
        learned.record(resultID: LauncherResult.application(apps[2]).id, query: "codi", at: now)
        let model = LauncherModel(applications: apps)
        model.setQuery("codi")
        let original = model.results
        model.select(LauncherResult.application(apps[1]).id)
        let selected = model.selectedID
        var publications = 0
        model.onChange = { publications += 1 }
        model.updateUsage(learned.snapshot(at: now))
        check(model.results == original && model.selectedID == selected,
              "Background learning must not reorder visible rows or numbered shortcuts")
        check(publications == 0, "A background snapshot must not trigger a redraw")
        model.setQuery("codi")
        check(model.results == original, "Duplicate text events keep visible ordering stable")
        model.setQuery("codiu")
        check(model.results.first == .application(apps[2]), "The next real edit adopts general usage")
        model.setQuery("codi")
        check(model.results.first == .application(apps[2]), "Cached queries are invalidated with new usage")
        model.setQuery("codium")
        check(model.results.first == .application(apps[0]), "Exact matches remain above learned prefixes")
        model.reset()
        check(model.results.isEmpty && model.query.isEmpty, "Personalization never creates initial suggestions")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cue-adaptive-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let domain = "com.yyhsiu.cue.tests.adaptive.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let conversionPreferences = ChineseConversionPreferences(defaults: defaults)
        check(conversionPreferences.aliases == .defaults, "New preferences use st/ts conversion aliases")
        let aliasModel = LauncherModel()
        aliasModel.setQuery("xy")
        check(aliasModel.results == [.googleSearch], "Unknown alias starts with cached Google fallback")
        var aliasChanges = 0
        conversionPreferences.onChange = { aliases in
            aliasChanges += 1
            aliasModel.setConversionAliases(aliases)
        }
        try conversionPreferences.save(traditional: "xy", simplified: "")
        check(aliasChanges == 1 && aliasModel.results.first == .convertToTraditional,
              "Saving aliases invalidates the current query's cached empty results immediately")
        let savedAliases = ChineseConversionPreferences(defaults: defaults).aliases
        check(savedAliases.traditional == "xy" && savedAliases.simplified.isEmpty,
              "Custom and disabled aliases survive a preferences restart")
        try conversionPreferences.save(traditional: " xy ", simplified: " ")
        check(aliasChanges == 1, "Saving unchanged normalized display values sends no redundant update")
        do {
            try conversionPreferences.save(traditional: "XY", simplified: "ｘｙ")
            check(false, "Duplicate aliases must be rejected")
        } catch {
            check(ChineseConversionPreferences(defaults: defaults).aliases == savedAliases && aliasChanges == 1,
                  "Rejected aliases must not alter persisted preferences or the live search model")
        }
        try conversionPreferences.save(traditional: "z", simplified: "ts")
        check(aliasModel.results == [.googleSearch], "Changing an alias also removes its old cached result")
        aliasModel.setQuery("z")
        check(aliasModel.selectedResult == .convertToTraditional, "An explicitly saved one-character alias remains usable")
        defaults.set(["traditional": "ST", "simplified": "ｓｔ"], forKey: "chineseConversion.aliases")
        check(ChineseConversionPreferences(defaults: defaults).aliases == .defaults,
              "Invalid saved aliases fall back to usable defaults")
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        let clipboard = ClipboardModel(defaults: defaults, fileURL: folder.appendingPathComponent("clipboard.json"),
                                       pasteboardName: board.name)
        let file = folder.appendingPathComponent("Search/usage.json")
        let store = SearchUsageStore(fileURL: file)
        let live = LauncherModel(applications: apps, usageStore: store)
        var completions: [@MainActor (Error?) -> Void] = []
        var launched: [IndexedApplication] = []
        let controller = LauncherPanelController(clipboard: clipboard, model: live, openApplication: { app, completion in
            launched.append(app)
            completions.append(completion)
        })
        guard let window = NSApplication.shared.windows.last(where: { $0.contentView is LauncherView }),
              let view = window.contentView as? LauncherView else { fatalError("Missing launcher fixture") }
        defer { window.contentView = nil; window.close() }
        live.startUsageTracking()
        live.setQuery("codi")
        live.select(LauncherResult.application(apps[2]).id)
        controller.dismiss()
        check(launched.isEmpty, "Navigation and cancellation must never count as use")

        // Failure after dismissal: ignore the obsolete error and never learn the failed app.
        live.setQuery("codi")
        live.select(LauncherResult.application(apps[2]).id)
        _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check(launched == [apps[2]], "Enter routes to the selected app")
        check(live.query.isEmpty && !window.isVisible, "Launching dismisses before completion or disk work")
        controller.dismiss()
        completions.removeFirst()(NSError(domain: domain, code: 1))
        check(!window.isVisible, "A stale failed launch must not reopen the window")

        // Numbered execution succeeds while another query is already visible.
        live.setQuery("codi")
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19)!
        check(view.handleNumberShortcut(event), "Command-2 is consumed by the real launcher")
        check(launched.last == apps[1], "Command-2 launches the displayed second row")
        live.setQuery("codi")
        let displayed = live.results
        live.select(LauncherResult.application(apps[0]).id)
        let displayedSelection = live.selectedID
        completions.removeFirst()(nil)
        await live.prepareForTermination()
        check(live.results == displayed && live.selectedID == displayedSelection,
              "Delayed successful launch must not move the current result list")
        let saved = await SearchUsageStore(fileURL: file).load()
        let ranked = SearchEngine.search(apps, query: "codi", usage: saved)
        check(ranked == [apps[1], apps[0], apps[2]], "Only successful selection is persisted; failures and navigation are excluded")
        live.reset()
        live.setQuery("codi")
        check(live.results.first == .application(apps[1]), "Reopening immediately uses the staged learned ranking")
        let restarted = LauncherModel(applications: apps, usageStore: SearchUsageStore(fileURL: file))
        restarted.setQuery("codi")
        let beforeLoad = restarted.results
        restarted.startUsageTracking()
        await restarted.prepareForTermination()
        check(restarted.results == beforeLoad, "Startup disk load must not reorder ongoing typing")
        restarted.reset()
        restarted.setQuery("codi")
        check(restarted.results.first == .application(apps[1]), "A fresh model restores personalization on next invocation")

        // Startup event ordering: an action accepted before explicit startup load is retained.
        let earlyFile = folder.appendingPathComponent("Early/usage.json")
        let early = LauncherModel(applications: apps, usageStore: SearchUsageStore(fileURL: earlyFile))
        early.recordSuccessfulAction(resultID: LauncherResult.application(apps[2]).id, query: "codi")
        early.startUsageTracking()
        early.recordSuccessfulAction(resultID: LauncherResult.application(apps[2]).id, query: "codi")
        await early.prepareForTermination()
        let earlySaved = await SearchUsageStore(fileURL: earlyFile).load()
        check(SearchEngine.search(apps, query: "codi", usage: earlySaved).first == apps[2],
              "First-use actions survive startup loading and immediate quit")

        // A command's incidental substring must not permanently block a learned
        // app choice: "it" also occurs inside the traditional-conversion alias.
        let terminal = IndexedApplication(name: "iTerm2", url: URL(fileURLWithPath: "/Synthetic/iTerm2.app"))
        let terminalResult = LauncherResult.application(terminal)
        let collisionFile = folder.appendingPathComponent("Collision/usage.json")
        let collisionStore = SearchUsageStore(fileURL: collisionFile)
        let collision = LauncherModel(applications: [terminal], usageStore: collisionStore)
        var collisionCompletions: [@MainActor (Error?) -> Void] = []
        var collisionLaunches: [IndexedApplication] = []
        let beforeCollisionWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let collisionController = LauncherPanelController(
            clipboard: clipboard, model: collision, openApplication: { app, completion in
                collisionLaunches.append(app)
                collisionCompletions.append(completion)
            }
        )
        guard let collisionWindow = NSApplication.shared.windows.first(where: {
            !beforeCollisionWindows.contains(ObjectIdentifier($0)) && $0.contentView is LauncherView
        }), let collisionView = collisionWindow.contentView as? LauncherView else {
            fatalError("Missing app/command collision fixture")
        }
        defer { collisionWindow.contentView = nil; collisionWindow.close() }
        collision.startUsageTracking()
        collision.setQuery("it")
        check(collision.results == [.convertToTraditional, terminalResult],
              "Unlearned it collision retains command-first ordering")
        collision.select(terminalResult.id)
        collisionController.dismiss()
        let afterNavigation = await collisionStore.load()
        check(collisionLaunches.isEmpty && afterNavigation == .empty,
              "Selecting and dismissing iTerm2 does not learn the it collision")

        let commandTwo = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: collisionWindow.windowNumber, context: nil,
            characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19)!
        collision.setQuery("it")
        check(collisionView.handleNumberShortcut(commandTwo), "Command-2 routes through the collision launcher")
        check(collisionLaunches == [terminal] && collision.query.isEmpty,
              "Command-2 launches the displayed iTerm2 and dismisses immediately")
        collisionController.dismiss()
        collisionCompletions.removeFirst()(NSError(domain: domain, code: 3))
        let afterFailure = await collisionStore.load()
        check(afterFailure == .empty && !collisionWindow.isVisible,
              "A failed iTerm2 launch neither learns the collision nor reopens a stale invocation")
        collision.setQuery("it")
        check(collision.results == [.convertToTraditional, terminalResult],
              "Failed launch leaves the it ordering unchanged")
        check(collisionView.handleNumberShortcut(commandTwo), "Command-2 executes a subsequent successful selection")
        check(collisionLaunches == [terminal, terminal], "Both collision launches use the same explicit second row")
        collision.setQuery("it")
        let visibleCollision = collision.results
        collision.select(LauncherResult.convertToTraditional.id)
        collisionCompletions.removeFirst()(nil)
        await collision.prepareForTermination()
        check(collision.results == visibleCollision && collision.selectedID == LauncherResult.convertToTraditional.id,
              "Completed collision learning does not move visible rows or their current selection")
        collision.reset()
        collision.setQuery("it")
        check(collision.results == [terminalResult, .convertToTraditional],
              "The next invocation promotes learned iTerm2 above the incidental conversion command")
        let collisionJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: collisionFile)) as! [String: Any]
        let collisionUsage = collisionJSON["usage"] as! [String: Any]
        let collisionResults = collisionUsage["results"] as! [[String: Any]]
        let collisionEntry = collisionResults.first?["usage"] as? [String: Any]
        check(collisionResults.count == 1 && collisionResults.first?["id"] as? String == terminalResult.id
              && collisionEntry?["score"] as? Double == 1,
              "Persistence contains exactly one successful iTerm2 selection, excluding navigation and failure")
        let restoredCollision = LauncherModel(applications: [terminal], usageStore: SearchUsageStore(fileURL: collisionFile))
        restoredCollision.startUsageTracking()
        await restoredCollision.prepareForTermination()
        restoredCollision.reset()
        restoredCollision.setQuery("it")
        check(restoredCollision.results == [terminalResult, .convertToTraditional],
              "The learned app/command collision ordering survives a model and store restart")
        collisionController.dismiss()

        // Commands use the same learning path, with system effects injected away.
        let commandFile = folder.appendingPathComponent("Commands/usage.json")
        let commandStore = SearchUsageStore(fileURL: commandFile)
        let commands = LauncherModel(usageStore: commandStore)
        var systemCalls: [SystemAction] = []
        let previousWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let commandController = LauncherPanelController(
            clipboard: clipboard, model: commands,
            performSystemAction: { action in
                systemCalls.append(action)
                if action == .lockScreen { throw NSError(domain: domain, code: 2) }
            },
            openApplication: { _, _ in fatalError("Command fixture must not launch an app") }
        )
        guard let commandWindow = NSApplication.shared.windows.first(where: {
            !previousWindows.contains(ObjectIdentifier($0)) && $0.contentView is LauncherView
        }), let commandView = commandWindow.contentView as? LauncherView else {
            fatalError("Missing command fixture")
        }
        defer { commandWindow.contentView = nil; commandWindow.close() }
        commands.startUsageTracking()
        commands.setQuery("sleep")
        check(commands.selectedResult == .sleep, "Sleep command is selected by its exact query")
        _ = commandView.control(commandView.searchField, textView: NSTextView(),
                                doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check(!commandWindow.isVisible && commands.query.isEmpty,
              "System command dismisses immediately without waiting for its action")
        var successfulCommandObserved = false
        for _ in 0..<200 {
            if await commandStore.load() != .empty {
                successfulCommandObserved = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(successfulCommandObserved && systemCalls == [.sleep],
              "A successful injected system action is learned")

        commands.setQuery("lock")
        check(commands.selectedResult == .lockScreen, "Lock command is selected by its exact query")
        _ = commandView.control(commandView.searchField, textView: NSTextView(),
                                doCommandBy: #selector(NSResponder.insertNewline(_:)))
        // Invalidate the invocation before the injected error returns; no UI opens.
        commandController.dismiss()
        for _ in 0..<200 {
            if systemCalls.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(systemCalls == [.sleep, .lockScreen], "Both system actions ran only through injected handlers")
        check(!commandWindow.isVisible, "A stale failed system action does not reopen the launcher")

        commands.setQuery("clipboard")
        check(commands.selectedResult == .clipboardHistory, "Clipboard command remains searchable")
        _ = commandView.control(commandView.searchField, textView: NSTextView(),
                                doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check(commandWindow.contentView is ClipboardView, "Clipboard command opens its own page")
        check(!clipboard.recordingEnabled, "Opening Clipboard History does not enable clipboard recording")
        await commands.prepareForTermination()
        let commandData = try Data(contentsOf: commandFile)
        let commandJSON = try JSONSerialization.jsonObject(with: commandData) as! [String: Any]
        let persistedUsage = commandJSON["usage"] as! [String: Any]
        let persistedResults = persistedUsage["results"] as! [[String: Any]]
        let persistedQueries = persistedUsage["queries"] as! [[String: Any]]
        check(Set(persistedResults.compactMap { $0["id"] as? String }) == [
            LauncherResult.sleep.id, LauncherResult.clipboardHistory.id,
        ], "Only successful system and Clipboard History commands are persisted")
        check(Set(persistedQueries.compactMap { $0["query"] as? String }) == ["sleep", "clipboard"],
              "Command learning contains launcher queries only; failed Lock is excluded")
        commandController.dismiss()
        await clipboard.prepareForTermination()
        check(!NSApplication.shared.isActive && !window.isVisible && !commandWindow.isVisible && !collisionWindow.isVisible,
              "Harness must not activate or show an app")
        print("Adaptive search integration passed: \(checks) checks; no real apps launched or user history read.")
    }
}
