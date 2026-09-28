import AppKit
import ApplicationServices

struct SelectedTextSession: Equatable, Sendable {
    let id: UUID
    let processID: Int32
    let text: String

    init(id: UUID = UUID(), processID: Int32, text: String) {
        self.id = id
        self.processID = processID
        self.text = text
    }
}

enum SelectedTextError: Error, Equatable, Sendable {
    case permissionRequired, noTarget, noSelection, secureField, readOnly
    case unsupportedField, selectionChanged, textTooLarge, applicationUnavailable
    case clipboardUnavailable, replacementFailed, replacementUnverified, busy
}

protocol SelectedTextAccessing: Sendable {
    func capture(processID: Int32) async throws -> SelectedTextSession
    func replace(_ session: SelectedTextSession, with text: String) async throws
    func discard(_ session: SelectedTextSession) async
}

/// Only transient selection state crosses the testing boundary. It is never logged or saved.
struct SelectedTextState: Equatable, Sendable {
    let elementID: UUID
    let processID: Int32
    let role: String
    let isSecure: Bool
    let isEnabled: Bool
    let isEditable: Bool
    let canSetSelectedText: Bool
    let text: String
    let range: NSRange
    let value: String
}

/// The service owns a single driver and calls every method on its actor executor.
/// Synchronous methods intentionally have no actor suspension between final validation
/// and posting a write. Tests inject a synthetic driver instead of contacting another app.
protocol SelectedTextDriver: Sendable {
    func isTrusted() -> Bool
    func capture(processID: Int32) throws -> SelectedTextState
    func currentState(for expected: SelectedTextState) throws -> SelectedTextState
    func isSourceFocused(_ expected: SelectedTextState) throws -> Bool
    func postPaste(to processID: Int32) throws
    func value(for expected: SelectedTextState) throws -> String
    func release(_ elementID: UUID)
}

enum SelectedTextValidation {
    static let maximumSelectionBytes = 256 * 1_024
    static let maximumDocumentUTF16Length = 1_024 * 1_024

    static func eligible(_ state: SelectedTextState) throws {
        guard !state.isSecure else { throw SelectedTextError.secureField }
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(state.role) else {
            throw SelectedTextError.unsupportedField
        }
        guard state.isEnabled, state.isEditable else { throw SelectedTextError.readOnly }
        guard !state.text.isEmpty, state.range.length > 0 else { throw SelectedTextError.noSelection }
        guard state.text.utf8.count <= maximumSelectionBytes,
              state.value.utf16.count <= maximumDocumentUTF16Length else {
            throw SelectedTextError.textTooLarge
        }
        let value = state.value as NSString
        guard state.range.location >= 0, state.range.location <= value.length,
              state.range.length <= value.length - state.range.location,
              exact(value.substring(with: state.range), state.text) else {
            throw SelectedTextError.unsupportedField
        }
    }

    static func unchanged(_ current: SelectedTextState, from expected: SelectedTextState) throws {
        try eligible(current)
        guard current.elementID == expected.elementID, current.processID == expected.processID,
              current.range == expected.range, exact(current.text, expected.text),
              exact(current.value, expected.value) else { throw SelectedTextError.selectionChanged }
    }

    static func replacing(_ state: SelectedTextState, with text: String) throws -> String {
        guard !text.isEmpty, text.utf8.count <= maximumSelectionBytes else {
            throw SelectedTextError.textTooLarge
        }
        let result = (state.value as NSString).replacingCharacters(in: state.range, with: text)
        guard result.utf16.count <= maximumDocumentUTF16Length else { throw SelectedTextError.textTooLarge }
        return result
    }

    static func exact(_ left: String, _ right: String) -> Bool {
        left.utf16.elementsEqual(right.utf16)
    }
}

