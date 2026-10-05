import AppKit
import Combine
import Sparkle

/// Isolated preferences, fake scheduling/bootstrap, and fake Sparkle UI. These
/// tests never start an updater, make a request, open a window, or install an app.
@main
struct CheckUpdates {
    @MainActor static func main() {
        let checks = Checks()
        checkController(checks)
        checkUserDriver(checks)
        checkSparkleBoundaries(checks)
        checkVersionDisplay(checks)
        if !checks.failures.isEmpty {
            checks.failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("Update network-policy/version regression passed: \(checks.count) checks; no network, updater startup, UI, or installation occurred.")
    }

    @MainActor private static func checkController(_ checks: Checks) {
        let suite = "com.yyhsiu.cue.tests.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "SUEnableAutomaticChecks")
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let scheduler = FakeScheduler()
        var engines: [FakeEngine] = []
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = UpdateController(networkPolicy: policy, defaults: defaults,
            makeEngine: { callbacks in
                let engine = FakeEngine(callbacks)
                engines.append(engine)
                return engine
            }, schedule: scheduler.schedule, now: { date })
        var presentations = 0
        controller.onPresentUpdate = { presentations += 1 }
        controller.start()
        controller.start()
        controller.checkForUpdates()
        controller.setAutomaticChecksEnabled(true)
        checks.expect(engines.isEmpty, "Offline startup/manual/automatic requests must never construct Sparkle")
        checks.expect(scheduler.actions.isEmpty, "Offline startup must schedule nothing despite persisted SU=true")
        checks.expect(!controller.automaticChecksEnabled && !controller.canCheckForUpdates,
                      "Both effective automatic/manual checks must be unavailable offline")
        checks.expect(defaults.bool(forKey: UpdateController.automaticPreferenceKey),
                      "Offline migration must preserve the user's previous automatic preference")
        checks.expect(presentations == 0, "Offline manual checks must not present an updater")

        policy.setAllowsNetwork(true)
        checks.expect(engines.count == 1 && engines[0].starts == 1, "Enabling networking must lazily start one engine")
        let engine = engines[0]
        checks.expect(controller.automaticChecksEnabled && controller.canCheckForUpdates,
                      "Online state must restore the desired preference and manual capability")
        checks.expect(scheduler.delays.last == 0, "The first automatic check may run after startup without a previous check")
        scheduler.actions.last?()
        checks.expect(engine.checks == [false], "Scheduled checks must use the injected cancellable background route")
        checks.expect(!controller.canCheckForUpdates, "An active check must publish its capability")
        checks.expect(defaults.object(forKey: UpdateController.lastCheckKey) as? Date == date,
                      "Check scheduling must retain a restart-safe last-check date")
        engine.callbacks.availableVersion("0.5.0")
        checks.expect(controller.availableVersion == "0.5.0", "An online background result must publish a gentle reminder")
        engine.finish()
        checks.expect(scheduler.delays.last == UpdateController.checkInterval, "Completion must schedule the next daily check")
        let staleScheduledAction = scheduler.actions.last!
        engine.sessionInProgress = true
        staleScheduledAction()
        checks.expect(engine.checks == [false], "A scheduled timer cannot switch an active manual session into background mode")
        engine.sessionInProgress = false
        policy.setAllowsNetwork(false)
        checks.expect(engine.cancellations == 1, "OFF must synchronously cancel the active engine")
        checks.expect(controller.availableVersion == nil && !controller.canCheckForUpdates && !controller.automaticChecksEnabled,
                      "OFF must clear reminders and disable all update controls immediately")
        staleScheduledAction()
        controller.checkForUpdates()
        engine.callbacks.availableVersion("late")
        engine.finish()
        checks.expect(engine.checks == [false] && presentations == 0 && controller.availableVersion == nil,
                      "Late timer/result callbacks cannot issue or expose updates offline")
        checks.expect(!controller.canCheckForUpdates, "Late engine completion cannot re-enable checking offline")
        do {
            try engine.callbacks.requireNetwork()
            checks.expect(false, "Every engine boundary must deny offline access")
        } catch { checks.expect(true, "The common policy denies offline engine access") }

        policy.setAllowsNetwork(true)
        staleScheduledAction()
        checks.expect(engine.checks == [false], "OFF/ON must not revive a previously canceled timer")
        controller.checkForUpdates()
        checks.expect(engines.count == 1 && engine.checks == [false, true] && presentations == 1,
                      "Re-enabling networking must retain one engine and permit an explicit manual check")
        policy.setAllowsNetwork(false)
        checks.expect(engine.cancellations == 2, "OFF during a manual check must cancel too")
        policy.setAllowsNetwork(true)
        controller.setAutomaticChecksEnabled(false)
        checks.expect(!controller.automaticChecksEnabled, "The user's automatic opt-out must persist independently")
        engine.finish()
        let count = engine.checks.count
        staleScheduledAction()
        checks.expect(engine.checks.count == count, "A stale timer cannot override automatic opt-out")
        policy.setAllowsNetwork(false)
        policy.setAllowsNetwork(true)
        checks.expect(!controller.automaticChecksEnabled, "A network cycle must preserve automatic opt-out")
        checks.expect(!defaults.bool(forKey: UpdateController.automaticPreferenceKey), "The desired opt-out must be stored")
    }

    @MainActor private static func checkUserDriver(_ checks: Checks) {
        let ui = FakeUserDriver()
        var allowed = true
        var versions: [String] = []
        let driver = NetworkAwareUserDriver(underlying: ui, requireNetwork: {
            guard allowed else { throw NetworkAccessError.disabled }
        }, availableVersion: { versions.append($0) })
        var cancelled = 0
        driver.showUserInitiatedUpdateCheck { cancelled += 1 }
        checks.expect(ui.checks == 1, "Online manual progress must use the native user driver")
        let staleCancel = ui.cancel
        allowed = false
        driver.cancelNetworkActivity()
        driver.cancelNetworkActivity()
        staleCancel?()
        checks.expect(cancelled == 1 && ui.dismissals == 2, "OFF must cancel exactly once and dismiss native UI")
        driver.showDownloadInitiated { cancelled += 1 }
        driver.showUserInitiatedUpdateCheck { cancelled += 1 }
        checks.expect(cancelled == 3 && ui.checks == 1 && ui.downloads == 0,
                      "Late download/check callbacks must cancel before showing UI offline")
        allowed = true
        driver.showDownloadInitiated { cancelled += 1 }
        checks.expect(cancelled == 4 && ui.downloads == 0, "Rapid OFF/ON cannot revive a canceled session")

        driver.resumeForNewSession()
        driver.isBackground = true
        driver.showUserInitiatedUpdateCheck { cancelled += 1 }
        checks.expect(ui.checks == 1, "Scheduled checks must not present progress or take focus")
        allowed = false
        driver.cancelNetworkActivity()
        checks.expect(cancelled == 5, "Silent feed checks must still have a live public cancellation callback")
        var acknowledged = 0
        driver.showUpdaterError(NSError(domain: "fixture", code: 1)) { acknowledged += 1 }
        driver.showUpdateNotFoundWithError(NSError(domain: "fixture", code: 2)) { acknowledged += 1 }
        checks.expect(acknowledged == 2 && ui.errors == 0 && ui.notFound == 0,
                      "Offline/background errors must be acknowledged without showing UI")

        allowed = true
        driver.resumeForNewSession()
        driver.isBackground = false
        driver.showDownloadInitiated { cancelled += 1 }
        checks.expect(ui.downloads == 1, "A fresh online manual download must forward its progress UI")
        driver.showDownloadDidReceiveData(ofLength: 32)
        checks.expect(ui.progress == 1, "An online active download must forward progress")
        allowed = false
        driver.cancelNetworkActivity()
        driver.showDownloadDidReceiveData(ofLength: 64)
        checks.expect(cancelled == 6 && ui.progress == 1, "OFF must cancel downloads and suppress late progress")

        allowed = true
        driver.resumeForNewSession()
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady { choices.append($0) }
        let staleChoice = ui.choice
        allowed = false
        driver.cancelNetworkActivity()
        allowed = true
        staleChoice?(.install)
        checks.expect(choices == [.skip], "OFF must cancel a ready installation and invalidate a queued Install click")
        driver.showReady { choices.append($0) }
        checks.expect(choices == [.skip, .skip], "A late install-ready callback must not revive canceled work")

        driver.resumeForNewSession()
        driver.showUpdaterError(NSError(domain: "fixture", code: 3)) { acknowledged += 1 }
        let staleAcknowledgement = ui.acknowledgement
        allowed = false
        driver.cancelNetworkActivity()
        staleAcknowledgement?()
        checks.expect(acknowledged == 3 && ui.errors == 1, "OFF must settle pending error acknowledgement exactly once")
        allowed = true
        driver.resumeForNewSession()
        var retried = 0
        driver.showInstallingUpdate(withApplicationTerminated: false) { retried += 1 }
        let staleRetry = ui.retry
        allowed = false
        driver.cancelNetworkActivity()
        allowed = true
        driver.resumeForNewSession()
        staleRetry?()
        checks.expect(retried == 0, "An old installation retry cannot revive after OFF/ON and a new session")

        let item = appcastItem()
        let state = SPUUserUpdateState(coder: StateDecoder(stage: .notDownloaded))!
        driver.isBackground = true
        var foundChoices: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: item, state: state) { foundChoices.append($0) }
        checks.expect(versions == ["0.5.0"] && foundChoices == [.dismiss] && ui.found == 0,
                      "Background appcasts must publish a gentle reminder and dismiss without update UI")
        driver.isBackground = false
        driver.showUpdateFound(with: item, state: state) { foundChoices.append($0) }
        let staleInstall = ui.choice
        checks.expect(ui.found == 1, "An online manual appcast must forward to native update UI")
        allowed = false
        driver.cancelNetworkActivity()
        allowed = true
        driver.resumeForNewSession()
        staleInstall?(.install)
        checks.expect(foundChoices == [.dismiss, .dismiss], "OFF must settle an offered update and invalidate its old Install reply")
        let installing = SPUUserUpdateState(coder: StateDecoder(stage: .installing))!
        driver.showUpdateFound(with: item, state: installing) { foundChoices.append($0) }
        allowed = false
        driver.cancelNetworkActivity()
        checks.expect(foundChoices.last == .skip, "OFF must cancel an already-installing offered update instead of deferring installation to quit")
        driver.showUpdateFound(with: item, state: installing) { foundChoices.append($0) }
        checks.expect(foundChoices.last == .skip, "A late already-installing callback while OFF must cancel instead of installing on quit")
        driver.showUpdateFound(with: item, state: state) { foundChoices.append($0) }
        checks.expect(versions == ["0.5.0"] && ui.found == 2 && foundChoices.last == .dismiss,
                      "A late offline appcast must neither show UI nor publish a reminder")
    }

