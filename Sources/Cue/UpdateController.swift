import AppKit
import Combine
import CueCore
import Sparkle

private enum UpdateText {
    static let unavailable = L10n.string(
        "update.unavailable", table: "Menu", value: "Updates are unavailable in this build: %@"
    )
}

@MainActor
protocol UpdateEngine: AnyObject {
    var canCheckForUpdates: Bool { get }
    var sessionInProgress: Bool { get }
    func start() throws
    func checkForUpdates(userInitiated: Bool)
    func cancelNetworkActivity()
}

@MainActor
struct UpdateEngineCallbacks {
    let requireNetwork: () throws -> Void
    let availableVersion: (String) -> Void
    let stateChanged: () -> Void
    let sessionFinished: () -> Void
}

/// All update traffic shares Cue's network policy. Sparkle's own scheduler stays
/// disabled because its background feed checks expose no public cancellation.
/// A single Cue timer instead uses the cancellable user-initiated driver silently.
@MainActor
final class UpdateController: ObservableObject {
    static let automaticPreferenceKey = "updates.automaticChecksEnabled"
    static let lastCheckKey = "updates.lastCheckDate"
    static let checkInterval: TimeInterval = 86_400

    @Published private(set) var automaticChecksEnabled = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var startupError: String?
    var onPresentUpdate: (() -> Void)?

    private let networkPolicy: NetworkPolicy
    private let defaults: UserDefaults
    private let makeEngine: (UpdateEngineCallbacks) -> any UpdateEngine
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable
    private let now: () -> Date
    private var desiredAutomaticChecks: Bool
    private var engine: (any UpdateEngine)?
    private var policySubscription: AnyCancellable?
    private var timer: AnyCancellable?
    private var timerGeneration = 0
    private var startRequested = false

    init(networkPolicy: NetworkPolicy, defaults: UserDefaults = .standard,
         bundle: Bundle = .main,
         makeEngine: ((UpdateEngineCallbacks) -> any UpdateEngine)? = nil,
         schedule: ((TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.networkPolicy = networkPolicy
        self.defaults = defaults
        self.now = now
        self.makeEngine = makeEngine ?? { SparkleUpdateEngine(bundle: bundle, callbacks: $0) }
        self.schedule = schedule ?? Self.scheduleTimer
        // Migrate before Sparkle is constructed or its automatic setting is forced
        // off. Offline launch preserves this preference without starting Sparkle.
        desiredAutomaticChecks = defaults.object(forKey: Self.automaticPreferenceKey) as? Bool
            ?? defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool
            ?? bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool
            ?? false
        defaults.set(desiredAutomaticChecks, forKey: Self.automaticPreferenceKey)
        policySubscription = networkPolicy.changes.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.applyNetworkPolicy() }
        }
        automaticChecksEnabled = networkPolicy.allowsNetwork && desiredAutomaticChecks
    }

    /// Called after the launcher and shortcut are ready. Offline means no Sparkle
    /// object, installer probe, timer, permission prompt, or feed request.
    func start() {
        startRequested = true
        applyNetworkPolicy()
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard networkPolicy.allowsNetwork, startupError == nil else { return }
        desiredAutomaticChecks = enabled
        defaults.set(enabled, forKey: Self.automaticPreferenceKey)
        automaticChecksEnabled = enabled
        reschedule()
    }

    func checkForUpdates() {
        guard networkPolicy.allowsNetwork, startupError == nil,
              canCheckForUpdates, let engine else { return }
        onPresentUpdate?()
        availableVersion = nil
        beginCheck(engine, userInitiated: true)
    }

    private func applyNetworkPolicy() {
        automaticChecksEnabled = networkPolicy.allowsNetwork && desiredAutomaticChecks
        guard networkPolicy.allowsNetwork else {
            timer = nil
            timerGeneration += 1
            canCheckForUpdates = false
            availableVersion = nil
            // Policy changes before this synchronous callback, so queued replies
            // and delegate callbacks are denied immediately as well.
            engine?.cancelNetworkActivity()
            return
        }
        guard startRequested else { return }
        if engine == nil {
            startupError = nil
            let callbacks = UpdateEngineCallbacks(
                requireNetwork: { [weak self] in
                    guard let self else { throw NetworkAccessError.disabled }
                    try self.networkPolicy.requireAccess()
                },
                availableVersion: { [weak self] version in
                    guard let self, self.networkPolicy.allowsNetwork else { return }
                    self.availableVersion = version
                },
                stateChanged: { [weak self] in self?.refreshState() },
                sessionFinished: { [weak self] in self?.refreshState(); self?.reschedule() }
            )
            let created = makeEngine(callbacks)
            engine = created
            do { try created.start() }
            catch {
                created.cancelNetworkActivity()
                engine = nil
                startupError = L10n.format(UpdateText.unavailable, error.localizedDescription)
            }
        }
        refreshState()
        reschedule()
    }

    private func refreshState() {
        canCheckForUpdates = networkPolicy.allowsNetwork && startupError == nil
            && (engine?.canCheckForUpdates == true)
    }

    private func beginCheck(_ engine: any UpdateEngine, userInitiated: Bool) {
        guard networkPolicy.allowsNetwork else { return }
        defaults.set(now(), forKey: Self.lastCheckKey)
        timer = nil
        engine.checkForUpdates(userInitiated: userInitiated)
        refreshState()
        reschedule()
    }

