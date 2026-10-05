import AppKit
import CueCore

/// Every geometry/identity is synthetic. This executable never creates AX
/// elements, enumerates real windows, accesses preferences, or activates an app.
private final class StubWindowDriver: WindowControlDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var state: WindowControlState
    private var trusted = true
    private var counts = (captures: 0, reads: 0, positions: 0, sizes: 0, releases: 0)
    private var released: Set<UUID> = []
    private var failedPosition = false
    private var failedReadsAfterWrite = false
    private var minimumSize: CGSize?
    private var onSize: (@Sendable () -> Void)?
    private var recordedMainThread = false

    init(state: WindowControlState) { self.state = state }
    func isTrusted() -> Bool { lock.withLock { trusted } }
    func capture(processIdentifier: Int32, request: WindowControlRequest) throws -> WindowControlState {
        try request.check()
        return lock.withLock { recordThread(); counts.captures += 1; return state }
    }
    func read(_ expected: WindowControlState, request: WindowControlRequest) throws -> WindowControlState {
        try request.check()
        return try lock.withLock {
            recordThread(); counts.reads += 1
            if failedReadsAfterWrite, counts.positions + counts.sizes > 0 { throw WindowControlError.timedOut }
            guard expected.elementID == state.elementID else { throw WindowControlError.applicationUnavailable }
            return state
        }
    }
    func setPosition(_ position: CGPoint, for expected: WindowControlState, request: WindowControlRequest) throws {
        try request.check()
        try lock.withLock {
            recordThread(); counts.positions += 1
            if failedPosition { throw WindowControlError.operationFailed }
            state = copy(frame: CGRect(origin: position, size: state.frame.size))
        }
    }
    func setSize(_ size: CGSize, for expected: WindowControlState, request: WindowControlRequest) throws {
        try request.check()
        let hook = lock.withLock {
            recordThread(); counts.sizes += 1
            let actual = CGSize(width: max(size.width, minimumSize?.width ?? 0),
                                height: max(size.height, minimumSize?.height ?? 0))
            state = copy(frame: CGRect(origin: state.frame.origin, size: actual))
            return onSize
        }
        hook?()
    }
    func release(_ elementID: UUID) { lock.withLock { counts.releases += 1; released.insert(elementID) } }
    func current() -> WindowControlState { lock.withLock { state } }
    func setState(_ value: WindowControlState) { lock.withLock { state = value } }
    func setTrusted(_ value: Bool) { lock.withLock { trusted = value } }
    func setMinimum(_ value: CGSize) { lock.withLock { minimumSize = value } }
    func failPosition(_ value: Bool) { lock.withLock { failedPosition = value } }
    func failReadback() { lock.withLock { failedReadsAfterWrite = true } }
    func afterSize(_ value: @escaping @Sendable () -> Void) { lock.withLock { onSize = value } }
    func writeCount() -> Int { lock.withLock { counts.positions + counts.sizes } }
    func positionCount() -> Int { lock.withLock { counts.positions } }
    func releaseCount() -> Int { lock.withLock { counts.releases } }
    func readCount() -> Int { lock.withLock { counts.reads } }
    func calledOnMain() -> Bool { lock.withLock { recordedMainThread } }
    private func recordThread() { recordedMainThread = recordedMainThread || Thread.isMainThread }
    private func copy(frame: CGRect) -> WindowControlState {
        WindowControlState(elementID: state.elementID, processIdentifier: state.processIdentifier,
                           frame: frame, canMove: state.canMove, canResize: state.canResize)
    }
}