    @MainActor private static func appcastItem(version: String = "0.5.0", build: String = "5") -> SUAppcastItem {
        // Public legacy initializer is sufficient for this local data-only fixture.
        SUAppcastItem(dictionary: [
            "title": "Fixture", "sparkle:version": build, "sparkle:shortVersionString": version,
            "enclosure": ["url": "https://invalid.example/Cue.zip", "length": "1", "type": "application/octet-stream"],
        ])!
    }

    @MainActor private static func checkVersionDisplay(_ checks: Checks) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cue-update-version-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            func bundle(_ name: String, _ info: [String: Any]) throws -> Bundle {
                let app = root.appendingPathComponent("\(name).app")
                let contents = app.appendingPathComponent("Contents")
                try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
                var metadata = info
                metadata["CFBundleIdentifier"] = "com.yyhsiu.cue.tests.versions.\(name)"
                metadata["CFBundleName"] = "Cue Fixture"
                metadata["CFBundlePackageType"] = "APPL"
                let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
                try data.write(to: contents.appendingPathComponent("Info.plist"))
                guard let bundle = Bundle(url: app) else {
                    throw NSError(domain: "CueVersionFixture", code: 1)
                }
                return bundle
            }

            let beta = CueUpdateVersionDisplayer(bundle: try bundle("beta", [
                "CFBundleShortVersionString": "0.10.0", "CFBundleVersion": "12",
                "CueBuildChannel": "beta", "CuePrereleaseNumber": 1,
            ]))
            let release = appcastItem(version: "0.10.0", build: "13")
            var installed: NSString = "0.10.0"
            let available = beta.formatUpdateVersion(fromUpdate: release, andBundleDisplayVersion: &installed,
                                                    withBundleVersion: "12")
            checks.expect(installed == "0.10.0-beta.1" && available == "0.10.0",
                          "An installed beta and its same-base final release must have distinct public version labels")
            checks.expect(!installed.contains("(") && !available.contains("("),
                          "Update UI must not append numeric build numbers in parentheses")
            checks.expect(beta.formatBundleDisplayVersion("0.10.0", withBundleVersion: "12", matchingUpdate: nil)
                            == "0.10.0-beta.1",
                          "The no-update alert must use the same installed beta label")
            checks.expect(beta.formatBundleDisplayVersion("0.10.0", withBundleVersion: "12", matchingUpdate: release)
                            == "0.10.0-beta.1",
                          "A matching feed item must not replace the installed build's public channel label")
            checks.expect(release.versionString == "13" && release.displayVersionString == "0.10.0",
                          "Formatting must preserve the feed's original build and public version")
            let comparator = SUStandardVersionComparator()
            checks.expect(comparator.compareVersion("12", toVersion: release.versionString) == .orderedAscending,
                          "Sparkle must still order numeric beta build 12 before final build 13")

