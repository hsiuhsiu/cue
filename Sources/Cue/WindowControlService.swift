import AppKit
import ApplicationServices
import CueCore

enum WindowControlError: Error, Equatable, Sendable {
    case permissionRequired, noTarget, unsupportedWindow, minimized, fullScreen
    case readOnly, cannotResize, applicationUnavailable, sessionExpired, noScreen
    case noAdjacentScreen, nothingToRestore, invalidPreset, timedOut, operationFailed, unverified
}

enum WindowControlNotice: Equatable, Sendable {
    case constrained, partialSuccess, restoreAdjusted
}

struct WindowControlSnapshot: Equatable, Sendable {
    let processIdentifier: Int32
    let frame: CGRect
    let screen: WindowScreen
    let canMove: Bool
    let canResize: Bool
    let notice: WindowControlNotice?
}

protocol WindowControlling: Sendable {
    func capture(processIdentifier: Int32, screens: [WindowScreen], sessionID: UUID) async throws -> WindowControlSnapshot
    func apply(_ action: WindowAction, screens: [WindowScreen], sessionID: UUID) async throws -> WindowControlSnapshot
    func cancel(sessionID: UUID)
}

struct WindowControlState: Equatable, Sendable {
    let elementID: UUID
    let processIdentifier: Int32
    let frame: CGRect
    let canMove: Bool
    let canResize: Bool
}

/// A driver checks before each IPC, so cancellation stops subsequent setters even
/// while an earlier non-cancellable AX call is finishing on the service actor.
struct WindowControlRequest: Sendable {
    let deadline: ContinuousClock.Instant
    let isCancelled: @Sendable () -> Bool

    func check() throws {
        try Task.checkCancellation()
        guard !isCancelled() else { throw CancellationError() }
        guard ContinuousClock.now < deadline else { throw WindowControlError.timedOut }
    }
}

protocol WindowControlDriver: Sendable {
    func isTrusted() -> Bool
    func capture(processIdentifier: Int32, request: WindowControlRequest) throws -> WindowControlState
    func read(_ expected: WindowControlState, request: WindowControlRequest) throws -> WindowControlState
    func setPosition(_ position: CGPoint, for expected: WindowControlState, request: WindowControlRequest) throws
    func setSize(_ size: CGSize, for expected: WindowControlState, request: WindowControlRequest) throws
    func release(_ elementID: UUID)
}

