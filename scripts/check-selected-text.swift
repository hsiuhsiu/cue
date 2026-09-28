import AppKit
import ApplicationServices

/// No real AX elements or general pasteboard are accessed by this driver.
private final class StubSelectedTextDriver: SelectedTextDriver, @unchecked Sendable {
    enum PasteBehavior { case apply, fail, ignore, copyElsewhere, delayedAcknowledgement, delayedConsumption }

    private let lock = NSLock()
    private var state: SelectedTextState
    private var trusted: Bool
    private var sourceFocused = true
    private var focusChecks = 0
    private var delayedFocusChecks = 0
    private var captureCount = 0
    private var pasteCount = 0
    private var releaseCount = 0
    private var acknowledgementReads = 0
    private var pastedValue: String?
    private var markerObserved = false
    private var behavior: PasteBehavior = .apply
    private let boardName: NSPasteboard.Name

    init(boardName: NSPasteboard.Name, state: SelectedTextState, trusted: Bool = true) {
        self.boardName = boardName
        self.state = state
        self.trusted = trusted
    }

    func isTrusted() -> Bool { lock.withLock { trusted } }
    func capture(processID: Int32) throws -> SelectedTextState {
        lock.withLock { captureCount += 1; return state }
    }
    func currentState(for expected: SelectedTextState) throws -> SelectedTextState { lock.withLock { state } }
    func isSourceFocused(_ expected: SelectedTextState) throws -> Bool {
        lock.withLock {
            focusChecks += 1
            if delayedFocusChecks > 0 {
                delayedFocusChecks -= 1
                return false
            }
            return sourceFocused
        }
    }
    func postPaste(to processID: Int32) throws {
        try lock.withLock {
            pasteCount += 1
            if behavior == .fail { throw SelectedTextError.replacementFailed }
            if behavior == .delayedConsumption { return }
            let board = NSPasteboard(name: boardName)
            guard let text = board.string(forType: .string) else { throw SelectedTextError.clipboardUnavailable }
            markerObserved = board.string(forType: SelectedTextPasteboard.marker) != nil
                && (board.types ?? []).contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            if behavior != .ignore { pastedValue = try SelectedTextValidation.replacing(state, with: text) }
            if behavior == .delayedAcknowledgement { acknowledgementReads = 4 }
            if behavior == .copyElsewhere {
                board.clearContents()
                board.setString("new user copy", forType: .string)
            }
        }
    }
    func value(for expected: SelectedTextState) throws -> String {
        lock.withLock {
            if acknowledgementReads > 0 {
                acknowledgementReads -= 1
                return state.value
            }
            return pastedValue ?? state.value
        }
    }
    func release(_ elementID: UUID) { lock.withLock { releaseCount += 1 } }
    func setState(_ state: SelectedTextState) { lock.withLock { self.state = state } }
    func setFocused(_ value: Bool) { lock.withLock { sourceFocused = value } }
    func delayFocus(forChecks count: Int) { lock.withLock { delayedFocusChecks = count } }
    func focusCheckCount() -> Int { lock.withLock { focusChecks } }
    func setBehavior(_ value: PasteBehavior) { lock.withLock { behavior = value } }
    func consumeDelayedPaste() throws {
        try lock.withLock {
            guard pasteCount == 1, behavior == .delayedConsumption,
                  let text = NSPasteboard(name: boardName).string(forType: .string) else {
                throw SelectedTextError.replacementFailed
            }
            pastedValue = try SelectedTextValidation.replacing(state, with: text)
        }
    }
    func counts() -> (captures: Int, pastes: Int, releases: Int, marked: Bool) {
        lock.withLock { (captureCount, pasteCount, releaseCount, markerObserved) }
    }
}

private actor HookCounter {
    private(set) var starts = 0
    private(set) var ends = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func start(suspend: Bool = false) async {
        starts += 1
        if suspend { await withCheckedContinuation { continuation = $0 } }
    }
    func end() { ends += 1 }
    func resume() { continuation?.resume(); continuation = nil }
    func isSuspended() -> Bool { continuation != nil }
    func counts() -> (Int, Int) { (starts, ends) }
}