            let legacy = CueUpdateVersionDisplayer(bundle: try bundle("legacy", [
                "CFBundleShortVersionString": "0.9.1", "CFBundleVersion": "11",
            ]))
            var legacyInstalled: NSString = "0.9.1"
            let legacyAvailable = legacy.formatUpdateVersion(
                fromUpdate: appcastItem(version: "0.9.1", build: "12"),
                andBundleDisplayVersion: &legacyInstalled, withBundleVersion: "11"
            )
            checks.expect(legacyInstalled == "0.9.1" && legacyAvailable == "0.9.1",
                          "Legacy metadata must remain a plain stable label even when feed and bundle bases match")
            checks.expect(legacy.formatBundleDisplayVersion("0.9.1", withBundleVersion: "11", matchingUpdate: nil)
                            == "0.9.1",
                          "A legacy installed build must not gain a build-number suffix in no-update UI")

            let missing = CueUpdateVersionDisplayer(bundle: try bundle("missing", [:]))
            var suppliedLabel: NSString = "Supplied by Sparkle"
            let suppliedUpdate = missing.formatUpdateVersion(fromUpdate: release, andBundleDisplayVersion: &suppliedLabel,
                                                             withBundleVersion: "12")
            checks.expect(suppliedLabel == "Supplied by Sparkle" && suppliedUpdate == "0.10.0",
                          "Missing bundle metadata must preserve Sparkle's supplied display label")
            checks.expect(missing.formatBundleDisplayVersion("Supplied by Sparkle", withBundleVersion: "12", matchingUpdate: nil)
                            == "Supplied by Sparkle",
                          "The no-update path must also retain its safe metadata fallback")
            for selector in [
                "formatUpdateDisplayVersionFromUpdate:andBundleDisplayVersion:withBundleVersion:",
                "formatBundleDisplayVersion:withBundleVersion:matchingUpdate:",
            ] {
                checks.expect(beta.responds(to: NSSelectorFromString(selector)),
                              "The version formatter must expose Sparkle's public selector \(selector)")
            }
        } catch {
            checks.expect(false, "Unable to construct isolated version fixtures: \(error)")
        }
    }

    @MainActor private static func checkSparkleBoundaries(_ checks: Checks) {
        // Neither the adapter nor this separate inert updater is ever started.
        // Passing the inert public object allows testing real delegate selectors.
        let ui = FakeUserDriver()
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: ui, delegate: nil)
        var allowed = true
        let engine = SparkleUpdateEngine(bundle: .main, callbacks: UpdateEngineCallbacks(
            requireNetwork: { guard allowed else { throw NetworkAccessError.disabled } },
            availableVersion: { _ in }, stateChanged: {}, sessionFinished: {}
        ))
        for type in [SPUUpdateCheck.updates, .updatesInBackground, .updateInformation] {
            do {
                try engine.updater(updater, mayPerform: type)
                checks.expect(type == .updates, "Only the cancellable check type may pass the real Sparkle delegate")
            } catch {
                checks.expect(type != .updates, "Scheduled/probe Sparkle checks must be rejected even while online")
            }
        }
        let item = appcastItem()
        checks.expect(!engine.updater(updater, shouldDownloadReleaseNotesForUpdate: item),
                      "Real Sparkle delegate must always disable independent remote-note downloads")
        let online = NSMutableURLRequest(url: URL(string: "https://invalid.example/Cue.zip")!)
        engine.updater(updater, willDownloadUpdate: item, with: online)
        checks.expect(online.url?.scheme == "https", "An allowed archive request must preserve Sparkle's signed download URL")
        allowed = false
        for type in [SPUUpdateCheck.updates, .updatesInBackground, .updateInformation] {
            do {
                try engine.updater(updater, mayPerform: type)
                checks.expect(false, "OFF must deny every real Sparkle check type")
            } catch { checks.expect(true, "Real Sparkle check delegate denies offline access") }
        }
        do {
            try engine.updater(updater, shouldProceedWithUpdate: item, updateCheck: .updates)
            checks.expect(false, "A feed result arriving after OFF must be rejected")
        } catch { checks.expect(true, "Real Sparkle proceed delegate denies offline results") }
        let late = NSMutableURLRequest(url: URL(string: "https://invalid.example/Cue.zip")!)
        engine.updater(updater, willDownloadUpdate: item, with: late)
        checks.expect(late.url?.isFileURL == true && late.url?.path == "/dev/null",
                      "An Install queued before OFF must be rewritten to a non-network URL at download creation")
        allowed = true
        let revived = NSMutableURLRequest(url: URL(string: "https://invalid.example/Cue.zip")!)
        engine.updater(updater, willDownloadUpdate: item, with: revived)
        checks.expect(revived.url?.isFileURL == true,
                      "Rapid OFF/ON must not allow a canceled old archive request to resume network activity")
        do {
            try engine.updater(updater, mayPerform: .updates)
            checks.expect(false, "A canceled old session must remain denied after OFF/ON")
        } catch { checks.expect(true, "Canceled check callbacks stay blocked after re-enabling networking") }
        do {
            try engine.updater(updater, shouldProceedWithUpdate: item, updateCheck: .updates)
            checks.expect(false, "An old appcast must remain denied after OFF/ON")
        } catch { checks.expect(true, "Canceled appcast callbacks stay blocked after re-enabling networking") }
        checks.expect(!engine.updaterShouldPromptForPermissionToCheck(forUpdates: updater),
                      "Sparkle must never show its own automatic-network consent prompt")
        checks.expect(!engine.standardUserDriverShouldShowVersionHistory(for: item),
                      "A stale standard modal alert must not retain an ungated external browser action")
        checks.expect(engine.standardUserDriverRequestsVersionDisplayer() is CueUpdateVersionDisplayer,
                      "The real Sparkle driver delegate must install Cue's public-version formatter")
        for selector in [
            "updater:mayPerformUpdateCheck:error:", "updater:shouldProceedWithUpdate:updateCheck:error:",
            "updater:shouldDownloadReleaseNotesForUpdate:", "updater:willDownloadUpdate:withRequest:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:", "updaterShouldPromptForPermissionToCheckForUpdates:",
            "standardUserDriverShouldShowVersionHistoryForAppcastItem:",
            "standardUserDriverRequestsVersionDisplayer",
        ] {
            checks.expect(engine.responds(to: NSSelectorFromString(selector)),
                          "The runtime must expose the real optional Sparkle delegate selector \(selector)")
        }
    }
}

