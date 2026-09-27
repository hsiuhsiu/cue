import AppKit
import Combine
import Sparkle

private enum UpdateText {
    static let unavailable = L10n.string(
        "update.unavailable", table: "Menu", value: "Updates are unavailable in this build: %@"
    )
}

/// Sparkle owns scheduling, persisted update preferences, verification, and installation.
/// Launcher input never performs update work; scheduled checks only publish a gentle reminder.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var automaticChecksEnabled = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var startupError: String?

    /// Called only in response to an explicit user request to open the updater.
    var onPresentUpdate: (() -> Void)?

    private var controller: SPUStandardUpdaterController?
    private var subscriptions = Set<AnyCancellable>()

    /// Call after the launcher and its shortcut are ready. No network request is awaited here.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        let updater = controller.updater

        // Cue only checks for releases automatically. Installation always requires a user choice.
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false

        updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
            .removeDuplicates()
            .sink { [weak self] enabled in
                MainActor.assumeIsolated { self?.automaticChecksEnabled = enabled }
            }
            .store(in: &subscriptions)
        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .removeDuplicates()
            .sink { [weak self] enabled in
                MainActor.assumeIsolated { self?.canCheckForUpdates = enabled }
            }
            .store(in: &subscriptions)

        do {
            // Catch configuration errors without presenting an alert over the launcher.
            try updater.start()
        } catch {
            startupError = L10n.format(UpdateText.unavailable, error.localizedDescription)
            canCheckForUpdates = false
        }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard startupError == nil, let updater = controller?.updater,
              updater.automaticallyChecksForUpdates != enabled else { return }
        // This property persists itself and reschedules checks; do not mirror it in CueSettings.
        updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard startupError == nil, canCheckForUpdates, let controller else { return }
        onPresentUpdate?()
        controller.checkForUpdates(nil)
    }

    // Sparkle delivers standard-user-driver callbacks on the main thread, but its legacy
    // delegate protocol is not actor-annotated. The conformance checks that at runtime.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Even a check near launch must not take keyboard focus from search or another app.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        availableVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
