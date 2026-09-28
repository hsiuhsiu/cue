import AppKit
import CueCore

private final class LauncherPanel: NSPanel {
    var onToggle: (() -> Void)?
    var shortcut = LauncherShortcut.default
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Keep the direct-event fallback on the same route as native key equivalents.
            if (contentView as? LauncherView)?.handleSettingsShortcut(event) == true { return }
            if (contentView as? ClipboardView)?.handleSettingsShortcut(event) == true { return }
            if (contentView as? LauncherView)?.handleNumberShortcut(event) == true { return }
            if (contentView as? ClipboardView)?.handleNumberShortcut(event) == true { return }
            if (contentView as? ClipboardView)?.handleDeleteShortcut(event) == true { return }
            if shortcut.matches(event: event) {
                if !event.isARepeat { onToggle?() }
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
    let model: LauncherModel
    private let panel: LauncherPanel
    private var launcherView: LauncherView!
    private let clipboard: ClipboardModel
    private let performSystemAction: @MainActor (SystemAction) async throws -> Void
    private let openApplication: @MainActor (IndexedApplication, @escaping @MainActor (Error?) -> Void) -> Void
    private let selectedText: any SelectedTextAccessing
    private let convertText: @Sendable (String, ChineseConversionTarget) async throws -> String
    private let frontmostProcess: @MainActor () -> Int32?
    private let restoreSource: @MainActor (Int32) -> Bool
    private var sourceProcessID: Int32?
    private var conversionTask: Task<Void, Never>?
    private var conversionRequest = 0
    private var showingClipboard = false
    private var isDismissing = false
    private lazy var clipboardView: ClipboardView = {
        let view = ClipboardView(
            model: clipboard,
            onCopy: { [weak self] index in
                guard let self else { return }
                self.clipboard.copySelected(at: index) { [weak self] in self?.dismiss() }
            },
            onBack: { [weak self] in self?.showLauncher() }
        )
        view.onPreferredHeightChange = { [weak self] height in
            guard let self, self.showingClipboard, self.panel.contentView === self.clipboardView else { return }
            self.resizePanel(to: height)
        }
        return view
    }()
    private var preferences = LauncherPreferences()
    private var invocation = 0
    var onSettings: (() -> Void)?
    var onConversionSettings: (() -> Void)?

    init(clipboard: ClipboardModel,
         model: LauncherModel = LauncherModel(),
         performSystemAction: @escaping @MainActor (SystemAction) async throws -> Void = SystemActions.perform,
         openApplication: @escaping @MainActor (IndexedApplication, @escaping @MainActor (Error?) -> Void) -> Void = LauncherPanelController.openSystemApplication,
         selectedText: (any SelectedTextAccessing)? = nil,
         convertText: @escaping @Sendable (String, ChineseConversionTarget) async throws -> String = { text, target in
             try await ChineseConversionEngine.shared.convert(text, to: target)
         },
         frontmostProcess: @escaping @MainActor () -> Int32? = {
             NSWorkspace.shared.frontmostApplication?.processIdentifier
         },
         restoreSource: @escaping @MainActor (Int32) -> Bool = LauncherPanelController.activateSource) {
        self.clipboard = clipboard
        self.model = model
        self.performSystemAction = performSystemAction
        self.openApplication = openApplication
        self.selectedText = selectedText ?? SelectedTextService(
            beforePaste: { await clipboard.beginTransientClipboardUse() },
            afterPaste: { await clipboard.endTransientClipboardUse() }
        )
        self.convertText = convertText
        self.frontmostProcess = frontmostProcess
        self.restoreSource = restoreSource
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 56),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        super.init()
        panel.title = "Cue"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onToggle = { [weak self] in self?.toggle() }
        launcherView = LauncherView(
            model: model,
            onSubmit: { [weak self] in self?.runSelected() },
            onCancel: { [weak self] in self?.dismiss() },
            onSettings: { [weak self] in self?.openContextSettings() }
        )
        launcherView.onPreferredHeightChange = { [weak self] height in
            guard let self, !self.showingClipboard, self.panel.contentView === self.launcherView else { return }
            self.resizePanel(to: height)
        }
        panel.contentView = launcherView
        panel.initialFirstResponder = launcherView.searchField
        panel.contentView?.layoutSubtreeIfNeeded()
        model.onQueryChange = { [weak self] in self?.cancelConversion() }
    }

    func apply(_ preferences: LauncherPreferences) {
        let preferences = preferences.sanitized()
        self.preferences = preferences
        panel.shortcut = preferences.shortcut
        model.setResultLimit(preferences.maxResults)
    }

    func toggle() {
        if panel.isVisible { dismiss() } else { show() }
    }