/// No service is contacted during construction, launcher invocation, or search.
/// AX and pasteboard calls occur on this actor only after explicit command execution.
actor SelectedTextService: SelectedTextAccessing {
    private let driver: any SelectedTextDriver
    private let pasteboardName: NSPasteboard.Name
    private let beforePaste: @Sendable () async -> Void
    private let afterPaste: @Sendable () async -> Void
    private let backupReader = SelectedTextBackupReader()
    private var pending: (session: SelectedTextSession, state: SelectedTextState, captured: ContinuousClock.Instant)?
    private var replacingID: UUID?
    private var cancelledID: UUID?

    init(driver: any SelectedTextDriver = AXSelectedTextDriver(),
         pasteboardName: NSPasteboard.Name = .general,
         beforePaste: @escaping @Sendable () async -> Void = {},
         afterPaste: @escaping @Sendable () async -> Void = {}) {
        self.driver = driver
        self.pasteboardName = pasteboardName
        self.beforePaste = beforePaste
        self.afterPaste = afterPaste
    }

    func capture(processID: Int32) throws -> SelectedTextSession {
        guard replacingID == nil else { throw SelectedTextError.busy }
        if let pending { driver.release(pending.state.elementID) }
        pending = nil
        guard processID > 0, processID != ProcessInfo.processInfo.processIdentifier else {
            throw SelectedTextError.noTarget
        }
        guard driver.isTrusted() else { throw SelectedTextError.permissionRequired }
        try Task.checkCancellation()
        let state = try driver.capture(processID: processID)
        do {
            guard state.processID == processID else { throw SelectedTextError.selectionChanged }
            try SelectedTextValidation.eligible(state)
            try Task.checkCancellation()
        } catch {
            driver.release(state.elementID)
            throw error
        }
        let session = SelectedTextSession(processID: processID, text: state.text)
        pending = (session, state, .now)
        return session
    }

    func discard(_ session: SelectedTextSession) {
        if replacingID == session.id { cancelledID = session.id }
        if pending?.session.id == session.id {
            if let pending { driver.release(pending.state.elementID) }
            pending = nil
        }
    }

    func replace(_ session: SelectedTextSession, with text: String) async throws {
        guard replacingID == nil else { throw SelectedTextError.busy }
        guard let captured = pending, captured.session == session else {
            throw SelectedTextError.selectionChanged
        }
        guard captured.captured.duration(to: .now) < .seconds(30) else {
            driver.release(captured.state.elementID)
            pending = nil
            throw SelectedTextError.selectionChanged
        }
        pending = nil
        replacingID = session.id
        cancelledID = nil
        defer {
            driver.release(captured.state.elementID)
            replacingID = nil
            cancelledID = nil
        }
        let state = captured.state
        guard driver.isTrusted() else { throw SelectedTextError.permissionRequired }
        let expectedValue = try SelectedTextValidation.replacing(state, with: text)
        try await waitForSourceFocus(state, sessionID: session.id)
        try validateBeforeWrite(state, sessionID: session.id)
        if SelectedTextValidation.exact(text, state.text) { return }

        // An AX setter does not promise participation in the source app's Undo
        // manager. Use its normal Paste command, which also supports editors that
        // expose readable selection attributes but no writable AXSelectedText.
        // Never rewrite AXValue or retry after an unconfirmed paste.
        await beforePaste()
        do {
            try validateBeforeWrite(state, sessionID: session.id)
            let board = NSPasteboard(name: pasteboardName)
            let backup = try await backupReader.snapshot(name: pasteboardName)
            // Snapshotting promised clipboard data can take time; revalidate afterward.
            try validateBeforeWrite(state, sessionID: session.id)
            let ownership = try SelectedTextPasteboard.install(text, on: board, replacing: backup)
            var pasteWasPosted = false
            do {
                // No suspension between this focus/range/content check and the event.
                try validateBeforeWrite(state, sessionID: session.id)
                guard SelectedTextPasteboard.stillOwns(board, ownership) else {
                    throw SelectedTextError.clipboardUnavailable
                }
                try driver.postPaste(to: state.processID)
                pasteWasPosted = true
                // Continue acknowledgement even if the command is cancelled after the
                // event: restoring too early could paste the old clipboard contents.
                guard await acknowledge(expectedValue, in: state) else {
                    throw SelectedTextError.replacementUnverified
                }
            } catch {
                // A queued Paste can be consumed after the acknowledgement deadline.
                // Restoring the previous clipboard then would insert unrelated data.
                // Keep the transient conversion available after an unverified posted
                // edit, and report the uncertainty; do not retry or poll indefinitely.
                if !pasteWasPosted {
                    SelectedTextPasteboard.restore(backup, on: board, ifOwned: ownership)
                }
                throw error
            }
            SelectedTextPasteboard.restore(backup, on: board, ifOwned: ownership)
        } catch {
            await afterPaste()
            throw error
        }
        await afterPaste()
    }

    private func waitForSourceFocus(_ state: SelectedTextState, sessionID: UUID) async throws {
        // The controller has already requested one source-app activation. Observe
        // its real AX focus rather than assuming the request completed synchronously.
        // Usually the first check succeeds, so there is no unconditional delay.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        repeat {
            try Task.checkCancellation()
            guard cancelledID != sessionID else { throw CancellationError() }
            do {
                if try driver.isSourceFocused(state) { return }
            } catch SelectedTextError.permissionRequired {
                throw SelectedTextError.permissionRequired
            } catch {
                // The focused application/element may briefly be absent during the
                // handoff. This grants no permission to edit; final validation below
                // still requires the original element, range, text, and full value.
            }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw SelectedTextError.selectionChanged }
            try await Task.sleep(for: min(.milliseconds(8), remaining))
        } while ContinuousClock.now < deadline
        throw SelectedTextError.selectionChanged
    }

    private func validateBeforeWrite(_ state: SelectedTextState, sessionID: UUID) throws {
        try Task.checkCancellation()
        guard cancelledID != sessionID else { throw CancellationError() }
        guard try driver.isSourceFocused(state) else { throw SelectedTextError.selectionChanged }
        try SelectedTextValidation.unchanged(driver.currentState(for: state), from: state)
        guard try driver.isSourceFocused(state) else { throw SelectedTextError.selectionChanged }
    }

    private func acknowledge(_ expectedValue: String, in state: SelectedTextState) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(800))
        repeat {
            if let value = try? driver.value(for: state), SelectedTextValidation.exact(value, expectedValue) {
                return true
            }
            if ContinuousClock.now >= deadline { break }
            // This polls an actual pending edit, not the typing path. The detached wait
            // is intentionally cancellation-independent after a paste was posted.
            await Task.detached { try? await Task.sleep(for: .milliseconds(15)) }.value
        } while ContinuousClock.now < deadline
        return false
    }
}

