import AppKit
import CueCore

private final class ConversionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value.addTimeInterval(seconds); lock.unlock() }
}

private actor ConversionTransport {
    private(set) var requests = 0
    let clock: ConversionClock
    init(_ clock: ConversionClock) { self.clock = clock }
    func fetch(_ request: URLRequest) throws -> CurrencyRatesController.Response {
        requests += 1
        guard request.url == CurrencyRatesController.endpoint, request.httpBody == nil else { fatalError("Query leaked into request") }
        let now = clock.now().timeIntervalSince1970
        let payload: [String: Any] = ["result": "success", "base_code": "USD",
            "time_last_update_unix": now - 60, "time_next_update_unix": now + 3600,
            "rates": ["USD": 1, "TWD": 32, "EUR": 0.9, "JPY": 150]]
        return .init(data: try JSONSerialization.data(withJSONObject: payload), statusCode: 200, url: CurrencyRatesController.endpoint)
    }
}

private actor ConversionWriter {
    let name: NSPasteboard.Name
    private(set) var attempts = 0
    private(set) var completed = 0
    private(set) var writes = 0
    private var held = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    init(_ name: NSPasteboard.Name) { self.name = name }
    func hold(_ value: Bool) { held = value }
    func release() { let saved = pending; pending = []; for waiter in saved { waiter.resume() } }
    func copy(_ text: String) async throws {
        attempts += 1
        defer { completed += 1 }
        if held { await withCheckedContinuation { pending.append($0) } }
        try Task.checkCancellation()
        let board = NSPasteboard(name: name)
        board.clearContents()
        guard board.setString(text, forType: .string) else { throw CocoaError(.fileWriteUnknown) }
        writes += 1
    }
}

@main struct CheckUnitConversion {
    @MainActor static var checks = 0
    @MainActor static func check(_ value: Bool, _ message: String) {
        guard value else { print("FAIL: \(message)"); exit(1) }; checks += 1
    }
    @MainActor static func eventually(_ message: String, _ predicate: () async -> Bool) async {
        for _ in 0..<2000 { if await predicate() { check(true, message); return }; try? await Task.sleep(for: .milliseconds(1)) }
        check(false, message)
    }
    @MainActor static func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let domain = "com.yyhsiu.cue.tests.units.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: NSPasteboard.Name(domain)); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("synthetic original", forType: .string)
        let unchanged = board.changeCount
        let clock = ConversionClock()
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let fixture = ConversionTransport(clock)
        let currency = CurrencyRatesController(policy: policy, cacheFile: nil, clock: { clock.now() }, transport: { try await fixture.fetch($0) })
        let store = SearchUsageStore(fileURL: folder.appendingPathComponent("usage.json"))
        let matchingApp = IndexedApplication(name: "5坪 Fixture", url: URL(fileURLWithPath: "/Synthetic/Units.app"))
        let model = LauncherModel(applications: [matchingApp], usageStore: store, currencyRates: currency,
                                  icons: AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil }))
        let clipboard = ClipboardModel(defaults: defaults, fileURL: folder.appendingPathComponent("clipboard.json"), pasteboardName: board.name)
        defer { clipboard.stop() }
        let writer = ConversionWriter(board.name)
        let web = WebSearchPreferences(defaults: defaults); web.setEnabled(false)
        let controller = LauncherPanelController(clipboard: clipboard, model: model,
            openApplication: { _, completion in completion(nil) }, webSearchPreferences: web,
            openWebURL: { _, _, _ in fatalError("No browser handoff expected") },
            copyCalculation: { try await writer.copy($0) }, frontmostProcess: { nil })
        guard let window = application.windows.last(where: { $0.contentView is LauncherView }), let view = window.contentView as? LauncherView else { fatalError("Missing view") }
        defer { window.contentView = nil; window.close() }
        func type(_ text: String) { view.searchField.stringValue = text; view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.searchField)); view.layoutSubtreeIfNeeded() }
        func submit() { _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))) }
        func converted() -> [ConversionResult] { model.results.compactMap { if case .conversion(let result) = $0 { return result }; return nil } }
        type(""); check(model.results.isEmpty && view.preferredHeight == 56, "Blank invocation stays minimal")
        type("5坪")
        check(converted().count == 3 && converted().first?.unitSymbol == "m²", "坪 gives three local common conversions immediately")
        check(model.results.last == .application(matchingApp), "Matching apps remain below unit answers")
        check(board.changeCount == unchanged, "Typing conversions never touches clipboard")
        type("10 m to ft"); check(converted().count == 1 && converted().first?.unitSymbol == "ft", "Explicit target shows one answer")
        let answer = converted().first!.value
        submit()
        await eventually("Return copies a conversion and closes", { await writer.writes == 1 && model.query.isEmpty })
        check(board.string(forType: .string) == answer, "Copy contains only numeric value")
        type("100 USD"); check(model.results.first == .currencyStatus(.networkRequired), "Currency is disabled while policy is off")
        check(await fixture.requests == 0, "OFF starts no request")
        submit(); check(model.query == "100 USD", "Disabled result does not run or close")
        policy.setAllowsNetwork(true)
        await eventually("Currency becomes ready after allowed request", { converted().count == 3 })
        check(converted().first?.value == "3200" && converted().first?.unitSymbol == "TWD", "Foreign currency prioritizes TWD")
        check(await fixture.requests == 1, "One fixed table request serves all currencies")
        check(model.currencyRateDate != nil, "Reference date is available")
        check(descendants(view).compactMap { $0 as? NSButton }.contains { !$0.isHidden && $0.title == "Rates By Exchange Rate API" }, "Visible provider attribution is linked")
        type("200USD to TWD"); check(converted().first?.value == "6400", "Amount changes recalculate synchronously")
        check(await fixture.requests == 1, "Typing reuses daily rates")
        await writer.hold(true)
        submit(); await eventually("Currency copy entered writer", { await writer.attempts == 2 })
        policy.setAllowsNetwork(false); await writer.release()
        await eventually("Revocation replaces currency rows", { model.results.first == .currencyStatus(.networkRequired) })
        await eventually("Cancelled writer finishes", { await writer.completed == 2 })
        check(await writer.writes == 1, "Revocation cancels pending copy before write")
        policy.setAllowsNetwork(true)
        await eventually("Fresh cache is restored only when allowed", { converted().count == 1 })
        await writer.hold(false)
        let attempts = await writer.attempts
        clock.advance(3601)
        submit()
        let afterExpiredSubmit = model.results.first
        check(await writer.attempts == attempts && afterExpiredSubmit == .currencyStatus(.loading), "Action-time expiry prevents stale answer copy")
        await eventually("Expired rates refresh asynchronously", { converted().count == 1 })
        type("5坪"); model.recordSuccessfulAction(resultID: LauncherResult.application(matchingApp).id, query: model.query)
        await model.prepareForTermination()
        check(await store.load() == .empty, "Alternate app action cannot learn conversion text")
        var samples: [Double] = []
        for index in 0..<500 {
            let start = DispatchTime.now().uptimeNanoseconds
            type("\(index + 1)坪")
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        samples.sort()
        print("Unit conversion input/search/native layout (500 cold queries): p50 \(samples[250]) ms; p99 \(samples[495]); max \(samples.last!)")
        print("Unit conversion integration passed: \(checks) checks; private pasteboard, synthetic rates, no real network or user data.")
        _ = controller
    }
}