private final class StateDecoder: NSCoder {
    let stage: SPUUserUpdateStage
    init(stage: SPUUserUpdateStage) { self.stage = stage }
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int { stage.rawValue }
    override func decodeBool(forKey key: String) -> Bool { true }
}

@MainActor private final class FakeEngine: UpdateEngine {
    let callbacks: UpdateEngineCallbacks
    var canCheckForUpdates = true
    var sessionInProgress = false
    var starts = 0
    var checks: [Bool] = []
    var cancellations = 0
    init(_ callbacks: UpdateEngineCallbacks) { self.callbacks = callbacks }
    func start() throws { try callbacks.requireNetwork(); starts += 1 }
    func checkForUpdates(userInitiated: Bool) {
        checks.append(userInitiated)
        sessionInProgress = true
        canCheckForUpdates = false
        callbacks.stateChanged()
    }
    func cancelNetworkActivity() { cancellations += 1; canCheckForUpdates = false }
    func finish() { sessionInProgress = false; canCheckForUpdates = true; callbacks.sessionFinished() }
}

@MainActor private final class FakeScheduler {
    var delays: [TimeInterval] = []
    var actions: [@MainActor () -> Void] = []
    func schedule(_ delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        delays.append(delay)
        actions.append(action)
        return AnyCancellable {}
    }
}

@MainActor private final class FakeUserDriver: NSObject, SPUUserDriver {
    var checks = 0, downloads = 0, dismissals = 0, progress = 0, errors = 0, notFound = 0, found = 0
    var cancel: (() -> Void)?
    var choice: ((SPUUserUpdateChoice) -> Void)?
    var acknowledgement: (() -> Void)?
    var retry: (() -> Void)?
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { checks += 1; cancel = cancellation }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { found += 1; choice = reply }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { notFound += 1; self.acknowledgement = acknowledgement }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { errors += 1; self.acknowledgement = acknowledgement }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { downloads += 1; cancel = cancellation }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { progress += 1 }
    func showDownloadDidReceiveData(ofLength length: UInt64) { progress += 1 }
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { choice = reply }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { retry = retryTerminatingApplication }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { self.acknowledgement = acknowledgement }
    func dismissUpdateInstallation() { dismissals += 1 }
}

@MainActor private final class Checks {
    var count = 0
    var failures: [String] = []
    func expect(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures.append(message) }
    }
}