/// No AX work is performed on construction or on Cue's ordinary search path.
/// Actor methods have no suspension between validation, writes, and readback.
actor WindowControlService: WindowControlling {
    private let driver: any WindowControlDriver
    private nonisolated let cancellation = WindowControlCancellation()
    private var pending: (id: UUID, state: WindowControlState)?
    private struct History {
        let before: CGRect
        let beforeScreen: WindowScreen
        let after: CGRect
        let afterScreen: WindowScreen
    }
    private var history: [UUID: History] = [:]
    private var recent: [UUID] = []
    private let maximumHistory = 50

    init(driver: any WindowControlDriver = AXWindowControlDriver()) { self.driver = driver }

    nonisolated func cancel(sessionID: UUID) {
        cancellation.cancel(sessionID)
        // Invalidating the token is immediate; releasing references can wait for
        // the bounded in-flight IPC without blocking the caller or keyboard.
        Task { await self.clearSession(sessionID) }
    }

    func capture(processIdentifier: Int32, screens: [WindowScreen], sessionID: UUID) throws -> WindowControlSnapshot {
        let request = request(for: sessionID)
        try request.check()
        if let old = pending { releaseIfUnused(old.state.elementID); pending = nil }
        guard processIdentifier > 0, processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw WindowControlError.noTarget
        }
        guard driver.isTrusted() else { clearAll(); throw WindowControlError.permissionRequired }
        guard !WindowGeometry.screens(screens).isEmpty else { throw WindowControlError.noScreen }
        let state = try driver.capture(processIdentifier: processIdentifier, request: request)
        do {
            try request.check()
            guard state.processIdentifier == processIdentifier, WindowGeometry.isUsable(state.frame) else {
                throw WindowControlError.unsupportedWindow
            }
            let result = try snapshot(state, screens: screens)
            pending = (sessionID, state)
            return result
        } catch {
            releaseIfUnused(state.elementID)
            throw error
        }
    }

    func apply(_ action: WindowAction, screens: [WindowScreen], sessionID: UUID) throws -> WindowControlSnapshot {
        let request = request(for: sessionID)
        try request.check()
        guard let session = pending, session.id == sessionID else { throw WindowControlError.sessionExpired }
        guard driver.isTrusted() else { clearAll(); throw WindowControlError.permissionRequired }
        let before: WindowControlState
        do { before = try driver.read(session.state, request: request) }
        catch {
            if error is CancellationError { throw error }
            forget(session.state.elementID)
            pending = nil
            throw error
        }
        guard before.elementID == session.state.elementID,
              before.processIdentifier == session.state.processIdentifier else {
            forget(session.state.elementID); pending = nil
            throw WindowControlError.applicationUnavailable
        }
        guard let source = WindowGeometry.currentScreen(for: before.frame, screens: screens) else {
            throw WindowControlError.noScreen
        }
        var destination = source
        var notice: WindowControlNotice?
        let target: CGRect
        switch action {
        case .half(let direction): target = WindowGeometry.half(direction, on: source)
        case .fill: target = source.visibleFrame
        case .center: target = WindowGeometry.centered(before.frame, on: source)
        case .move(let direction):
            guard let next = WindowGeometry.adjacentScreen(from: source, direction: direction, screens: screens) else {
                throw WindowControlError.noAdjacentScreen
            }
            destination = next
            target = WindowGeometry.moved(before.frame, from: source, to: next, resize: before.canResize)
        case .preset(let preset):
            guard let frame = WindowGeometry.frame(for: preset, on: source) else { throw WindowControlError.invalidPreset }
            target = frame
        case .restore:
            guard let saved = history[before.elementID], WindowGeometry.approximatelyEqual(before.frame, saved.after) else {
                forgetHistory(before.elementID)
                throw WindowControlError.nothingToRestore
            }
            if let original = WindowGeometry.screens(screens).first(where: { $0.id == saved.beforeScreen.id }) {
                destination = original
                if original == saved.beforeScreen { target = saved.before }
                else {
                    target = WindowGeometry.moved(saved.before, from: saved.beforeScreen, to: original, resize: before.canResize)
                    notice = .restoreAdjusted
                }
            } else {
                target = WindowGeometry.moved(saved.before, from: saved.beforeScreen, to: source, resize: before.canResize)
                notice = .restoreAdjusted
            }
        }
        guard WindowGeometry.isUsable(target) else { throw WindowControlError.unsupportedWindow }
        guard before.canMove else { throw WindowControlError.readOnly }
        let changesSize = abs(before.frame.width - target.width) > 1 || abs(before.frame.height - target.height) > 1
        guard !changesSize || before.canResize else { throw WindowControlError.cannotResize }
        if WindowGeometry.approximatelyEqual(before.frame, target, tolerance: 1) {
            pending = (sessionID, before)
            return try snapshot(before, screens: screens, notice: notice)
        }

        var setterFailed = false
        do {
            if changesSize { try driver.setSize(target.size, for: before, request: request) }
            try request.check()
            try driver.setPosition(target.origin, for: before, request: request)
        } catch is CancellationError { throw CancellationError() }
        catch WindowControlError.permissionRequired { clearAll(); throw WindowControlError.permissionRequired }
        catch { setterFailed = true }
        // A failing setter can still have changed the window. Always read back;
        // never claim success or create a restore record from an assumed frame.
        let after: WindowControlState
        do {
            try request.check()
            after = try driver.read(before, request: request)
            try request.check()
            guard after.elementID == before.elementID, after.processIdentifier == before.processIdentifier,
                  WindowGeometry.isUsable(after.frame) else { throw WindowControlError.unverified }
        } catch is CancellationError { throw CancellationError() }
        catch {
            forget(before.elementID); pending = nil
            throw WindowControlError.unverified
        }
        pending = (sessionID, after)
        let changed = !WindowGeometry.approximatelyEqual(before.frame, after.frame, tolerance: 0.5)
        if changed {
            remember(before: before, on: source, after: after,
                     on: WindowGeometry.currentScreen(for: after.frame, screens: screens) ?? destination)
        }
        if setterFailed {
            guard changed else { throw WindowControlError.operationFailed }
            notice = .partialSuccess
        } else if !WindowGeometry.approximatelyEqual(after.frame, target) { notice = .constrained }
        return try snapshot(after, screens: screens, notice: notice)
    }

    private func request(for sessionID: UUID) -> WindowControlRequest {
        WindowControlRequest(deadline: .now.advanced(by: .milliseconds(900)),
                             isCancelled: { [cancellation] in cancellation.contains(sessionID) })
    }

    private func snapshot(_ state: WindowControlState, screens: [WindowScreen],
                          notice: WindowControlNotice? = nil) throws -> WindowControlSnapshot {
        guard let screen = WindowGeometry.currentScreen(for: state.frame, screens: screens) else {
            throw WindowControlError.noScreen
        }
        return WindowControlSnapshot(processIdentifier: state.processIdentifier, frame: state.frame,
                                     screen: screen, canMove: state.canMove, canResize: state.canResize, notice: notice)
    }

    private func remember(before: WindowControlState, on source: WindowScreen,
                          after: WindowControlState, on destination: WindowScreen) {
        history[before.elementID] = History(before: before.frame, beforeScreen: source,
                                            after: after.frame, afterScreen: destination)
        recent.removeAll { $0 == before.elementID }
        recent.append(before.elementID)
        while recent.count > maximumHistory { forget(recent[0]) }
    }

    private func forgetHistory(_ id: UUID) { history[id] = nil; recent.removeAll { $0 == id } }
    private func forget(_ id: UUID) { forgetHistory(id); driver.release(id) }
    private func releaseIfUnused(_ id: UUID) { if history[id] == nil { driver.release(id) } }
    private func clearSession(_ id: UUID) {
        guard pending?.id == id else { return }
        if let pending { releaseIfUnused(pending.state.elementID) }
        pending = nil
    }
    private func clearAll() {
        for id in Set(recent + (pending.map { [$0.state.elementID] } ?? [])) { driver.release(id) }
        history.removeAll(); recent.removeAll(); pending = nil
    }
}

