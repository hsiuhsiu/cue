import Foundation

private enum StubFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Test service denied the operation." }
}

/// No live SMAppService is constructed or mutated by this harness.
private actor StubLoginItemService: LoginItemService {
    private var currentStatus: LoginItemStatus = .notRegistered
    private var nextStatus: LoginItemStatus?
    private var shouldFail = false
    private var suspendMutation = false
    private var suspendedMutation: CheckedContinuation<Void, Never>?
    private(set) var reads = 0
    private(set) var enables = 0
    private(set) var disables = 0

    func status() -> LoginItemStatus {
        reads += 1
        return currentStatus
    }

    func setEnabled(_ enabled: Bool) async throws {
        if enabled { enables += 1 } else { disables += 1 }
        if suspendMutation {
            await withCheckedContinuation { suspendedMutation = $0 }
        }
        if let nextStatus { currentStatus = nextStatus }
        else if !shouldFail { currentStatus = enabled ? .enabled : .notRegistered }
        if shouldFail { throw StubFailure.denied }
    }

    func configure(status: LoginItemStatus, nextStatus: LoginItemStatus? = nil,
                   shouldFail: Bool = false, suspendMutation: Bool = false) {
        currentStatus = status
        self.nextStatus = nextStatus
        self.shouldFail = shouldFail
        self.suspendMutation = suspendMutation
    }

    func isSuspended() -> Bool { suspendedMutation != nil }
    func resume() {
        suspendedMutation?.resume()
        suspendedMutation = nil
    }

    func counts() -> (reads: Int, enables: Int, disables: Int) { (reads, enables, disables) }
}

@main
struct CheckLoginItem {
    @MainActor private static var checks = 0

