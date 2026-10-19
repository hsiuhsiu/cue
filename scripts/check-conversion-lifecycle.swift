import AppKit
import CueCore

private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let waiting = waiters
        waiters.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private actor SelectionFixture: SelectedTextAccessing {
    struct Counts: Sendable { let captures: Int; let processIDs: [Int32]; let replacements: [String]; let discards: Int }
    private var captures = 0
    private var processIDs: [Int32] = []
    private var replacements: [String] = []
    private var discards = 0
    private var captureGate: Gate?
    private var replacementGate: Gate?
    private var captureError: SelectedTextError?

    func configure(capture: Gate? = nil, replacement: Gate? = nil, error: SelectedTextError? = nil) {
        captureGate = capture
        replacementGate = replacement
        captureError = error
    }
    func capture(processID: Int32) async throws -> SelectedTextSession {
        captures += 1
        processIDs.append(processID)
        if let captureGate { await captureGate.wait() }
        if let captureError { throw captureError }
        // Deliberately return even after cancellation, like an in-flight AX call.
        return SelectedTextSession(processID: processID, text: "软件")
    }
    func replace(_ session: SelectedTextSession, with text: String) async throws {
        try Task.checkCancellation()
        replacements.append(text)
        // Model a paste already posted: cleanup must finish despite cancellation.
        if let replacementGate { await replacementGate.wait() }
    }
    func discard(_ session: SelectedTextSession) { discards += 1 }
    func counts() -> Counts { Counts(captures: captures, processIDs: processIDs, replacements: replacements, discards: discards) }
}

private actor ConverterFixture {
    private var gate: Gate?
    private var requests = 0
    func setGate(_ value: Gate?) { gate = value }
    func count() -> Int { requests }
    func convert(_ text: String, target: ChineseConversionTarget) async throws -> String {
        requests += 1
        if let gate { await gate.wait() }
        try Task.checkCancellation()
        return target == .traditionalTaiwan ? "軟體" : "软件"
    }
}

@MainActor private final class SourceFixture {
    var processID: Int32? = 42_424
    var observations = 0
    var restorations = 0
    func observe() -> Int32? { observations += 1; return processID }
    func restore(_ processID: Int32) -> Bool { restorations += 1; return self.processID == processID }
}

/// Simulates key focus independently of foreground-app ownership. No windows
/// are ordered and no real application is activated.
@MainActor private final class FocusFixture {
    let cue: Int32 = 100
    let browser: Int32 = 200
    var snapshot = LauncherFocusRequest.State(isVisible: false, isKeyWindow: false, frontmostProcess: 200)
    var events: [String] = []
    var queued: [@MainActor @Sendable () -> Void] = []
    var focusSucceeds = true
    lazy var request = LauncherFocusRequest(
        processID: cue, state: { [unowned self] in snapshot },
        orderAndFocus: { [unowned self] in
            events.append("focus"); snapshot.isVisible = true
            if focusSucceeds { snapshot.isKeyWindow = true }
        },
        nextEvent: { [unowned self] work in queued.append(work) }
    )
    func nextEvent() { if !queued.isEmpty { queued.removeFirst()() } }
}

