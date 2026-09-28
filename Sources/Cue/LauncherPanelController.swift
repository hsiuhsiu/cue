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
    private var showingClipboard = false
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

    init(clipboard: ClipboardModel,
         model: LauncherModel = LauncherModel(),
         performSystemAction: @escaping @MainActor (SystemAction) async throws -> Void = SystemActions.perform,
         openApplication: @escaping @MainActor (IndexedApplication, @escaping @MainActor (Error?) -> Void) -> Void = LauncherPanelController.openSystemApplication) {
        self.clipboard = clipboard
        self.model = model
        self.performSystemAction = performSystemAction
        self.openApplication = openApplication
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 56),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
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
            onSettings: { [weak self] in self?.onSettings?() }
        )
        launcherView.onPreferredHeightChange = { [weak self] height in
            guard let self, !self.showingClipboard, self.panel.contentView === self.launcherView else { return }
            self.resizePanel(to: height)
        }
        panel.contentView = launcherView
        panel.initialFirstResponder = launcherView.searchField
        panel.contentView?.layoutSubtreeIfNeeded()
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
            panel.makeKeyAndOrderFront(nil)
            // Feature settings own their focus; never target the hidden history field.
            if !showingClipboard || !clipboardView.isShowingSettings {
                panel.makeFirstResponder(showingClipboard ? clipboardView.searchField : launcherView.searchField)
            }
            return
        }
        invocation += 1
        if resetQuery { model.reset() }
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
        // The native field already exists: no SwiftUI layout or next-turn focus handoff.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(launcherView.searchField)
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

    func dismiss() {
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
        if preferences.dismissOnFocusLoss, panel.isVisible { dismiss() }
    }

    private func runSelected() {
        guard let result = model.selectedResult else { return }
        switch result {
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
        case .application(let application):
            launch(application)
        }
    }

    private func runSystemAction(_ action: SystemAction) {
        let query = model.query
        let resultID = action == .sleep ? LauncherResult.sleep.id : LauncherResult.lockScreen.id
        // Close immediately; system calls and framework loading stay off typing's
        // event path. The injected action also lets tests avoid sleeping/locking.
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
                self.model.launchError = action == .sleep ? LauncherText.shared.sleepError : LauncherText.shared.lockError
                self.show(resetQuery: false)
            }
        }
    }

    private func launch(_ application: IndexedApplication) {
        let query = model.query
        // Acknowledge Enter immediately, independent of another app's startup time.
        dismiss()
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