/// The actor owns this driver exclusively. AX references never leave its executor.
final class AXSelectedTextDriver: SelectedTextDriver, @unchecked Sendable {
    private var elements: [UUID: AXUIElement] = [:]
    private let timeout: Float = 0.15

    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func capture(processID: Int32) throws -> SelectedTextState {
        let app = AXUIElementCreateApplication(processID)
        try configure(app)
        let element = try elementAttribute(app, kAXFocusedUIElementAttribute)
        try configure(element)
        let id = UUID()
        let state = try read(element, id: id, processID: processID)
        elements[id] = element
        return state
    }

    func currentState(for expected: SelectedTextState) throws -> SelectedTextState {
        guard let original = elements[expected.elementID] else { throw SelectedTextError.selectionChanged }
        let app = AXUIElementCreateApplication(expected.processID)
        try configure(app)
        let focused = try elementAttribute(app, kAXFocusedUIElementAttribute)
        guard CFEqual(focused, original) else { throw SelectedTextError.selectionChanged }
        return try read(original, id: expected.elementID, processID: expected.processID)
    }

    func isSourceFocused(_ expected: SelectedTextState) throws -> Bool {
        let system = AXUIElementCreateSystemWide()
        try configure(system)
        let focusedApp = try elementAttribute(system, kAXFocusedApplicationAttribute)
        var pid: pid_t = 0
        guard AXUIElementGetPid(focusedApp, &pid) == .success else {
            throw SelectedTextError.applicationUnavailable
        }
        guard pid == expected.processID, let original = elements[expected.elementID] else { return false }
        let focused = try elementAttribute(system, kAXFocusedUIElementAttribute)
        return CFEqual(focused, original)
    }