private final class WindowControlCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []
    func cancel(_ id: UUID) {
        lock.withLock {
            if !ids.contains(id) { ids.append(id) }
            // The controller bounds its command queue; retain far more cancelled
            // sessions than can be pending without allowing unbounded memory.
            if ids.count > 128 { ids.removeFirst(ids.count - 128) }
        }
    }
    func contains(_ id: UUID) -> Bool { lock.withLock { ids.contains(id) } }
}

/// AX references are exclusively used by WindowControlService's actor. UUIDs are
/// transient handles, keyed by both the process launch identity and CFEqual AX
/// element identity. Window/document titles are never read or persisted.
final class AXWindowControlDriver: WindowControlDriver, @unchecked Sendable {
    private struct Handle {
        let element: AXUIElement
        let processIdentifier: Int32
        let launched: Date
    }
    private var handles: [UUID: Handle] = [:]
    private let timeout: Float = 0.12

    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func capture(processIdentifier: Int32, request: WindowControlRequest) throws -> WindowControlState {
        try request.check()
        guard let process = NSRunningApplication(processIdentifier: processIdentifier), !process.isTerminated,
              let launched = process.launchDate else { throw WindowControlError.applicationUnavailable }
        // No polling. Release dead process identities when the user next invokes.
        handles = handles.filter { _, handle in
            guard let app = NSRunningApplication(processIdentifier: handle.processIdentifier) else { return false }
            return !app.isTerminated && app.launchDate == handle.launched
        }
        let app = AXUIElementCreateApplication(processIdentifier)
        try configure(app, request: request)
        guard let value = try attribute(app, kAXFocusedWindowAttribute, request: request),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { throw WindowControlError.noTarget }
        let element = value as! AXUIElement
        try configure(element, request: request)
        let id = handles.first { _, handle in
            handle.processIdentifier == processIdentifier && handle.launched == launched && CFEqual(handle.element, element)
        }?.key ?? UUID()
        let wasKnown = handles[id] != nil
        handles[id] = Handle(element: element, processIdentifier: processIdentifier, launched: launched)
        do { return try readHandle(id, request: request) }
        catch { if !wasKnown { handles[id] = nil }; throw error }
    }

    func read(_ expected: WindowControlState, request: WindowControlRequest) throws -> WindowControlState {
        try readHandle(expected.elementID, request: request)
    }

