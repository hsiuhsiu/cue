import Combine
import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case notRegistered, enabled, requiresApproval, notFound, unknown
}

protocol LoginItemService: Sendable {
    func status() async -> LoginItemStatus
    func setEnabled(_ enabled: Bool) async throws
}

/// Service Management may talk to system services. Keep it off the input/rendering thread,
/// and serialize reads and writes without adding a timer or a persisted shadow preference.
private actor SystemLoginItemService: LoginItemService {
    func status() -> LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        let currentStatus = service.status
        if enabled {
            // Approval is controlled by macOS; re-registering cannot override a user's denial.
            guard currentStatus != .enabled, currentStatus != .requiresApproval else { return }
            try service.register()
        } else {
            guard currentStatus != .notRegistered else { return }
            try service.unregister()
        }
    }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: LoginItemStatus = .notRegistered
    @Published private(set) var isBusy = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorDescription: String?

    private let service: any LoginItemService

    init(service: any LoginItemService = SystemLoginItemService()) {
        self.service = service
        // Reading or registering here would add work to app launch. Settings requests a refresh.
    }

    /// A pending registration remains selected so it can also be cancelled from Cue.
    /// The accompanying approval message distinguishes this from an enabled login item.
    var isSelected: Bool { status == .enabled || status == .requiresApproval }

    // macOS can report .notFound before this installed app's first registration.
    // It is only an actionable problem after a requested operation actually fails.
    var hasMissingRegistrationError: Bool { status == .notFound && errorDescription != nil }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let updatedStatus = await service.status()
        if updatedStatus != status { errorDescription = nil }
        status = updatedStatus
        hasLoaded = true
    }

    func setEnabled(_ enabled: Bool) async {
        guard hasLoaded, !isBusy, enabled != isSelected else { return }
        isBusy = true
        errorDescription = nil
        defer { isBusy = false }
        do {
            try await service.setEnabled(enabled)
        } catch {
            errorDescription = error.localizedDescription
        }
        // Registration can succeed while still requiring approval. Failure can also alter status.
        // Always show the OS's final state, never an optimistic or saved toggle value.
        status = await service.status()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