    @MainActor
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    @MainActor
    static func main() async {
        let service = StubLoginItemService()
        let controller = LoginItemController(service: service)
        check(!controller.hasLoaded && !controller.isSelected && !controller.isBusy,
              "Initial UI must be unloaded and off")
        var counts = await service.counts()
        check(counts.reads == 0 && counts.enables == 0 && counts.disables == 0,
              "Initialization must not query or register a service")
        await controller.setEnabled(true)
        counts = await service.counts()
        check(counts.enables == 0, "Ignore edits until the OS's initial status is known")

        await controller.refresh()
        check(controller.hasLoaded && !controller.isSelected && !controller.isBusy,
              "Fresh install starts off without registration")
        counts = await service.counts()
        check(counts.reads == 1 && counts.enables == 0 && counts.disables == 0,
              "Refresh is read-only")
        await controller.setEnabled(true)
        check(controller.status == .enabled && controller.isSelected && !controller.isBusy,
              "Successful registration reflects OS enabled status")
        await controller.setEnabled(true)
        counts = await service.counts()
        check(counts.enables == 1, "Repeated selection must not register twice")
        await controller.setEnabled(false)
        check(controller.status == .notRegistered && !controller.isSelected,
              "Unregister switches off without terminating the app")
        await controller.setEnabled(false)
        counts = await service.counts()
        check(counts.disables == 1, "Repeated deselection must not unregister twice")

        await service.configure(status: .notRegistered, nextStatus: .requiresApproval)
        await controller.setEnabled(true)
        check(controller.status == .requiresApproval && controller.isSelected,
              "Successful registration awaiting approval must not claim enabled status")
        counts = await service.counts()
        let registrationsBeforeRefresh = counts.enables
        await controller.refresh()
        counts = await service.counts()
        check(counts.enables == registrationsBeforeRefresh,
              "Pending or revoked approval must never be silently re-enabled")
        await service.configure(status: .requiresApproval)
        await controller.setEnabled(false)
        check(controller.status == .notRegistered, "Pending registration can be cancelled")

        await service.configure(status: .enabled)
        await controller.refresh()
        check(controller.isSelected, "Existing OS registration is reflected without a saved preference")
        await service.configure(status: .requiresApproval)
        await controller.refresh()
        check(controller.status == .requiresApproval,
              "Revocation in System Settings is reflected on the next refresh")
        await service.configure(status: .notRegistered)
        await controller.refresh()
        check(!controller.isSelected, "External removal is reflected on the next refresh")

        await service.configure(status: .notRegistered, shouldFail: true)
        await controller.setEnabled(true)
        check(controller.status == .notRegistered && !controller.isSelected && !controller.isBusy,
              "Failed registration must restore actual off status and release busy state")
        check(controller.errorDescription == StubFailure.denied.errorDescription,
              "Failed registration exposes an actionable error")
        await controller.refresh()
        check(controller.errorDescription != nil,
              "Focus refresh must not immediately erase an unchanged operation failure")
        await service.configure(status: .enabled, shouldFail: true)
        await controller.refresh()
        check(controller.errorDescription == nil, "External state changes clear a stale error")
        await controller.setEnabled(false)
        check(controller.status == .enabled && controller.isSelected && controller.errorDescription != nil,
              "A failed unregister must not claim the service is disabled")

        await service.configure(status: .notRegistered, nextStatus: .requiresApproval, shouldFail: true)
        await controller.refresh()
        await controller.setEnabled(true)
        check(controller.status == .requiresApproval && controller.errorDescription != nil,
              "Even thrown operations must read back the real changed status")
        for status in [LoginItemStatus.notFound, .unknown] {
            await service.configure(status: status)
            await controller.refresh()
            check(controller.status == status && !controller.isSelected,
                  "Missing and future OS states must be exposed rather than claiming enabled")
        }

        await service.configure(status: .notRegistered, suspendMutation: true)
        await controller.refresh()
        let operation = Task { await controller.setEnabled(true) }
        var started = false
        for _ in 0..<10_000 {
            if await service.isSuspended() { started = true; break }
            await Task.yield()
        }
        check(started, "Controlled asynchronous registration started")
        check(controller.isBusy && !controller.isSelected,
              "A slow service acknowledges progress without optimistically changing the switch")
        counts = await service.counts()
        let countsBeforeIgnoredEvents = counts
        await controller.setEnabled(false)
        await controller.setEnabled(true)
        await controller.refresh()
        counts = await service.counts()
        check(counts == countsBeforeIgnoredEvents,
              "Concurrent refreshes and clicks cannot overtake an in-flight mutation")
        // Reaching this main-actor code while the service is suspended also proves UI work is free.
        await service.resume()
        await operation.value
        check(controller.status == .enabled && !controller.isBusy && controller.errorDescription == nil,
              "Completion reads status and clears progress")

        // An installed, signed app can legitimately report notFound before its first registration.
        let freshService = StubLoginItemService()
        await freshService.configure(status: .notFound)
        let freshController = LoginItemController(service: freshService)
        await freshController.refresh()
        check(freshController.status == .notFound && !freshController.isSelected && freshController.hasLoaded,
              "A fresh missing registration is shown as an available off switch")
        check(freshController.errorDescription == nil && !freshController.hasMissingRegistrationError,
              "First-run notFound must not incorrectly tell an installed user to reinstall")
        await freshController.setEnabled(true)
        check(freshController.status == .enabled && freshController.isSelected,
              "A fresh missing registration can be enabled directly")

        await freshService.configure(status: .notFound, shouldFail: true)
        await freshController.refresh()
        await freshController.setEnabled(true)
        check(freshController.errorDescription != nil && freshController.hasMissingRegistrationError,
              "A missing registration after a failed operation exposes the actual error and recovery hint")
        await freshService.configure(status: .notFound)
        await freshController.setEnabled(true)
        check(freshController.status == .enabled && !freshController.hasMissingRegistrationError
              && freshController.errorDescription == nil,
              "A successful retry clears the missing-registration error and hint")
        print("Login item checks passed: \(checks) assertions; no system login items or user preferences changed.")
    }
}