    func setPosition(_ position: CGPoint, for expected: WindowControlState, request: WindowControlRequest) throws {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { throw WindowControlError.operationFailed }
        try set(value, attribute: kAXPositionAttribute, for: expected, request: request)
    }

    func setSize(_ size: CGSize, for expected: WindowControlState, request: WindowControlRequest) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw WindowControlError.operationFailed }
        try set(value, attribute: kAXSizeAttribute, for: expected, request: request)
    }

    func release(_ elementID: UUID) { handles[elementID] = nil }

    private func readHandle(_ id: UUID, request: WindowControlRequest) throws -> WindowControlState {
        let handle = try validatedHandle(id, request: request)
        let element = handle.element
        guard try attribute(element, kAXRoleAttribute, request: request) as? String == kAXWindowRole,
              try attribute(element, kAXSubroleAttribute, optional: true, request: request) as? String == kAXStandardWindowSubrole else {
            throw WindowControlError.unsupportedWindow
        }
        if try boolAttribute(element, kAXMinimizedAttribute, request: request) { throw WindowControlError.minimized }
        if try boolAttribute(element, "AXFullScreen", request: request) { throw WindowControlError.fullScreen }
        if let sheets = try attribute(element, "AXSheets", optional: true, request: request) as? [AXUIElement], !sheets.isEmpty {
            throw WindowControlError.unsupportedWindow
        }
        guard let position = try attribute(element, kAXPositionAttribute, request: request),
              let size = try attribute(element, kAXSizeAttribute, request: request),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw WindowControlError.unsupportedWindow
        }
        let axPosition = position as! AXValue, axSize = size as! AXValue
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetType(axPosition) == .cgPoint, AXValueGetType(axSize) == .cgSize,
              AXValueGetValue(axPosition, .cgPoint, &origin), AXValueGetValue(axSize, .cgSize, &dimensions),
              WindowGeometry.isUsable(CGRect(origin: origin, size: dimensions)) else { throw WindowControlError.unsupportedWindow }
        let movable = try isSettable(element, kAXPositionAttribute, request: request)
        let resizable = try isSettable(element, kAXSizeAttribute, request: request)
        return WindowControlState(elementID: id, processIdentifier: handle.processIdentifier,
                                  frame: CGRect(origin: origin, size: dimensions), canMove: movable, canResize: resizable)
    }

    private func validatedHandle(_ id: UUID, request: WindowControlRequest) throws -> Handle {
        try request.check()
        guard let handle = handles[id],
              let app = NSRunningApplication(processIdentifier: handle.processIdentifier), !app.isTerminated,
              app.launchDate == handle.launched else {
            handles[id] = nil
            throw WindowControlError.applicationUnavailable
        }
        return handle
    }

    private func configure(_ element: AXUIElement, request: WindowControlRequest) throws {
        try request.check()
        try check(AXUIElementSetMessagingTimeout(element, timeout))
    }

    private func attribute(_ element: AXUIElement, _ name: String, optional: Bool = false,
                           request: WindowControlRequest) throws -> CFTypeRef? {
        try request.check()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if optional, error == .attributeUnsupported || error == .noValue { return nil }
        try check(error)
        return value
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String, request: WindowControlRequest) throws -> Bool {
        guard let value = try attribute(element, name, optional: true, request: request) else { return false }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { throw WindowControlError.unsupportedWindow }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func isSettable(_ element: AXUIElement, _ name: String, request: WindowControlRequest) throws -> Bool {
        try request.check()
        var result = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, name as CFString, &result)
        if error == .attributeUnsupported || error == .noValue { return false }
        try check(error)
        return result.boolValue
    }

    private func set(_ value: AXValue, attribute: String, for expected: WindowControlState,
                     request: WindowControlRequest) throws {
        let handle = try validatedHandle(expected.elementID, request: request)
        guard isTrusted() else { throw WindowControlError.permissionRequired }
        try request.check()
        try check(AXUIElementSetAttributeValue(handle.element, attribute as CFString, value))
    }

    private func check(_ error: AXError) throws {
        switch error {
        case .success: return
        case .apiDisabled: throw WindowControlError.permissionRequired
        case .cannotComplete: throw WindowControlError.timedOut
        case .invalidUIElement: throw WindowControlError.applicationUnavailable
        case .attributeUnsupported, .noValue: throw WindowControlError.unsupportedWindow
        default: throw WindowControlError.operationFailed
        }
    }
}
