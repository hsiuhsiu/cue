import AppKit
import Darwin
import IOKit.pwr_mgt

enum SystemAction: Sendable {
    case sleep
    case lockScreen
}

enum SystemActionError: Error {
    case sleepUnavailable
    case sleepFailed(IOReturn)
    case lockUnavailable
}

enum SystemActions {
    // Resolve the service only on first execution, never while searching. Keep the
    // library loaded for the app lifetime, including any work scheduled by macOS.
    private static let lockService = Result { try LockScreenService() }

    @MainActor
    static func perform(_ action: SystemAction) async throws {
        switch action {
        case .sleep:
            try await Task.detached(priority: .userInitiated) {
                let connection = IOPMFindPowerManagement(0)
                guard connection != 0 else { throw SystemActionError.sleepUnavailable }
                defer { IOServiceClose(connection) }
                let result = IOPMSleepSystem(connection)
                guard result == kIOReturnSuccess else { throw SystemActionError.sleepFailed(result) }
            }.value
        case .lockScreen:
            let service = try await Task.detached(priority: .userInitiated) {
                try lockService.get()
            }.value
            service.lock()
        }
    }
}

/// macOS has no public, permission-free lock-screen API. Keep the dynamically
/// resolved login service isolated and fail explicitly if it is unavailable.
/// Do not substitute display sleep: that need not lock the user's session.
/// The immutable handle can cross executors; invocation is main-actor-only.
final class LockScreenService: @unchecked Sendable {
    private typealias LockFunction = @convention(c) () -> Void
    private let handle: UnsafeMutableRawPointer
    private let function: LockFunction

    init() throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY | RTLD_LOCAL)
        else { throw SystemActionError.lockUnavailable }
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            dlclose(handle)
            throw SystemActionError.lockUnavailable
        }
        self.handle = handle
        function = unsafeBitCast(symbol, to: LockFunction.self)
    }

    @MainActor
    func lock() { function() }

    deinit { dlclose(handle) }
}