    func postPaste(to processID: Int32) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            throw SelectedTextError.replacementFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(processID)
        up.postToPid(processID)
    }

    func value(for expected: SelectedTextState) throws -> String {
        guard let element = elements[expected.elementID] else { throw SelectedTextError.selectionChanged }
        return try stringAttribute(element, kAXValueAttribute,
                                   maximumLength: SelectedTextValidation.maximumDocumentUTF16Length)
    }

    func release(_ elementID: UUID) { elements.removeValue(forKey: elementID) }

    private func read(_ element: AXUIElement, id: UUID, processID: Int32) throws -> SelectedTextState {
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == processID else {
            throw SelectedTextError.selectionChanged
        }
        let role = try stringAttribute(element, kAXRoleAttribute, maximumLength: 256)
        let subrole = try optionalStringAttribute(element, kAXSubroleAttribute)
        // Reject secure fields before requesting any text attributes.
        guard subrole != kAXSecureTextFieldSubrole else { throw SelectedTextError.secureField }
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            throw SelectedTextError.unsupportedField
        }
        let enabled = try optionalBoolAttribute(element, kAXEnabledAttribute) ?? true
        let canSetSelection = try isSettable(element, kAXSelectedTextAttribute)
        let editable = try canSetSelection || isSettable(element, kAXValueAttribute)
        guard enabled, editable else { throw SelectedTextError.readOnly }
        let range = try selectionRange(element)
        guard range.length > 0 else { throw SelectedTextError.noSelection }
        let text = try stringAttribute(element, kAXSelectedTextAttribute,
                                       maximumLength: SelectedTextValidation.maximumSelectionBytes)
        let value = try stringAttribute(element, kAXValueAttribute,
                                        maximumLength: SelectedTextValidation.maximumDocumentUTF16Length)
        let state = SelectedTextState(elementID: id, processID: processID, role: role, isSecure: false,
                                      isEnabled: enabled, isEditable: editable, canSetSelectedText: canSetSelection,
                                      text: text, range: range, value: value)
        try SelectedTextValidation.eligible(state)
        return state
    }

    private func configure(_ element: AXUIElement) throws {
        guard AXUIElementSetMessagingTimeout(element, timeout) == .success else {
            throw SelectedTextError.applicationUnavailable
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String, optional: Bool = false) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if optional, error == .attributeUnsupported || error == .noValue { return nil }
        guard error == .success else {
            if error == .apiDisabled { throw SelectedTextError.permissionRequired }
            if error == .cannotComplete || error == .invalidUIElement { throw SelectedTextError.applicationUnavailable }
            throw SelectedTextError.unsupportedField
        }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) throws -> AXUIElement {
        guard let value = try attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw SelectedTextError.unsupportedField
        }
        return value as! AXUIElement
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String, maximumLength: Int) throws -> String {
        guard let value = try attribute(element, name), CFGetTypeID(value) == CFStringGetTypeID() else {
            throw SelectedTextError.unsupportedField
        }
        let string = value as! CFString
        guard CFStringGetLength(string) <= maximumLength else { throw SelectedTextError.textTooLarge }
        return string as String
    }

    private func optionalStringAttribute(_ element: AXUIElement, _ name: String) throws -> String? {
        guard let value = try attribute(element, name, optional: true) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { throw SelectedTextError.unsupportedField }
        return value as? String
    }

    private func optionalBoolAttribute(_ element: AXUIElement, _ name: String) throws -> Bool? {
        guard let value = try attribute(element, name, optional: true) else { return nil }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { throw SelectedTextError.unsupportedField }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func isSettable(_ element: AXUIElement, _ name: String) throws -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        if error == .attributeUnsupported || error == .noValue { return false }
        guard error == .success else { throw SelectedTextError.applicationUnavailable }
        return settable.boolValue
    }

    private func selectionRange(_ element: AXUIElement) throws -> NSRange {
        guard let value = try attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { throw SelectedTextError.unsupportedField }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { throw SelectedTextError.unsupportedField }
        if let ranges = try attribute(element, kAXSelectedTextRangesAttribute, optional: true) {
            guard CFGetTypeID(ranges) == CFArrayGetTypeID(),
                  let values = ranges as? [AnyObject], values.count == 1,
                  CFGetTypeID(values[0]) == AXValueGetTypeID() else {
                throw SelectedTextError.unsupportedField
            }
            let selectedRange = values[0] as! AXValue
            var multipleRange = CFRange()
            guard AXValueGetType(selectedRange) == .cfRange,
                  AXValueGetValue(selectedRange, .cfRange, &multipleRange),
                  multipleRange.location == range.location, multipleRange.length == range.length else {
                throw SelectedTextError.unsupportedField
            }
        }
        return NSRange(location: range.location, length: range.length)
    }
}

enum SelectedTextPasteboard {
    static let marker = NSPasteboard.PasteboardType("com.yyhsiu.cue.selected-text-conversion")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let maximumBackupBytes = 16 * 1_024 * 1_024