    private func reschedule() {
        timer = nil
        timerGeneration += 1
        guard startRequested, networkPolicy.allowsNetwork, desiredAutomaticChecks,
              startupError == nil, let engine, engine.canCheckForUpdates, !engine.sessionInProgress else { return }
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
            ?? defaults.object(forKey: "SULastCheckTime") as? Date
        let delay = lastCheck.map { min(Self.checkInterval, max(0, Self.checkInterval - now().timeIntervalSince($0))) } ?? 0
        let generation = timerGeneration
        timer = schedule(delay) { [weak self] in
            guard let self, self.timerGeneration == generation,
                  self.networkPolicy.allowsNetwork, self.desiredAutomaticChecks,
                  let engine = self.engine, engine.canCheckForUpdates, !engine.sessionInProgress else { return }
            self.beginCheck(engine, userInitiated: false)
        }
    }

    private static func scheduleTimer(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, leeway: .seconds(60))
        timer.setEventHandler { MainActor.assumeIsolated { action() } }
        timer.resume()
        return AnyCancellable { timer.cancel() }
    }
}

/// Public Sparkle interfaces only. All sessions use checkForUpdates() so their
/// feed request supplies a cancellation callback before it starts.
@MainActor
final class SparkleUpdateEngine: NSObject, UpdateEngine, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let callbacks: UpdateEngineCallbacks
    private nonisolated let versionDisplayer: CueUpdateVersionDisplayer
    private var updater: SPUUpdater!
    private var driver: NetworkAwareUserDriver!
    private var subscription: AnyCancellable?
    private var cancelling = false
    var canCheckForUpdates: Bool { !cancelling && updater.canCheckForUpdates }
    var sessionInProgress: Bool { updater.sessionInProgress }

    init(bundle: Bundle, callbacks: UpdateEngineCallbacks) {
        self.callbacks = callbacks
        versionDisplayer = CueUpdateVersionDisplayer(bundle: bundle)
        super.init()
        driver = NetworkAwareUserDriver(
            underlying: SPUStandardUserDriver(hostBundle: bundle, delegate: self),
            requireNetwork: callbacks.requireNetwork, availableVersion: callbacks.availableVersion
        )
        updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
    }

    func start() throws {
        try callbacks.requireNetwork()
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
        subscription = updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .removeDuplicates().sink { [weak self] _ in
                MainActor.assumeIsolated { self?.callbacks.stateChanged() }
            }
        try updater.start()
    }

    func checkForUpdates(userInitiated: Bool) {
        guard canCheckForUpdates, (try? callbacks.requireNetwork()) != nil else { return }
        guard userInitiated || !updater.sessionInProgress else { return }
        if !updater.sessionInProgress { driver.resumeForNewSession() }
        driver.isBackground = !userInitiated
        updater.checkForUpdates()
    }

    func cancelNetworkActivity() {
        cancelling = updater.sessionInProgress
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        driver.cancelNetworkActivity()
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try callbacks.requireNetwork()
        // A restored SU preference cannot enable uncancellable scheduled/probe
        // feed checks. Cue owns all background scheduling.
        guard updateCheck == .updates, !cancelling, driver.acceptsNetworkActivity else { throw NetworkAccessError.disabled }
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        try callbacks.requireNetwork()
        guard !cancelling, driver.acceptsNetworkActivity else { throw NetworkAccessError.disabled }
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        // Remote notes have no standalone cancellation API. Embedded signed
        // appcast notes remain available in the native update dialog.
        false
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        guard !cancelling, driver.acceptsNetworkActivity, (try? callbacks.requireNetwork()) != nil else {
            // An Install reply queued just before OFF may drain afterward. Its
            // later request must not reach the network while aborting.
            request.url = URL(fileURLWithPath: "/dev/null")
            driver.cancelNetworkActivity()
            return
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        cancelling = false
        callbacks.sessionFinished()
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    nonisolated func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? {
        versionDisplayer
    }

    nonisolated func standardUserDriverShouldShowVersionHistory(for item: SUAppcastItem) -> Bool {
        // Sparkle's generic "no update" modal alert can outlive dismissal. Omit
        // its direct browser action so that a stale alert cannot bypass policy.
        false
    }
}

/// Display metadata does not participate in Sparkle's numeric build comparison.
/// Keeping the channel here distinguishes, for example, 0.10.0-beta.1 from the
/// final 0.10.0 without Sparkle appending internal build numbers in parentheses.
final class CueUpdateVersionDisplayer: NSObject, SUVersionDisplay, @unchecked Sendable {
    // Immutable after initialization; Sparkle's nonisolated delegate may read it.
    private let installedVersion: String?

    init(bundle: Bundle) {
        installedVersion = AppVersion(bundle: bundle).displayVersion
        super.init()
    }

    func formatUpdateVersion(fromUpdate update: SUAppcastItem,
                             andBundleDisplayVersion bundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
                             withBundleVersion bundleVersion: String) -> String {
        if let installedVersion {
            bundleDisplayVersion.pointee = installedVersion as NSString
        }
        // Feed versions are the publisher's public labels. Never add a build
        // suffix or copy the installed build's beta/dev channel to an update.
        return update.displayVersionString
    }

    func formatBundleDisplayVersion(_ bundleDisplayVersion: String, withBundleVersion bundleVersion: String,
                                    matchingUpdate: SUAppcastItem?) -> String {
        installedVersion ?? bundleDisplayVersion
    }
}