    func show(resetQuery: Bool = true) {
        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            focusIfPresented()
            return
        }
        prepareInvocation(resetQuery: resetQuery)
        launcherView.scrollToSelection()
        let screen: NSScreen?
        switch preferences.display {
        case .pointer:
            screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main
        case .main:
            screen = NSScreen.screens.first
        }
        if let frame = screen?.visibleFrame {
            let size = NSSize(width: min(640, frame.width - 24), height: min(launcherView.preferredHeight, frame.height - 24))
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + (frame.height - size.height) * 0.65
            )
            let targetFrame = NSRect(origin: origin, size: size)
            if panel.frame != targetFrame { panel.setFrame(targetFrame, display: false) }
        }
        // Capture the source before activation. A regular key panel routes real
        // keyboard input to Cue without relying on nonactivating focus stealing.
        // The native field already exists; no delayed handoff enters typing.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(launcherView.searchField)
    }

    /// Activation can complete after the show call. Reassert only a presented
    /// launcher, without activating, reopening, or resetting a newer invocation.
    func focusIfPresented() {
        guard panel.isVisible, !isDismissing else { return }
        panel.makeKeyAndOrderFront(nil)
        // Feature settings own their focus; never target the hidden history field.
        if !showingClipboard || !clipboardView.isShowingSettings {
            panel.makeFirstResponder(showingClipboard ? clipboardView.searchField : launcherView.searchField)
        }
    }

    /// Establish an invocation independently of window presentation. This only
    /// samples the source PID; accessibility and conversion stay deferred.
    func prepareInvocation(resetQuery: Bool = true) {
        cancelConversion()
        let frontmost = frontmostProcess()
        sourceProcessID = frontmost == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        invocation += 1
        if resetQuery { model.reset() }
    }

    private func resizePanel(to preferredHeight: CGFloat) {
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let height = min(preferredHeight, (visibleFrame?.height ?? preferredHeight + 24) - 24)
        guard panel.frame.height != height else { return }
        var frame = panel.frame
        // Keep the search field anchored while results grow below it. No animation,
        // focus handoff, or deferred resize enters the typing path.
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        if let visibleFrame { frame.origin.y = max(frame.origin.y, visibleFrame.minY + 12) }
        panel.setFrame(frame, display: panel.isVisible, animate: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func dismiss(cancelConversion shouldCancel: Bool = true, returnFocus: Bool = true) {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        let returnToSource = returnFocus && panel.isVisible
            && frontmostProcess() == ProcessInfo.processInfo.processIdentifier
        let source = sourceProcessID
        if shouldCancel { cancelConversion() }
        invocation += 1
        panel.orderOut(nil)
        if showingClipboard {
            clipboard.close()
            clipboardView.closeSettings()
            showingClipboard = false
            panel.contentView = launcherView
            panel.initialFirstResponder = launcherView.searchField
        }
        model.reset()
        resizePanel(to: launcherView.preferredHeight)
        if returnToSource, let source { _ = restoreSource(source) }
    }

    private func showClipboard() {
        showingClipboard = true
        clipboard.open()
        panel.contentView = clipboardView
        panel.initialFirstResponder = clipboardView.searchField
        resizePanel(to: clipboardView.preferredHeight)
        panel.makeFirstResponder(clipboardView.searchField)
    }

    private func showLauncher() {
        clipboard.close()
        clipboardView.closeSettings()
        showingClipboard = false
        model.reset()
        panel.contentView = launcherView
        panel.initialFirstResponder = launcherView.searchField
        resizePanel(to: launcherView.preferredHeight)
        panel.makeFirstResponder(launcherView.searchField)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isDismissing, panel.isVisible else { return }
        cancelConversion()
        // The user chose another window; do not reactivate the invocation source.
        if preferences.dismissOnFocusLoss { dismiss(returnFocus: false) }
    }

    private func runSelected() {
        guard let result = model.selectedResult else { return }
        if result != .convertToTraditional && result != .convertToSimplified { cancelConversion() }
        switch result {
        case .convertToTraditional:
            runConversion(.traditionalTaiwan, resultID: result.id)
        case .convertToSimplified:
            runConversion(.simplifiedChina, resultID: result.id)
        case .chineseConversionSettings:
            dismiss(returnFocus: false)
            onConversionSettings?()
        case .updateIndex:
            guard !model.isIndexing else { return }
            let query = model.query
            Task {
                if await model.loadApplications() {
                    model.recordSuccessfulAction(resultID: result.id, query: query)
                }
            }
        case .clipboardHistory:
            let query = model.query
            showClipboard()
            model.recordSuccessfulAction(resultID: result.id, query: query)
        case .sleep:
            runSystemAction(.sleep)
        case .lockScreen:
            runSystemAction(.lockScreen)
        case .screenOff:
            runSystemAction(.screenOff)
        case .application(let application):
            launch(application)
        }
    }

    private func openContextSettings() {
        switch model.selectedResult {
        case .convertToTraditional, .convertToSimplified, .chineseConversionSettings:
            dismiss(returnFocus: false)
            onConversionSettings?()
        default:
            onSettings?()
        }
    }

    private func cancelConversion() {
        conversionTask?.cancel()
        if model.actionStatus != nil { model.actionStatus = nil }
    }

    /// Conversion keeps the original invocation target while Cue owns keyboard
    /// input. Any other foreground app invalidates the pending action.
    static func acceptsConversionContext(source: Int32, frontmost: Int32?, launcherHasFocus: Bool) -> Bool {
        frontmost == source || (frontmost == ProcessInfo.processInfo.processIdentifier && launcherHasFocus)
    }

    private func ownsConversionContext(_ source: Int32) -> Bool {
        Self.acceptsConversionContext(source: source, frontmost: frontmostProcess(),
                                      launcherHasFocus: panel.isVisible && panel.isKeyWindow)
    }

    /// Drain bounded paste acknowledgement/clipboard restoration before quitting.
    func finishPendingTextConversion() async {
        cancelConversion()
        await conversionTask?.value
    }

    private func runConversion(_ target: ChineseConversionTarget, resultID: String) {
        // Suppress repeated Return/number events while this request is pending.
        guard model.actionStatus == nil else { return }
        guard let sourceProcessID else {
            model.launchError = ChineseConversionText.noSelection
            return
        }
        let query = model.query
        let requestInvocation = invocation
        let previous = conversionTask
        previous?.cancel()
        conversionRequest += 1
        let request = conversionRequest
        model.launchError = nil
        model.actionStatus = ChineseConversionText.converting
        conversionTask = Task { [weak self, selectedText, convertText] in
            // A cancelled paste may still need acknowledgement before restoring
            // the clipboard. Serialize a later request behind that cleanup.
            await previous?.value
            guard let self else { return }
            var session: SelectedTextSession?
            var completionInvocation = requestInvocation
            do {
                try Task.checkCancellation()
                guard self.invocation == requestInvocation, self.ownsConversionContext(sourceProcessID) else {
                    throw SelectedTextError.selectionChanged
                }
                let captured = try await selectedText.capture(processID: sourceProcessID)
                session = captured
                let converted = try await convertText(captured.text, target)
                try Task.checkCancellation()
                guard self.invocation == requestInvocation,
                      self.ownsConversionContext(sourceProcessID) else {
                    throw SelectedTextError.selectionChanged
                }
                self.dismiss(cancelConversion: false, returnFocus: false)
                completionInvocation = self.invocation
                guard self.restoreSource(sourceProcessID) else {
                    throw SelectedTextError.applicationUnavailable
                }
                try await selectedText.replace(captured, with: converted)
                self.model.recordSuccessfulAction(resultID: resultID, query: query)
            } catch {
                if !(error is CancellationError), !Task.isCancelled,
                   self.invocation == completionInvocation, self.conversionRequest == request,
                   self.ownsConversionContext(sourceProcessID) {
                    self.model.actionStatus = nil
                    if (error as? SelectedTextError) == .permissionRequired {
                        self.dismiss(cancelConversion: false, returnFocus: false)
                        self.onConversionSettings?()
                    } else {
                        self.model.setQuery(query)
                        self.model.launchError = ChineseConversionText.message(for: error)
                        self.show(resetQuery: false)
                    }
                }
            }
            if let session { await selectedText.discard(session) }
            if self.conversionRequest == request {
                self.model.actionStatus = nil
                self.conversionTask = nil
            }
        }
    }

    private static func activateSource(_ processID: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated else {
            return false
        }
        if application.isActive { return true }
        return application.activate(options: [])
    }

    private func runSystemAction(_ action: SystemAction) {
        let query = model.query
        let resultID: String
        let failureMessage: String
        switch action {
        case .sleep:
            resultID = LauncherResult.sleep.id
            failureMessage = LauncherText.shared.sleepError
        case .lockScreen:
            resultID = LauncherResult.lockScreen.id
            failureMessage = LauncherText.shared.lockError
        case .screenOff:
            resultID = LauncherResult.screenOff.id
            failureMessage = LauncherText.shared.screenOffError
        }
        // Close immediately; system calls and framework loading stay off typing's
        // event path. Tests inject actions to avoid changing the Mac's state.
        dismiss()
        let actionInvocation = invocation
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performSystemAction(action)
                self.model.recordSuccessfulAction(resultID: resultID, query: query)
            } catch {
                // Never steal focus back for an old failed request after reopening.
                guard self.invocation == actionInvocation else { return }
                self.model.setQuery(query)
                self.model.launchError = failureMessage
                self.show(resetQuery: false)
            }
        }
    }

    private func launch(_ application: IndexedApplication) {
        let query = model.query
        // Acknowledge Enter immediately, independent of another app's startup time.
        dismiss(returnFocus: false)
        let launchInvocation = invocation
        let resultID = LauncherResult.application(application).id
        openApplication(application) { [weak self] error in
            guard let self else { return }
            if let error {
                guard self.invocation == launchInvocation else { return }
                self.model.setQuery(query)
                self.show(resetQuery: false)
                self.model.launchError = L10n.format(
                    LauncherText.shared.launchError, application.name, error.localizedDescription
                )
            } else {
                // A completed launch still counts if the user has already begun another search.
                self.model.recordSuccessfulAction(resultID: resultID, query: query)
            }
        }
    }

    private static func openSystemApplication(
        _ application: IndexedApplication, completion: @escaping @MainActor (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) { _, error in
            Task { @MainActor in completion(error) }
        }
    }
}