    struct Backup: Sendable {
        let changeCount: Int
        let items: [[(NSPasteboard.PasteboardType, Data)]]
    }

    struct Ownership {
        let changeCount: Int
        let token: String
    }

    static func snapshot(_ board: NSPasteboard) throws -> Backup {
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny {
            throw SelectedTextError.clipboardUnavailable
        }
        let count = board.changeCount
        guard let items = board.pasteboardItems, items.count <= 32 else {
            throw SelectedTextError.clipboardUnavailable
        }
        var bytes = 0
        var backup: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in items {
            let types = item.types
            guard types.count <= 32 else { throw SelectedTextError.clipboardUnavailable }
            var representations: [(NSPasteboard.PasteboardType, Data)] = []
            for type in types {
                guard let data = item.data(forType: type), data.count <= maximumBackupBytes - bytes else {
                    throw SelectedTextError.clipboardUnavailable
                }
                bytes += data.count
                representations.append((type, data))
            }
            backup.append(representations)
        }
        guard board.changeCount == count else { throw SelectedTextError.clipboardUnavailable }
        return Backup(changeCount: count, items: backup)
    }

    static func install(_ text: String, on board: NSPasteboard, replacing backup: Backup) throws -> Ownership {
        guard board.changeCount == backup.changeCount else { throw SelectedTextError.clipboardUnavailable }
        let token = UUID().uuidString
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string), item.setString(token, forType: marker),
              item.setData(Data(), forType: transient) else { throw SelectedTextError.clipboardUnavailable }
        let clearCount = board.clearContents()
        guard board.writeObjects([item]) else {
            // Failed publication still owns the just-cleared board; restore only if
            // another app has not taken ownership in the meantime.
            if board.changeCount == clearCount { restoreItems(backup.items, on: board) }
            throw SelectedTextError.clipboardUnavailable
        }
        return Ownership(changeCount: board.changeCount, token: token)
    }

    static func stillOwns(_ board: NSPasteboard, _ ownership: Ownership) -> Bool {
        board.changeCount == ownership.changeCount && board.string(forType: marker) == ownership.token
    }

    static func restore(_ backup: Backup, on board: NSPasteboard, ifOwned ownership: Ownership) {
        guard stillOwns(board, ownership) else { return }
        restoreItems(backup.items, on: board)
    }

    private static func restoreItems(_ representations: [[(NSPasteboard.PasteboardType, Data)]], on board: NSPasteboard) {
        let items = representations.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
    }
}

/// Pasteboard providers may block while producing promised data. Read on a utility
/// queue and abandon the request before mutation when it exceeds the budget. At
/// most one provider request is active per service, including after a timeout;
/// repeated commands cannot accumulate an unbounded number of blocked workers.
private final class SelectedTextBackupReader: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.yyhsiu.cue.selected-text-clipboard", qos: .utility)
    private var isReading = false

    func snapshot(name: NSPasteboard.Name) async throws -> SelectedTextPasteboard.Backup {
        let request = ReadRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation) else { return }
                guard lock.withLock({
                    if isReading { return false }
                    isReading = true
                    return true
                }) else {
                    request.finish(.failure(SelectedTextError.clipboardUnavailable))
                    return
                }
                queue.async { [self] in
                    let result = Result {
                        try autoreleasepool { try SelectedTextPasteboard.snapshot(NSPasteboard(name: name)) }
                    }
                    lock.withLock { isReading = false }
                    request.finish(result)
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(750)) {
                    request.finish(.failure(SelectedTextError.clipboardUnavailable))
                }
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
        }
    }

    private final class ReadRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<SelectedTextPasteboard.Backup, any Error>?
        private var finished = false
        private var earlyResult: Result<SelectedTextPasteboard.Backup, any Error>?

        func install(_ continuation: CheckedContinuation<SelectedTextPasteboard.Backup, any Error>) -> Bool {
            lock.lock()
            if let earlyResult {
                self.earlyResult = nil
                lock.unlock()
                continuation.resume(with: earlyResult)
                return false
            }
            self.continuation = continuation
            lock.unlock()
            return true
        }

        func finish(_ result: Result<SelectedTextPasteboard.Backup, any Error>) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            if continuation == nil { earlyResult = result }
            lock.unlock()
            continuation?.resume(with: result)
        }
    }
}
