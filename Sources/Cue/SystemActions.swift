import AppKit
import Darwin
import IOKit.pwr_mgt

enum SystemAction: Sendable {
    case sleep
    case lockScreen
    case screenOff
}

enum SystemActionError: Error {
    case sleepUnavailable
    case sleepFailed(IOReturn)
    case lockUnavailable
    case screenOffUnavailable
    case screenOffFailed(Int32)
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
        case .screenOff:
            try await ScreenOffService.perform()
        }
    }
}

/// pmset's documented one-shot display-sleep request changes no power settings.
/// It does not request system sleep or lock the session. Only execution creates
/// a process; launching, typing, and ranking never touch this service.
enum ScreenOffService {
    static func perform(
        runProcess: @escaping @Sendable (URL, [String]) throws -> Int32 = execute
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let status: Int32
            do {
                status = try runProcess(URL(fileURLWithPath: "/usr/bin/pmset"), ["displaysleepnow"])
            } catch {
                throw SystemActionError.screenOffUnavailable
            }
            guard status == 0 else { throw SystemActionError.screenOffFailed(status) }
        }.value
    }

    private static func execute(_ executable: URL, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
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