@main
struct CheckSelectedText {
    @MainActor private static var checks = 0
    private static let processID: Int32 = 424_242

    @MainActor private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    private static func state(id: UUID = UUID(), role: String = kAXTextAreaRole, secure: Bool = false,
                              enabled: Bool = true, editable: Bool = true, selected: String = "简体文字",
                              range: NSRange? = nil, value: String? = nil) -> SelectedTextState {
        let fullValue = value ?? "before 👩🏽‍💻 \(selected) after"
        return SelectedTextState(elementID: id, processID: processID, role: role, isSecure: secure,
                                 isEnabled: enabled, isEditable: editable, canSetSelectedText: false,
                                 text: selected, range: range ?? (fullValue as NSString).range(of: selected), value: fullValue)
    }

    @MainActor private static func expect(_ expected: SelectedTextError,
                                         _ operation: () async throws -> Void) async {
        do { try await operation(); check(false, "Expected \(expected)") }
        catch { check(error as? SelectedTextError == expected, "Expected \(expected), received \(type(of: error))") }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let boardName = NSPasteboard.Name("com.yyhsiu.cue.tests.selection.\(UUID())")
        let board = NSPasteboard(name: boardName)
        defer { board.releaseGlobally() }

        func seedClipboard() {
            let item = NSPasteboardItem()
            item.setString("previous clipboard", forType: .string)
            item.setData(Data([0, 1, 2, 255]), forType: NSPasteboard.PasteboardType("com.yyhsiu.test.binary"))
            board.clearContents()
            board.writeObjects([item])
        }
        seedClipboard()
        let initialCount = board.changeCount
        let untrusted = StubSelectedTextDriver(boardName: boardName, state: state(), trusted: false)
        let noPermission = SelectedTextService(driver: untrusted, pasteboardName: boardName)
        check(untrusted.counts().captures == 0, "Construction must not inspect selection")
        await expect(.permissionRequired) { _ = try await noPermission.capture(processID: processID) }
        check(untrusted.counts().captures == 0 && board.changeCount == initialCount,
              "Missing permission must not read selection or alter clipboard")
        await expect(.noTarget) { _ = try await noPermission.capture(processID: 0) }

        let invalidStates: [(SelectedTextState, SelectedTextError)] = [
            (state(secure: true), .secureField),
            (state(role: kAXStaticTextRole), .unsupportedField),
            (state(editable: false), .readOnly),
            (state(enabled: false), .readOnly),
            (state(selected: "", range: NSRange(location: 0, length: 0)), .noSelection),
            (state(range: NSRange(location: Int.max, length: 4)), .unsupportedField),
            (state(range: NSRange(location: 0, length: 4)), .unsupportedField),
            (state(selected: String(repeating: "字", count: 90_000)), .textTooLarge),
        ]
        for (invalid, expected) in invalidStates {
            let driver = StubSelectedTextDriver(boardName: boardName, state: invalid)
            let service = SelectedTextService(driver: driver, pasteboardName: boardName)
            await expect(expected) { _ = try await service.capture(processID: processID) }
            check(driver.counts().pastes == 0, "Invalid selection never posts Paste")
        }

        let original = state()
        let staleStates = [
            state(id: UUID()),
            state(id: original.elementID, selected: "另一段文字"),
            state(id: original.elementID, value: "moved before 👩🏽‍💻 简体文字 after"),
            state(id: original.elementID, value: "before 👩🏽‍💻 简体文字 changed outside selection"),
        ]
        for changed in staleStates {
            let driver = StubSelectedTextDriver(boardName: boardName, state: original)
            let service = SelectedTextService(driver: driver, pasteboardName: boardName)
            let session = try await service.capture(processID: processID)
            driver.setState(changed)
            await expect(.selectionChanged) { try await service.replace(session, with: "正體文字") }
            check(driver.counts().pastes == 0 && board.changeCount == initialCount,
                  "Changed element/range/selection/document cannot write or overwrite clipboard")
        }

        let unfocused = StubSelectedTextDriver(boardName: boardName, state: original)
        let unfocusedService = SelectedTextService(driver: unfocused, pasteboardName: boardName)
        let unfocusedSession = try await unfocusedService.capture(processID: processID)
        unfocused.setFocused(false)
        let focusTimeoutStart = ContinuousClock.now
        await expect(.selectionChanged) { try await unfocusedService.replace(unfocusedSession, with: "正體文字") }
        check(unfocused.counts().pastes == 0 && board.changeCount == initialCount,
              "A source-focus timeout never pastes into another app or changes clipboard")
        check(focusTimeoutStart.duration(to: .now) < .seconds(2), "Source focus readiness has a bounded deadline")

        // A source activation request can finish asynchronously after Cue dismisses.
        let delayedFocus = StubSelectedTextDriver(boardName: boardName, state: original)
        delayedFocus.delayFocus(forChecks: 3)
        let delayedFocusService = SelectedTextService(driver: delayedFocus, pasteboardName: boardName)
        let delayedFocusSession = try await delayedFocusService.capture(processID: processID)
        try await delayedFocusService.replace(delayedFocusSession, with: "正體文字")
        check(delayedFocus.focusCheckCount() >= 4 && delayedFocus.counts().pastes == 1,
              "Observed delayed source focus allows one paste after readiness")
        check(board.string(forType: .string) == "previous clipboard", "Delayed focus still restores clipboard after acknowledged replacement")

        let changedDuringHandoff = StubSelectedTextDriver(boardName: boardName, state: original)
        changedDuringHandoff.delayFocus(forChecks: 2)
        let changedDuringHandoffService = SelectedTextService(driver: changedDuringHandoff, pasteboardName: boardName)
        let changedDuringHandoffSession = try await changedDuringHandoffService.capture(processID: processID)
        changedDuringHandoff.setState(state(id: original.elementID, value: "before 👩🏽‍💻 简体文字 edited elsewhere"))
        let beforeChangedHandoff = board.changeCount
        await expect(.selectionChanged) {
            try await changedDuringHandoffService.replace(changedDuringHandoffSession, with: "正體文字")
        }
        check(changedDuringHandoff.counts().pastes == 0 && board.changeCount == beforeChangedHandoff,
              "Focus readiness never relaxes full-value validation after the handoff")

        // Cancellation during readiness must not wait for the deadline or touch clipboard.
        let focusCancelled = StubSelectedTextDriver(boardName: boardName, state: original)
        focusCancelled.setFocused(false)
        let focusCancelledHooks = HookCounter()
        let focusCancelledService = SelectedTextService(driver: focusCancelled, pasteboardName: boardName,
            beforePaste: { await focusCancelledHooks.start() }, afterPaste: { await focusCancelledHooks.end() })
        let focusCancelledSession = try await focusCancelledService.capture(processID: processID)
        let beforeCancelledFocus = board.changeCount
        let focusOperation = Task { try await focusCancelledService.replace(focusCancelledSession, with: "正體文字") }
        for _ in 0..<200 {
            if focusCancelled.focusCheckCount() > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        check(focusCancelled.focusCheckCount() > 0, "Cancellation fixture reached observed focus readiness")
        focusOperation.cancel()
        do { try await focusOperation.value; check(false, "Focus-readiness cancellation must throw") }
        catch { check(error is CancellationError, "Focus readiness propagates cancellation") }
        let focusHookCounts = await focusCancelledHooks.counts()
        check(focusCancelled.counts().pastes == 0 && board.changeCount == beforeCancelledFocus
              && focusHookCounts == (0, 0), "Cancellation during focus handoff never begins clipboard mutation")

        let driver = StubSelectedTextDriver(boardName: boardName, state: original)
        let hooks = HookCounter()
        let service = SelectedTextService(driver: driver, pasteboardName: boardName,
            beforePaste: { await hooks.start() }, afterPaste: { await hooks.end() })
        let beforeCapture = board.changeCount
        let session = try await service.capture(processID: processID)
        check(session.text == "简体文字" && board.changeCount == beforeCapture,
              "Capture reads selected text only without copying or changing clipboard")
        try await service.replace(session, with: "正體文字")
        let hookCounts = await hooks.counts()
        check(hookCounts == (1, 1), "Successful paste brackets clipboard-monitor suspension")
        check(driver.counts().pastes == 1 && driver.counts().marked, "Exactly one transient-marked paste is posted")
        let convertedValue = try driver.value(for: original)
        check(convertedValue == "before 👩🏽‍💻 正體文字 after", "UTF-16 selection replacement preserves emoji and surrounding text")
        check(board.string(forType: .string) == "previous clipboard", "Original text clipboard is restored after acknowledgement")
        check(board.data(forType: NSPasteboard.PasteboardType("com.yyhsiu.test.binary")) == Data([0, 1, 2, 255]),
              "Additional clipboard representations survive restoration")
        await expect(.selectionChanged) { try await service.replace(session, with: "another value") }
        check(driver.counts().pastes == 1, "A consumed session cannot perform a second edit")

        for behavior in [StubSelectedTextDriver.PasteBehavior.fail, .ignore, .copyElsewhere] {
            seedClipboard()
            let driver = StubSelectedTextDriver(boardName: boardName, state: original)
            driver.setBehavior(behavior)
            let hooks = HookCounter()
            let service = SelectedTextService(driver: driver, pasteboardName: boardName,
                beforePaste: { await hooks.start() }, afterPaste: { await hooks.end() })
            let session = try await service.capture(processID: processID)
            switch behavior {
            case .fail: await expect(.replacementFailed) { try await service.replace(session, with: "正體文字") }
            case .ignore: await expect(.replacementUnverified) { try await service.replace(session, with: "正體文字") }
            default: try await service.replace(session, with: "正體文字")
            }
            let counts = await hooks.counts()
            check(counts == (1, 1), "Monitor resumes after success, failure, and unconfirmed paste")
            check(driver.counts().pastes == 1, "Unconfirmed or failed paste is never retried")
            let expectedClipboard = behavior == .copyElsewhere ? "new user copy"
                : behavior == .ignore ? "正體文字" : "previous clipboard"
            check(board.string(forType: .string) == expectedClipboard,
                  "Cleanup restores owned clipboard only before posting or after acknowledged completion")
        }

        // The target may not consume its queued Paste until after the acknowledgement
        // deadline. Restoring the backup at timeout would insert unrelated clipboard data.
        seedClipboard()
        let delayedDriver = StubSelectedTextDriver(boardName: boardName, state: original)
        delayedDriver.setBehavior(.delayedConsumption)
        let delayedService = SelectedTextService(driver: delayedDriver, pasteboardName: boardName)
        let delayedSession = try await delayedService.capture(processID: processID)
        await expect(.replacementUnverified) {
            try await delayedService.replace(delayedSession, with: "正體文字")
        }
        check(board.string(forType: .string) == "正體文字"
              && board.string(forType: SelectedTextPasteboard.marker) != nil,
              "Unverified posted Paste keeps its transient converted payload available")
        try delayedDriver.consumeDelayedPaste()
        let delayedValue = try delayedDriver.value(for: original)
        check(delayedValue == "before 👩🏽‍💻 正體文字 after" && delayedDriver.counts().pastes == 1,
              "Late Paste consumption receives converted text, never the restored original clipboard")

        // Cancellation before paste releases the pause and leaves the clipboard alone.
        seedClipboard()
        let cancelledDriver = StubSelectedTextDriver(boardName: boardName, state: original)
        let gate = HookCounter()
        let cancelledService = SelectedTextService(driver: cancelledDriver, pasteboardName: boardName,
            beforePaste: { await gate.start(suspend: true) }, afterPaste: { await gate.end() })
        let cancelledSession = try await cancelledService.capture(processID: processID)
        let operation = Task { try await cancelledService.replace(cancelledSession, with: "正體文字") }
        while !(await gate.isSuspended()) { await Task.yield() }
        operation.cancel()
        await gate.resume()
        do { try await operation.value; check(false, "Cancellation must throw before a write") }
        catch { check(error is CancellationError, "Cancellation propagates distinctly") }
        let cancelledCounts = await gate.counts()
        check(cancelledCounts == (1, 1) && cancelledDriver.counts().pastes == 0,
              "Cancellation resumes monitor without posting an event")
        check(board.string(forType: .string) == "previous clipboard", "Cancellation before paste preserves clipboard")

        // Cancellation after posting must not restore before the source reads it.
        let postedDriver = StubSelectedTextDriver(boardName: boardName, state: original)
        postedDriver.setBehavior(.delayedAcknowledgement)
        let postedService = SelectedTextService(driver: postedDriver, pasteboardName: boardName)
        let postedSession = try await postedService.capture(processID: processID)
        let postedOperation = Task { try await postedService.replace(postedSession, with: "正體文字") }
        while postedDriver.counts().pastes == 0 { await Task.yield() }
        postedOperation.cancel()
        try await postedOperation.value
        check(postedDriver.counts().pastes == 1 && board.string(forType: .string) == "previous clipboard",
              "Cancellation after posting still acknowledges one edit before restoring clipboard")

        let discardedDriver = StubSelectedTextDriver(boardName: boardName, state: original)
        let discardedService = SelectedTextService(driver: discardedDriver, pasteboardName: boardName)
        let discardedSession = try await discardedService.capture(processID: processID)
        await discardedService.discard(discardedSession)
        await expect(.selectionChanged) { try await discardedService.replace(discardedSession, with: "正體文字") }
        check(discardedDriver.counts().releases == 1 && discardedDriver.counts().pastes == 0,
              "Discard releases transient state and cannot edit")

        // Already-converted text must not disturb the clipboard or create an Undo step.
        let noChangeDriver = StubSelectedTextDriver(boardName: boardName, state: original)
        let noChangeService = SelectedTextService(driver: noChangeDriver, pasteboardName: boardName)
        let noChangeSession = try await noChangeService.capture(processID: processID)
        let beforeNoChange = board.changeCount
        try await noChangeService.replace(noChangeSession, with: original.text)
        check(noChangeDriver.counts().pastes == 0 && board.changeCount == beforeNoChange,
              "Unchanged conversion performs no paste or clipboard write")

        // Preserve an empty clipboard as empty, including after asynchronous backup.
        board.clearContents()
        let emptyDriver = StubSelectedTextDriver(boardName: boardName, state: original)
        let emptyService = SelectedTextService(driver: emptyDriver, pasteboardName: boardName)
        let emptySession = try await emptyService.capture(processID: processID)
        try await emptyService.replace(emptySession, with: "正體文字")
        check((board.types ?? []).isEmpty, "An originally empty clipboard is restored as empty")

        // Reject an unpreservable clipboard before replacing the selection or its contents.
        board.clearContents()
        board.setData(Data(repeating: 1, count: 16 * 1_024 * 1_024 + 1),
                      forType: NSPasteboard.PasteboardType("com.yyhsiu.test.oversized"))
        let oversizedCount = board.changeCount
        let largeDriver = StubSelectedTextDriver(boardName: boardName, state: original)
        let largeService = SelectedTextService(driver: largeDriver, pasteboardName: boardName)
        let largeSession = try await largeService.capture(processID: processID)
        await expect(.clipboardUnavailable) { try await largeService.replace(largeSession, with: "正體文字") }
        check(largeDriver.counts().pastes == 0 && board.changeCount == oversizedCount,
              "Oversized clipboard preservation failure leaves both selection and clipboard untouched")
        check(!NSApplication.shared.isActive, "The harness never activates a UI application")
        print("Selected-text service passed: \(checks) checks; synthetic driver and private pasteboard only.")
    }
}
