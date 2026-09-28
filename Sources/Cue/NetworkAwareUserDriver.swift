import AppKit
import Sparkle

/// Wraps native Sparkle UI with public cancellation/reply callbacks. Silent
/// checks use this same path; there is no hidden uncancellable scheduled driver.
@MainActor
final class NetworkAwareUserDriver: NSObject, SPUUserDriver {
    var isBackground = false
    private let underlying: any SPUUserDriver
    private let requireNetwork: () throws -> Void
    private let availableVersion: (String) -> Void
    private var cancellation: (() -> Void)?
    private var pendingChoice: ((SPUUserUpdateChoice) -> Void)?
    private var cancellationChoice: SPUUserUpdateChoice = .dismiss
    private var pendingAcknowledgement: (() -> Void)?
    private var generation = 0
    private var cancelled = false
    private var allowsNetwork: Bool { !cancelled && (try? requireNetwork()) != nil }
    var acceptsNetworkActivity: Bool { allowsNetwork }

    init(underlying: any SPUUserDriver, requireNetwork: @escaping () throws -> Void,
         availableVersion: @escaping (String) -> Void) {
        self.underlying = underlying
        self.requireNetwork = requireNetwork
        self.availableVersion = availableVersion
    }

    func cancelNetworkActivity() {
        cancelled = true
        let cancel = cancellation
        let choice = pendingChoice
        let decline = cancellationChoice
        let acknowledge = pendingAcknowledgement
        clearCallbacks()
        underlying.dismissUpdateInstallation()
        cancel?()
        choice?(decline)
        acknowledge?()
    }

    func resumeForNewSession() {
        clearCallbacks()
        cancelled = false
    }

    private func clearCallbacks() {
        generation += 1
        cancellation = nil
        pendingChoice = nil
        cancellationChoice = .dismiss
        pendingAcknowledgement = nil
    }

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        clearCallbacks()
        guard allowsNetwork else { cancellation(); return }
        self.cancellation = cancellation
        guard !isBackground else { return }
        let token = generation
        underlying.showUserInitiatedUpdateCheck { [weak self] in
            guard let self, self.generation == token else { return }
            let cancel = self.cancellation
            self.cancellation = nil
            cancel?()
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearCallbacks()
        let decline: SPUUserUpdateChoice = state.stage == .installing ? .skip : .dismiss
        guard allowsNetwork else { reply(decline); return }
        guard !isBackground else {
            availableVersion(appcastItem.displayVersionString)
            reply(decline)
            return
        }
        pendingChoice = reply
        cancellationChoice = decline
        let token = generation
        underlying.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
            guard let self, self.generation == token else { return }
            let reply = self.pendingChoice
            self.pendingChoice = nil
            reply?(self.allowsNetwork ? choice : decline)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        showAcknowledgement(acknowledgement) { underlying.showUpdateNotFoundWithError(error, acknowledgement: $0) }
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        showAcknowledgement(acknowledgement) { underlying.showUpdaterError(error, acknowledgement: $0) }
    }

    private func showAcknowledgement(_ acknowledgement: @escaping () -> Void,
                                     present: (@escaping () -> Void) -> Void) {
        clearCallbacks()
        guard allowsNetwork, !isBackground else { acknowledgement(); return }
        pendingAcknowledgement = acknowledgement
        let token = generation
        present { [weak self] in
            guard let self, self.generation == token else { return }
            let acknowledgement = self.pendingAcknowledgement
            self.pendingAcknowledgement = nil
            acknowledgement?()
        }
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        clearCallbacks()
        guard allowsNetwork, !isBackground else { cancellation(); return }
        self.cancellation = cancellation
        let token = generation
        underlying.showDownloadInitiated { [weak self] in
            guard let self, self.generation == token else { return }
            let cancel = self.cancellation
            self.cancellation = nil
            cancel?()
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard allowsNetwork, !isBackground else { return }
        underlying.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard allowsNetwork, !isBackground else { return }
        underlying.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        clearCallbacks() // Download cancellation is invalid after this point.
        guard allowsNetwork, !isBackground else { return }
        underlying.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        guard allowsNetwork, !isBackground else { return }
        underlying.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearCallbacks()
        guard allowsNetwork, !isBackground else { reply(.skip); return }
        pendingChoice = reply
        cancellationChoice = .skip
        let token = generation
        underlying.showReady { [weak self] choice in
            guard let self, self.generation == token else { return }
            let reply = self.pendingChoice
            self.pendingChoice = nil
            reply?(self.allowsNetwork ? choice : .skip)
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        clearCallbacks()
        guard allowsNetwork, !isBackground else { return }
        let token = generation
        underlying.showInstallingUpdate(withApplicationTerminated: applicationTerminated) { [weak self] in
            guard let self, self.generation == token, self.allowsNetwork else { return }
            retryTerminatingApplication()
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        showAcknowledgement(acknowledgement) {
            underlying.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: $0)
        }
    }

    func dismissUpdateInstallation() {
        clearCallbacks()
        underlying.dismissUpdateInstallation()
    }

    func showUpdateInFocus() {
        guard allowsNetwork, !isBackground else { return }
        underlying.showUpdateInFocus?()
    }
}
