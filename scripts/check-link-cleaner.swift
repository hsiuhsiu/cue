import AppKit
import CueCore

/// Intentionally ignores cancellation while suspended so stale-controller guards
/// are tested independently of a cooperative pasteboard service.
private actor SuspendedLinkCleaner: LinkCleaning {
    private var preparation = LinkCleaningPreparation(
        result: LinkCleaner.Result(url: "https://example.test/article?keep=yes", removedParameterCount: 1),
        changeCount: 0
    )
    private var suspensionEnabled = false
    private var prepareError: LinkCleaningError?
    private var commitError: LinkCleaningError?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var preparations = 0
    private(set) var commits = 0

    func configure(result: LinkCleaner.Result? = nil, suspended: Bool = false,
                   prepareError: LinkCleaningError? = nil, commitError: LinkCleaningError? = nil) {
        if let result { preparation = LinkCleaningPreparation(result: result, changeCount: 0) }
        suspensionEnabled = suspended
        self.prepareError = prepareError
        self.commitError = commitError
    }

    func prepare() async throws -> LinkCleaningPreparation {
        preparations += 1
        let result = preparation
        let error = prepareError
        if suspensionEnabled { await withCheckedContinuation { waiting.append($0) } }
        if let error { throw error }
        return result
    }

    func commit(_ preparation: LinkCleaningPreparation) async throws {
        commits += 1
        if let commitError { throw commitError }
    }

    func resume() {
        let pending = waiting
        waiting.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@main
struct CheckLinkCleaner {
    @MainActor static var checks = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor static func eventually(_ message: String, _ predicate: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await predicate() { check(true, message); return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(false, message)
    }

    @MainActor static func expectError(_ expected: LinkCleaningError, _ message: String,
                                      operation: () async throws -> Void) async {
        do { try await operation(); check(false, message) }
        catch let error as LinkCleaningError {
            // Error enum cases have no payload; avoid requiring an Equatable API
            // solely for the harness.
            check(String(describing: error) == String(describing: expected), message)
        } catch { check(false, "\(message): unexpected error \(error)") }
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.mainMenu = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cue-link-cleaner-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let domain = "com.yyhsiu.cue.tests.link-cleaner.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        try await checkPasteboard(board)
        try await checkController(application, board: board, defaults: defaults, folder: folder)
        check(!application.isActive && application.windows.allSatisfy { !$0.isVisible },
              "The harness stays hidden and never activates a window")
        print("Link cleaner passed: \(checks) checks; private pasteboard transactions, marker preservation, cancellation, controller routing, and no query history. No general clipboard, browser, or network access.")
    }

    @MainActor private static func checkPasteboard(_ board: NSPasteboard) async throws {
        let service = LinkCleaningService(pasteboardName: board.name)
        let original = "  https://example.test/A%2fb?keep=One+Two&utm_source=mail&tag=x%2Fy&empty=#A%2bB  "
        let expected = "https://example.test/A%2fb?keep=One+Two&tag=x%2Fy&empty=#A%2bB"
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let marker = Data([0x10, 0x00, 0x71])
        let item = NSPasteboardItem()
        item.setString(original, forType: .string)
        item.setString("<a href='fixture'>stale rich content</a>", forType: .html)
        item.setData(marker, forType: concealed)
        item.setData(Data(), forType: transient)
        board.clearContents()
        check(board.writeObjects([item]), "The private source clipboard fixture must be written")
        let originalCount = board.changeCount
        let preparation = try await service.prepare()
        check(preparation.result.url == expected && preparation.result.removedParameterCount == 1,
              "The pasteboard reader preserves functional parameters and raw encoding through core cleanup")
        check(board.changeCount == originalCount && board.string(forType: .string) == original
              && board.string(forType: .html)?.contains("stale rich content") == true,
              "Preparation must not mutate the source clipboard or strip formats before commit")
        try await service.commit(preparation)
        check(board.string(forType: .string) == expected && board.string(forType: .URL) == expected,
              "A successful commit writes the same cleaned text and URL representation")
        check(board.data(forType: concealed) == marker && board.data(forType: transient) == Data(),
              "Privacy and transient markers survive cleanup exactly")
        check(board.data(forType: .html) == nil && board.pasteboardItems?.count == 1,
              "Cleaning must not retain stale rich content or duplicate pasteboard items")

        let urlOnly = "https://example.test/path?keep=%2B&utm_medium=message"
        board.clearContents()
        board.setString(urlOnly, forType: .URL)
        let urlPreparation = try await service.prepare()
        check(urlPreparation.result.url == "https://example.test/path?keep=%2B",
              "URL-only clipboard content is supported without decoding its useful query")
        try await service.commit(urlPreparation)
        check(board.string(forType: .string) == urlPreparation.result.url
              && board.string(forType: .URL) == urlPreparation.result.url,
              "URL-only sources become a consistent pair of cleaned text and URL representations")

        for (url, protected) in [
            ("https://example.test/path?keep=yes#section", false),
            ("https://example.test/download?X-Amz-Signature=fixture&utm_source=mail", true)
        ] {
            board.clearContents()
            board.setString(url, forType: .string)
            let count = board.changeCount
            let unchanged = try await service.prepare()
            check(unchanged.result.removedParameterCount == 0 && unchanged.result.isProtected == protected,
                  "Already-clean and protected links report their distinct unchanged status")
            try await service.commit(unchanged)
            check(board.changeCount == count && board.string(forType: .string) == url,
                  "Unchanged and signed links must not rewrite the clipboard or its ownership")
        }

        board.clearContents()
        board.setString(urlOnly, forType: .string)
        let outdated = try await service.prepare()
        board.clearContents()
        board.setString("a newer copied value", forType: .string)
        let newerCount = board.changeCount
        await expectError(.clipboardChanged, "A new copy between preparation and commit prevents overwrite") {
            try await service.commit(outdated)
        }
        check(board.changeCount == newerCount && board.string(forType: .string) == "a newer copied value",
              "A stale prepared link never replaces a newer clipboard value")

        board.clearContents()
        board.setString(urlOnly, forType: .string)
        let cancelPreparation = try await service.prepare()
        let countBeforeCancel = board.changeCount
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await service.commit(cancelPreparation)
        }
        do { try await cancelled.value; check(false, "An already-cancelled commit must fail") }
        catch is CancellationError { check(true, "An already-cancelled commit must fail") }
        catch { check(false, "Cancellation must remain a cancellation error: \(error)") }
        check(board.changeCount == countBeforeCancel && board.string(forType: .string) == urlOnly,
              "Cancellation before commit leaves every clipboard representation untouched")

        board.clearContents()
        await expectError(.emptyClipboard, "An empty clipboard has a specific actionable error") { _ = try await service.prepare() }
        let first = NSPasteboardItem()
        first.setString(urlOnly, forType: .string)
        let second = NSPasteboardItem()
        second.setString("https://example.test/second", forType: .string)
        board.clearContents()
        check(board.writeObjects([first, second]), "The multiple-item fixture must be written")
        let multipleCount = board.changeCount
        await expectError(.unsupportedContent, "Multiple pasteboard items are refused rather than merged or dropped") { _ = try await service.prepare() }
        check(board.changeCount == multipleCount && board.pasteboardItems?.count == 2,
              "Unsupported multi-item content remains untouched")
        board.clearContents()
        board.setData(Data([0x00, 0x01, 0x02]), forType: .png)
        let imageCount = board.changeCount
        await expectError(.unsupportedContent, "Non-text clipboard data is rejected without trying to interpret it") { _ = try await service.prepare() }
        check(board.changeCount == imageCount && board.data(forType: .png) == Data([0x00, 0x01, 0x02]),
              "Unsupported binary content remains untouched")
        let fileItem = NSPasteboardItem()
        fileItem.setString(urlOnly, forType: .string)
        fileItem.setString("file:///Synthetic/document.txt", forType: .fileURL)
        board.clearContents()
        check(board.writeObjects([fileItem]), "The copied-file fixture must be written")
        let fileCount = board.changeCount
        await expectError(.unsupportedContent, "Copied files must not be rewritten even when a text flavor resembles a web URL") {
            _ = try await service.prepare()
        }
        check(board.changeCount == fileCount && board.string(forType: .fileURL) == "file:///Synthetic/document.txt",
              "Rejected file clipboard content remains unchanged")
        board.clearContents()
        board.setString("an ordinary non-link copied sentence", forType: .string)
        let sentenceCount = board.changeCount
        do { _ = try await service.prepare(); check(false, "Non-link text must be rejected") }
        catch LinkCleaner.Error.invalidURL { check(true, "Non-link text must be rejected") }
        catch { check(false, "Unexpected non-link text error: \(error)") }
        check(board.changeCount == sentenceCount && board.string(forType: .string) == "an ordinary non-link copied sentence",
              "Invalid-link errors never change copied text")
    }

    @MainActor private static func checkController(_ application: NSApplication, board: NSPasteboard,
                                                   defaults: UserDefaults, folder: URL) async throws {
        let clipboard = ClipboardModel(defaults: defaults, fileURL: folder.appendingPathComponent("clipboard.json"), pasteboardName: board.name)
        defer { clipboard.stop() }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let service = SuspendedLinkCleaner()
        let usageURL = folder.appendingPathComponent("usage.json")
        let store = SearchUsageStore(fileURL: usageURL)
        let app = IndexedApplication(name: "Clean Link Fixture", url: URL(fileURLWithPath: "/Synthetic/CleanLinkFixture.app"))
        let icons = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil })
        let model = LauncherModel(applications: [app], usageStore: store, icons: icons)
        var applicationOpens = 0
        var browserOpens = 0
        let controller = LauncherPanelController(
            clipboard: clipboard, model: model,
            performSystemAction: { _ in fatalError("Unexpected real system action") },
            openApplication: { _, completion in applicationOpens += 1; completion(nil) },
            webSearchPreferences: WebSearchPreferences(defaults: defaults),
            openWebURL: { _, _, completion in browserOpens += 1; completion(nil) },
            resolveBrowser: { _ in nil }, linkCleaner: service,
            frontmostProcess: { nil }, restoreSource: { _ in false }
        )
        guard let window = application.windows.last(where: { $0.contentView is LauncherView }),
              let view = window.contentView as? LauncherView else { fatalError("Missing hidden launcher") }
        defer { window.contentView = nil; window.close() }
        func submit() {
            _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        }
        func numberOne(repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: "1",
                             charactersIgnoringModifiers: "1", isARepeat: repeated, keyCode: 18)!
        }
        for query in ["", "clean", "clean link", "remove tracking"] { model.setQuery(query) }
        model.setQuery("clean link")
        check(model.selectedResult == .cleanLink, "Typing the feature name selects the Clean Link command")
        check(await service.preparations == 0, "Typing, matching, and rendering never read clipboard content")
        let cleaned = try LinkCleaner.clean("https://example.test/private-fixture?keep=yes&utm_source=mail")
        await service.configure(result: cleaned, suspended: true)
        submit()
        check(model.actionStatus == LauncherText.shared.cleaningLink && model.query == "clean link",
              "Execution acknowledges clipboard work immediately without clearing the query")
        await eventually("Explicit Return starts exactly one preparation") { await service.preparations == 1 }
        submit()
        _ = view.handleNumberShortcut(numberOne())
        _ = view.handleNumberShortcut(numberOne(repeated: true))
        let repeatedPreparations = await service.preparations
        let repeatedCommits = await service.commits
        check(repeatedPreparations == 1 && repeatedCommits == 0,
              "Repeated Return and numbered shortcuts do not overlap an ongoing cleanup")
        await service.resume()
        await eventually("The prepared result commits and reports success") {
            model.actionStatus == L10n.format(LauncherText.shared.linkCleaned, 1)
        }
        check(await service.commits == 1, "A changed link commits exactly once")
        check(!policy.allowsNetwork && model.query == "clean link" && model.selectedResult == .cleanLink
              && !window.isVisible, "Cleanup works with Cue networking disabled and preserves the current launcher state")
        let initialUsage = await store.load()
        check(initialUsage == .empty, "A successful cleanup does not learn the command query or clipboard URL")
        check(browserOpens == 0, "Cleaning a clipboard link never opens a browser")

        for (result, status) in [
            (LinkCleaner.Result(url: "https://example.test/clean", removedParameterCount: 0), LauncherText.shared.linkAlreadyClean),
            (LinkCleaner.Result(url: "https://example.test/signed?sig=fixture", removedParameterCount: 0, isProtected: true), LauncherText.shared.linkProtected)
        ] {
            let commitsBefore = await service.commits
            await service.configure(result: result)
            _ = view.handleNumberShortcut(numberOne())
            await eventually("Unchanged cleanup finishes with the appropriate feedback") { model.actionStatus == status }
            check(await service.commits == commitsBefore && model.launchError == nil,
                  "Already-clean and protected results never call the write service")
        }
        for (error, status) in [
            (LinkCleaningError.emptyClipboard, LauncherText.shared.linkInvalid),
            (.unsupportedContent, LauncherText.shared.linkInvalid),
            (.accessDenied, LauncherText.shared.linkAccessDenied),
            (.clipboardChanged, LauncherText.shared.linkClipboardChanged),
            (.writeFailed, LauncherText.shared.linkWriteFailed)
        ] {
            await service.configure(result: cleaned, prepareError: error)
            submit()
            await eventually("Preparation errors become actionable launcher feedback") { model.launchError == status }
            check(model.actionStatus == nil && model.query == "clean link", "Failures clear progress without removing the command query")
        }
        await service.configure(result: cleaned, commitError: .clipboardChanged)
        submit()
        await eventually("Commit-time clipboard races report that the newer copy was retained") {
            model.launchError == LauncherText.shared.linkClipboardChanged
        }

        for cancellation in ["query", "dismiss", "invocation", "other command", "actions", "web shortcut"] {
            controller.prepareInvocation()
            model.setQuery("clean link")
            await service.configure(result: cleaned, suspended: true)
            let beforePreparations = await service.preparations
            let beforeCommits = await service.commits
            submit()
            await eventually("\(cancellation): cleanup preparation starts") { await service.preparations == beforePreparations + 1 }
            switch cancellation {
            case "query": model.setQuery("preserve my newer input")
            case "dismiss": controller.dismiss(returnFocus: false)
            case "invocation": controller.prepareInvocation()
            case "other command":
                check(model.results.contains(.application(app)), "The pending-action fixture must include its synthetic app alternative")
                model.select(LauncherResult.application(app).id)
                submit()
            case "web shortcut":
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                             windowNumber: window.windowNumber, context: nil, characters: "\r",
                                             charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                check(view.handleWebSearchShortcut(event), "Command-Return explicitly replaces the pending clipboard action")
            default: model.toggleSearchActions()
            }
            let query = model.query
            let selection = model.selectedID
            check(model.actionStatus == nil, "\(cancellation): cancellation clears cleanup progress immediately")
            await service.resume()
            try await Task.sleep(for: .milliseconds(25))
            check(await service.commits == beforeCommits && model.query == query && model.selectedID == selection
                  && model.launchError == nil && model.actionStatus == nil,
                  "\(cancellation): a late preparation cannot write, replace input, or publish obsolete feedback")
        }
        check(applicationOpens == 1, "Choosing another result executes only the injected local-app handoff")
        check(browserOpens == 1, "Only the explicit Command-Return test invokes the injected browser handoff")

        // A suspended clipboard provider must not occupy the synchronous input path.
        controller.prepareInvocation()
        model.setQuery("clean link")
        await service.configure(result: cleaned, suspended: true)
        let beforeTypingPreparations = await service.preparations
        let beforeTypingCommits = await service.commits
        submit()
        await eventually("The input responsiveness fixture begins suspended clipboard work") {
            await service.preparations == beforeTypingPreparations + 1
        }
        var samples: [Double] = []
        for index in 0..<500 {
            let start = DispatchTime.now().uptimeNanoseconds
            view.searchField.stringValue = "synthetic query \(index)"
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField))
            view.layoutSubtreeIfNeeded()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        check(model.query == "synthetic query 499" && model.actionStatus == nil,
              "Every immediate input update completes while a clipboard provider remains suspended")
        await service.resume()
        try await Task.sleep(for: .milliseconds(25))
        check(await service.commits == beforeTypingCommits && model.query == "synthetic query 499",
              "Typing cancels the delayed clipboard write without losing the final input")
        samples.sort()
        print(String(format: "Offscreen AppKit input/render during suspended clipboard work (500 edits): p95 %.3f ms, p99 %.3f ms, max %.3f ms. Excludes OS input delivery and visible composition.", samples[474], samples[494], samples[499]))
        await model.prepareForTermination()
        if let bytes = try? Data(contentsOf: usageURL), let json = String(data: bytes, encoding: .utf8) {
            check(!json.contains("command:clean-link") && !json.contains("private-fixture") && !json.contains("utm_source"),
                  "Persisted ranking history contains neither cleaned URL content nor cleanup execution history")
        }
        await clipboard.prepareForTermination()
    }
}