/// Hidden windows and injected sessions only. Never reads accessibility, touches
/// the real clipboard, activates another application, or posts keyboard events.
@main struct CheckConversionLifecycle {
    @MainActor private static var checks = 0
    @MainActor private static func check(_ value: Bool, _ message: String) {
        guard value else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }
    @MainActor private static func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        fatalError("Timed out waiting for fixture")
    }
    @MainActor private static func submit(_ view: LauncherView) {
        _ = view.control(view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    }

    @MainActor private static func checkFocusHandoff() {
        let immediate = FocusFixture()
        immediate.request.present()
        check(immediate.events == ["focus"] && immediate.snapshot.frontmostProcess == immediate.browser,
              "Panel focus does not require changing the foreground app")
        check(immediate.request.hasKeyboardFocus, "A nonactivating key panel accepts input while the source remains active")
        immediate.nextEvent()
        check(immediate.events == ["focus"] && immediate.queued.isEmpty,
              "Successful focus does not reassign an existing editor at the next event")
        immediate.snapshot.frontmostProcess = immediate.cue
        check(immediate.request.hasKeyboardFocus, "The same key panel also works when Cue itself is active")

        let delayed = FocusFixture()
        delayed.focusSucceeds = false
        delayed.request.present()
        check(delayed.snapshot.isVisible && !delayed.request.hasKeyboardFocus,
              "Visibility without key ownership does not count as keyboard focus")
        delayed.focusSucceeds = true
        delayed.nextEvent()
        check(delayed.events == ["focus", "focus"] && delayed.request.hasKeyboardFocus,
              "A single next-event check can finish an incomplete key-window handoff")
        delayed.request.foregroundApplicationChanged(to: delayed.cue)
        check(delayed.events.count == 2 && delayed.queued.isEmpty,
              "Later application activation cannot disturb a completed input session")

        for foreground in [Int32(100), Int32(200)] {
            let changed = FocusFixture()
            changed.focusSucceeds = false
            changed.request.present()
            changed.snapshot.frontmostProcess = foreground
            changed.request.foregroundApplicationChanged(to: foreground)
            changed.focusSucceeds = true
            changed.nextEvent()
            check(changed.request.hasKeyboardFocus && changed.events.count == 2,
                  "Cue or the original source becoming active preserves the pending key-focus check")
        }

        let denied = FocusFixture()
        denied.focusSucceeds = false
        denied.request.present(); denied.nextEvent()
        for _ in 0..<10 { denied.request.foregroundApplicationChanged(to: denied.cue) }
        check(denied.events == ["focus", "focus"] && denied.queued.isEmpty && !denied.request.hasKeyboardFocus,
              "Denied key focus has one retry only; unrelated activation cannot restart it")

        let switched = FocusFixture()
        switched.focusSucceeds = false
        switched.request.present()
        switched.snapshot.frontmostProcess = 300
        switched.nextEvent()
        switched.request.foregroundApplicationChanged(to: switched.cue)
        check(switched.events == ["focus"], "A different foreground app cancels queued and late recovery")

        let switchedBack = FocusFixture()
        switchedBack.focusSucceeds = false
        switchedBack.request.present(); switchedBack.request.foregroundApplicationChanged(to: 300)
        switchedBack.snapshot.frontmostProcess = switchedBack.browser
        switchedBack.nextEvent(); switchedBack.request.foregroundApplicationChanged(to: switchedBack.cue)
        check(switchedBack.events == ["focus"], "Switching away and back still invalidates the earlier request")

        let unknown = FocusFixture()
        unknown.focusSucceeds = false
        unknown.request.present(); unknown.snapshot.frontmostProcess = nil; unknown.nextEvent()
        check(unknown.events == ["focus"], "Unknown foreground ownership never triggers delayed focus changes")

        for hidden in [false, true] {
            let dismissed = FocusFixture()
            dismissed.focusSucceeds = false
            dismissed.request.present()
            if hidden { dismissed.snapshot.isVisible = false }
            else { dismissed.request.cancel() } // Escape, Settings or key-window loss.
            dismissed.nextEvent(); dismissed.request.foregroundApplicationChanged(to: dismissed.cue)
            check(dismissed.events == ["focus"], "Canceled or hidden launchers cannot reopen from old callbacks")
        }

        let newer = FocusFixture()
        newer.focusSucceeds = false
        newer.request.present(); newer.request.cancel(); newer.request.present()
        newer.nextEvent()
        check(newer.events == ["focus", "focus"], "An old callback cannot repair a newer invocation")
        newer.focusSucceeds = true
        newer.nextEvent()
        check(newer.events.count == 3 && newer.request.hasKeyboardFocus,
              "The current invocation retains its own single recovery attempt")

        let keyLost = FocusFixture()
        keyLost.request.present(); keyLost.snapshot.isKeyWindow = false
        keyLost.request.cancel() // windowDidResignKey: the user chose another window.
        keyLost.nextEvent()
        check(keyLost.events == ["focus"] && !keyLost.request.hasKeyboardFocus,
              "A genuine key-window loss cancels recovery even when the source app stays active")
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.mainMenu = nil
        checkFocusHandoff()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cue-conversion-lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let domain = "com.yyhsiu.cue.tests.conversion.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let board = NSPasteboard(name: NSPasteboard.Name(domain))
        defer { board.releaseGlobally() }
        let clipboard = ClipboardModel(defaults: defaults, fileURL: folder.appendingPathComponent("clipboard.json"), pasteboardName: board.name)
        let source = SourceFixture()
        let selections = SelectionFixture()
        let converter = ConverterFixture()
        let model = LauncherModel(usageStore: SearchUsageStore(fileURL: folder.appendingPathComponent("Search/usage.json")))
        let controller = LauncherPanelController(
            clipboard: clipboard, model: model,
            performSystemAction: { _ in fatalError("Unexpected system action") },
            openApplication: { _, _ in fatalError("Unexpected app launch") },
            selectedText: selections,
            convertText: { try await converter.convert($0, target: $1) },
            frontmostProcess: { source.observe() }, restoreSource: { source.restore($0) }
        )
        guard let window = NSApplication.shared.windows.last(where: { $0.contentView is LauncherView }),
              let view = window.contentView as? LauncherView else { fatalError("Missing hidden launcher") }
        defer { window.contentView = nil; window.close() }

        check(window.styleMask.contains(.nonactivatingPanel), "Launcher uses a native nonactivating key panel")
        check(window.canBecomeKey && !window.canBecomeMain && !(window as! NSPanel).becomesKeyOnlyIfNeeded,
              "The panel accepts immediate keyboard focus without becoming the source app's main window")
        let cuePID = ProcessInfo.processInfo.processIdentifier
        check(LauncherPanelController.acceptsConversionContext(source: 42_424, frontmost: cuePID, launcherHasFocus: true),
              "Cue can own keyboard focus while conversion retains the original source")
        check(LauncherPanelController.acceptsConversionContext(source: 42_424, frontmost: 42_424, launcherHasFocus: false),
              "Original app ownership remains valid after the launcher closes")
        check(!LauncherPanelController.acceptsConversionContext(source: 42_424, frontmost: cuePID, launcherHasFocus: false),
              "Another Cue window cannot authorize a stale conversion")
        check(!LauncherPanelController.acceptsConversionContext(source: 42_424, frontmost: 99_999, launcherHasFocus: true),
              "A different foreground app invalidates conversion even with stale key-window state")
        check(!LauncherPanelController.acceptsConversionContext(source: 42_424, frontmost: nil, launcherHasFocus: true),
              "Unknown foreground ownership never authorizes conversion")

        controller.prepareInvocation()
        model.setQuery("st")
        let initial = await selections.counts()
        check(initial.captures == 0 && source.observations == 1, "Invocation and typing capture only source PID")
        check(!window.isVisible && !NSApplication.shared.isActive, "Fixture never shows or activates a window")
        submit(view)
        check(model.actionStatus != nil, "Conversion immediately indicates active work")
        try await waitUntil { await selections.counts().discards == 1 && model.actionStatus == nil }
        let successful = await selections.counts()
        check(successful.replacements == ["軟體"] && source.restorations == 1, "Successful conversion returns to captured source and replaces once")
        check(successful.processIDs == [42_424], "Selected text is read from the PID captured before Cue presentation")
        check(model.query.isEmpty && !window.isVisible, "Success dismisses the launcher")

        // Repeated keyboard activation must not duplicate an in-flight request.
        let captureGate = Gate()
        await selections.configure(capture: captureGate)
        controller.prepareInvocation()
        model.setQuery("st")
        submit(view)
        submit(view)
        try await waitUntil { await selections.counts().captures == 2 }
        await captureGate.open()
        try await waitUntil { await selections.counts().discards == 2 && model.actionStatus == nil }
        check(await selections.counts().replacements.count == 2, "Repeated Return does not post a second replacement")

        // A late capture from a cancelled query must not overwrite new typing.
        let lateCapture = Gate()
        await selections.configure(capture: lateCapture)
        controller.prepareInvocation()
        model.setQuery("st")
        submit(view)
        try await waitUntil { await selections.counts().captures == 3 }
        model.setQuery("new query")
        await lateCapture.open()
        try await waitUntil { await selections.counts().discards == 3 }
        check(await selections.counts().replacements.count == 2, "Cancelled capture never replaces source text")
        check(model.query == "new query" && model.launchError == nil && !window.isVisible, "Cancellation preserves current typing and focus")

        // Switching apps while the panel remains open must not steal focus back.
        await selections.configure()
        let changedSourceGate = Gate()
        await converter.setGate(changedSourceGate)
        controller.prepareInvocation()
        model.setQuery("st")
        let beforeConversion = await converter.count()
        submit(view)
        try await waitUntil { await converter.count() > beforeConversion }
        source.processID = 99_999
        await changedSourceGate.open()
        try await waitUntil { await selections.counts().discards == 4 && model.actionStatus == nil }
        check(await selections.counts().replacements.count == 2, "A changed frontmost app prevents replacement")
        check(model.launchError == nil && !window.isVisible && !NSApplication.shared.isActive, "Stale source errors never reopen or focus Cue")

        // A new invocation cancels conversion; the old completion is discarded.
        source.processID = 42_424
        let oldInvocationGate = Gate()
        await converter.setGate(oldInvocationGate)
        controller.prepareInvocation()
        model.setQuery("st")
        let beforeOld = await converter.count()
        submit(view)
        try await waitUntil { await converter.count() > beforeOld }
        controller.prepareInvocation()
        model.setQuery("ts")
        await oldInvocationGate.open()
        try await waitUntil { await selections.counts().discards == 5 }
        check(await selections.counts().replacements.count == 2, "Old invocation cannot replace after reopening")
        check(model.query == "ts" && model.launchError == nil, "Old completion cannot alter a new invocation")

        // A posted paste can require cleanup. Later requests wait for that cleanup.
        await converter.setGate(nil)
        let pasteGate = Gate()
        await selections.configure(replacement: pasteGate)
        controller.prepareInvocation()
        model.setQuery("st")
        submit(view)
        try await waitUntil { await selections.counts().replacements.count == 3 }
        controller.prepareInvocation()
        model.setQuery("ts")
        submit(view)
        try await Task.sleep(for: .milliseconds(20))
        check(await selections.counts().captures == 6, "Next request waits until prior paste cleanup completes")
        await selections.configure()
        await pasteGate.open()
        try await waitUntil { await selections.counts().discards == 7 && model.actionStatus == nil }
        let final = await selections.counts()
        check(final.replacements == ["軟體", "軟體", "軟體", "软件"], "Serialized requests use their own original conversion targets")

        // A late foreground notification must never reopen a closed panel,
        // erase new typing, resample a source, or request another activation.
        model.setQuery("preserve this query")
        let observationsBeforeFocus = source.observations
        let restorationsBeforeFocus = source.restorations
        controller.foregroundApplicationChanged(to: cuePID)
        check(model.query == "preserve this query" && source.observations == observationsBeforeFocus
              && source.restorations == restorationsBeforeFocus && !window.isVisible,
              "Late activation notification leaves a hidden launcher and its state alone")

        // Cue itself must never become the source of a new selection request.
        source.processID = cuePID
        controller.prepareInvocation()
        model.setQuery("st")
        submit(view)
        check(model.launchError == ChineseConversionText.noSelection && model.actionStatus == nil,
              "Invoking from Cue's own window does not capture Cue as the source")
        check(await selections.counts().captures == final.captures,
              "No accessibility capture occurs without an external invocation source")

        // A launcher that is no longer visible/key cannot use Cue's foreground
        // process as permission to read or restore a previously captured source.
        source.processID = 42_424
        controller.prepareInvocation()
        model.setQuery("st")
        source.processID = cuePID
        submit(view)
        try await waitUntil { model.actionStatus == nil }
        check(await selections.counts().captures == final.captures
              && source.restorations == restorationsBeforeFocus && !window.isVisible,
              "Lost launcher focus blocks capture and restoration before conversion starts")
        controller.dismiss(returnFocus: false)

        // Permission repair is a settings detour: retain the command and source,
        // but do not touch selection again merely because Settings closes.
        source.processID = 42_424
        await selections.configure(error: .permissionRequired)
        let beforePermission = await selections.counts()
        let conversionsBeforePermission = await converter.count()
        let restorationsBeforePermission = source.restorations
        var settingsVisits = 0
        var retainedPermissionContext = false
        controller.onConversionSettings = {
            settingsVisits += 1
            // Mirrors AppDelegate.prepareSettings without showing any window or
            // querying real Accessibility authorization.
            retainedPermissionContext = controller.suspendForSettings()
        }
        controller.prepareInvocation()
        model.setQuery("st")
        submit(view)
        try await waitUntil { settingsVisits == 1 && model.actionStatus == nil }
        check(retainedPermissionContext && controller.isSuspendedForSettings
              && model.query == "st" && model.selectedResult == .convertToTraditional,
              "A permission error opens feature settings without discarding the original command")
        check(controller.windowControlSource == 42_424,
              "A window-mode handoff from suspended Settings retains the original app instead of Cue")
        let denied = await selections.counts()
        check(denied.captures == beforePermission.captures + 1
              && denied.replacements == beforePermission.replacements && denied.discards == beforePermission.discards,
              "A denied capture never creates a replacement or a nonexistent session to discard")
        check(await converter.count() == conversionsBeforePermission && source.restorations == restorationsBeforePermission,
              "Permission failure does not run conversion or reactivate the source app")
        let observationsBeforePermissionReturn = source.observations
        check(controller.restoreSettingsContext() && !controller.isSuspendedForSettings
              && model.query == "st" && model.selectedResult == .convertToTraditional,
              "Returning from permission settings restores the unchanged command offscreen")
        await selections.configure()
        for _ in 0..<20 { await Task.yield() }
        check(await selections.counts().captures == denied.captures
              && source.observations == observationsBeforePermissionReturn,
              "Returning after permission repair must neither recapture selection nor resample the source")
        check(await converter.count() == conversionsBeforePermission && !controller.restoreSettingsContext(),
              "Settings return never retries conversion automatically or reuses a consumed settings context")
        check(!window.isVisible && !NSApplication.shared.isActive,
              "Permission settings lifecycle is verified without opening windows or requesting authorization")
        submit(view)
        try await waitUntil { await selections.counts().discards == denied.discards + 1 && model.actionStatus == nil }
        let afterPermissionRetry = await selections.counts()
        check(afterPermissionRetry.captures == denied.captures + 1
              && afterPermissionRetry.processIDs.last == 42_424
              && afterPermissionRetry.replacements.count == denied.replacements.count + 1
              && afterPermissionRetry.replacements.last == "軟體",
              "Only an explicit later Return retries conversion against the preserved invocation source")
        controller.onConversionSettings = nil
        controller.dismiss(returnFocus: false)

        // Reclaiming a retained launcher from another app keeps its text but
        // prepares a new selection context, rather than modifying the old form.
        model.setQuery("st")
        source.processID = 55_555
        controller.prepareInvocation(resetQuery: false)
        check(model.query == "st" && model.selectedResult == .convertToTraditional,
              "A new source context can preserve the existing launcher query and action")
        submit(view)
        try await waitUntil { await selections.counts().discards == afterPermissionRetry.discards + 1 && model.actionStatus == nil }
        check(await selections.counts().processIDs.last == 55_555,
              "Reclaimed launcher conversion targets the newly captured app, not the previous form")
        controller.dismiss(returnFocus: false)

        // Exercise the actual production actor, with bundled data, while a main
        // actor heartbeat runs. Conversion must not monopolize the UI executor.
        var heartbeat = 0
        let pulse = Task { @MainActor in
            while !Task.isCancelled {
                heartbeat += 1
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        let input = String(repeating: "软件开发使用鼠标和打印机。", count: 2_000)
        for _ in 0..<12 { _ = try await ChineseConversionEngine.shared.convert(input, to: .traditionalTaiwan) }
        pulse.cancel()
        await pulse.value
        check(heartbeat > 5, "Production conversion leaves the main actor responsive")
        await controller.finishPendingTextConversion()
        await model.prepareForTermination()
        await clipboard.prepareForTermination()
        check(!window.isVisible && !NSApplication.shared.isActive, "No real UI was shown or activated")
        print("Chinese conversion lifecycle passed: \(checks) checks; heartbeat=\(heartbeat); hidden windows and injected selections only.")
    }
}
