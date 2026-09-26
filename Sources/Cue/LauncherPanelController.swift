import AppKit
import Carbon
import CueCore

private final class LauncherPanel: NSPanel {
    var onToggle: (() -> Void)?
    var onSettings: (() -> Void)?
    var shortcut = LauncherShortcut.default
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == UInt16(kVK_ANSI_Comma), modifiers == .command {
                if !event.isARepeat { onSettings?() }
                return
            }
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
    let model = LauncherModel()
    private let panel: LauncherPanel
    private var launcherView: LauncherView!
    private var preferences = LauncherPreferences()
    private var invocation = 0
    var onSettings: (() -> Void)?

    override init() {
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
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
        panel.onSettings = { [weak self] in self?.onSettings?() }
        launcherView = LauncherView(
            model: model,
            onSubmit: { [weak self] in self?.runSelected() },
            onCancel: { [weak self] in self?.dismiss() },
            onSettings: { [weak self] in self?.onSettings?() }
        )
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
            panel.makeFirstResponder(launcherView.searchField)
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
            let size = NSSize(width: min(680, frame.width - 32), height: min(420, frame.height - 32))
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

    func dismiss() {
        invocation += 1
        panel.orderOut(nil)
        model.reset()
    }

    func windowDidResignKey(_ notification: Notification) {
        if preferences.dismissOnFocusLoss, panel.isVisible { dismiss() }
    }

    private func runSelected() {
        guard let result = model.selectedResult else { return }
        switch result {
        case .updateIndex:
            Task { await model.loadApplications() }
        case .application(let application):
            launch(application)
        }
    }

    private func launch(_ application: IndexedApplication) {
        let query = model.query
        // Acknowledge Enter immediately, independent of another app's startup time.
        dismiss()
        let launchInvocation = invocation
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) {
            [weak self] _, error in
            Task { @MainActor in
                guard let self, let error, self.invocation == launchInvocation else { return }
                self.model.setQuery(query)
                self.show(resetQuery: false)
                self.model.launchError = "Couldn’t open \(application.name): \(error.localizedDescription)"
            }
        }
    }
}