@main
struct CheckWindowService {
    @MainActor private static var checks = 0
    private static let process: Int32 = 424_242
    private static let area = CGRect(x: 0, y: 24, width: 1200, height: 800)
    private static let original = CGRect(x: 100, y: 100, width: 650, height: 500)
    private static let screen = WindowScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1200, height: 900), visibleFrame: area)

    @MainActor private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    private static func state(id: UUID = UUID(), frame: CGRect = original,
                              movable: Bool = true, resizable: Bool = true) -> WindowControlState {
        WindowControlState(elementID: id, processIdentifier: process, frame: frame, canMove: movable, canResize: resizable)
    }

    @MainActor private static func expect(_ error: WindowControlError, _ action: () async throws -> Void) async {
        do { try await action(); check(false, "Expected \(error)") }
        catch let actual as WindowControlError { check(actual == error, "Expected \(error), received \(actual)") }
        catch { check(false, "Unexpected error \(type(of: error))") }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            let stub = StubWindowDriver(state: state()), service = WindowControlService(driver: StubWindowDriver(state: state()))
            // Construction is inert, and invalid self/empty targets do not contact AX.
            check(stub.readCount() == 0 && stub.writeCount() == 0, "No construction work")
            await expect(.noTarget) { _ = try await service.capture(processIdentifier: ProcessInfo.processInfo.processIdentifier, screens: [screen], sessionID: UUID()) }
            stub.setTrusted(false)
            let denied = WindowControlService(driver: stub)
            await expect(.permissionRequired) { _ = try await denied.capture(processIdentifier: process, screens: [screen], sessionID: UUID()) }
            check(stub.writeCount() == 0, "Permission denial never writes")
        }
        do {
            let stub = StubWindowDriver(state: state()), serviceID = UUID()
            let service = WindowControlService(driver: stub)
            let capture = try await service.capture(processIdentifier: process, screens: [screen], sessionID: serviceID)
            check(capture.frame == original, "Original frame captured")
            let half = try await service.apply(.half(.right), screens: [screen], sessionID: serviceID)
            check(half.frame == CGRect(x: 600, y: 24, width: 600, height: 800), "Right half applied")
            let writes = stub.writeCount()
            _ = try await service.apply(.half(.right), screens: [screen], sessionID: serviceID)
            check(stub.writeCount() == writes, "No-op does not write")
            let restored = try await service.apply(.restore, screens: [screen], sessionID: serviceID)
            check(restored.frame == original, "No-op did not overwrite restore")
            let toggled = try await service.apply(.restore, screens: [screen], sessionID: serviceID)
            check(toggled.frame == half.frame, "Repeated restore toggles confirmed state")
            check(!stub.calledOnMain(), "Driver reads and writes stay off main thread")
            service.cancel(sessionID: serviceID)
            let nextID = UUID()
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: nextID)
            let acrossSessions = try await service.apply(.restore, screens: [screen], sessionID: nextID)
            check(acrossSessions.frame == original, "Restore survives closing and reopening same window")
        }
        do {
            let stub = StubWindowDriver(state: state()), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            _ = try await service.apply(.fill, screens: [screen], sessionID: session)
            stub.setState(state(id: stub.current().elementID, frame: CGRect(x: 15, y: 25, width: 1100, height: 600)))
            let writes = stub.writeCount()
            await expect(.nothingToRestore) { _ = try await service.apply(.restore, screens: [screen], sessionID: session) }
            check(stub.writeCount() == writes, "External edits invalidate stale restore")
        }
        do {
            let stub = StubWindowDriver(state: state(resizable: false)), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            await expect(.cannotResize) { _ = try await service.apply(.fill, screens: [screen], sessionID: session) }
            check(stub.writeCount() == 0, "Fixed window is not partially moved by resize command")
            let centered = try await service.apply(.center, screens: [screen], sessionID: session)
            check(centered.frame.size == original.size, "Fixed windows can be centered")
            check(centered.frame.midX == area.midX && centered.frame.midY == area.midY, "Center uses usable area")
        }
        do {
            let stub = StubWindowDriver(state: state(movable: false)), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            await expect(.readOnly) { _ = try await service.apply(.center, screens: [screen], sessionID: session) }
            check(stub.writeCount() == 0, "Read-only window never writes")
        }
        do {
            let stub = StubWindowDriver(state: state()), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            stub.setMinimum(CGSize(width: 800, height: 600))
            let result = try await service.apply(.half(.left), screens: [screen], sessionID: session)
            check(result.notice == .constrained && result.frame.width == 800, "Minimum size is read back honestly")
            check(stub.writeCount() == 2, "Constrained size has no unbounded retries")
        }
        do {
            let stub = StubWindowDriver(state: state()), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            stub.failPosition(true)
            let partial = try await service.apply(.fill, screens: [screen], sessionID: session)
            check(partial.notice == .partialSuccess && partial.frame.origin == original.origin, "Partial resize success is explicit")
            stub.failPosition(false)
            let restored = try await service.apply(.restore, screens: [screen], sessionID: session)
            check(restored.frame == original, "Partial success remains restorable")
        }
        do {
            let stub = StubWindowDriver(state: state()), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            stub.failReadback()
            await expect(.unverified) { _ = try await service.apply(.fill, screens: [screen], sessionID: session) }
            check(stub.writeCount() == 2, "Unverified write never retries")
        }
        do {
            let stub = StubWindowDriver(state: state()), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            stub.afterSize { service.cancel(sessionID: session) }
            do { _ = try await service.apply(.fill, screens: [screen], sessionID: session); check(false, "Expected cancellation") }
            catch is CancellationError { check(true, "Cancellation observed during setter") }
            check(stub.positionCount() == 0, "Cancel prevents next setter")
            do { _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session); check(false, "Cancelled session revived") }
            catch is CancellationError { check(true, "Cancelled session cannot revive") }
        }
        do {
            let stub = StubWindowDriver(state: state()), session = UUID()
            let service = WindowControlService(driver: stub)
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            stub.setState(state())
            await expect(.applicationUnavailable) { _ = try await service.apply(.fill, screens: [screen], sessionID: session) }
            check(stub.writeCount() == 0, "Replaced or closed target cannot receive writes")
        }
        do {
            let stub = StubWindowDriver(state: state()), session = UUID()
            let service = WindowControlService(driver: stub)
            let rightFrame = CGRect(x: 1500, y: -200, width: 1000, height: 800)
            let right = WindowScreen(id: 2, frame: rightFrame, visibleFrame: rightFrame)
            _ = try await service.capture(processIdentifier: process, screens: [screen, right], sessionID: session)
            await expect(.noAdjacentScreen) { _ = try await service.apply(.move(.left), screens: [screen, right], sessionID: session) }
            let moved = try await service.apply(.move(.right), screens: [screen, right], sessionID: session)
            check(moved.screen.id == 2 && moved.frame.size == original.size, "Cross-display retains points")
            let adjusted = try await service.apply(.restore, screens: [right], sessionID: session)
            check(adjusted.notice == .restoreAdjusted && right.visibleFrame.contains(adjusted.frame), "Unplugged restore maps onto surviving screen")
        }
        do {
            let initial = state(), stub = StubWindowDriver(state: state())
            let service = WindowControlService(driver: stub)
            for index in 0..<55 {
                stub.setState(index == 0 ? initial : state())
                let session = UUID()
                _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
                _ = try await service.apply(.fill, screens: [screen], sessionID: session)
                service.cancel(sessionID: session)
            }
            check(stub.releaseCount() >= 5, "Restore handles are bounded to 50 windows")
            stub.setState(WindowControlState(elementID: initial.elementID, processIdentifier: process, frame: area, canMove: true, canResize: true))
            let session = UUID()
            _ = try await service.capture(processIdentifier: process, screens: [screen], sessionID: session)
            await expect(.nothingToRestore) { _ = try await service.apply(.restore, screens: [screen], sessionID: session) }
        }
        do {
            let expired = WindowControlRequest(deadline: .now.advanced(by: .seconds(-1)), isCancelled: { false })
            do { try expired.check(); check(false, "Expired request passed") }
            catch { check(error as? WindowControlError == .timedOut, "Deadline checked before IPC") }
        }
        print("Window service checks passed (\(checks)); synthetic targets only, no desktop activation or AX calls.")
    }
}
