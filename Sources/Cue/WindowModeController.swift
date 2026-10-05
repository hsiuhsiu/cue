import AppKit
import CueCore

/// In-memory session coordination; neither input routing nor drawing performs AX work.
@MainActor
final class WindowModeModel {
    private let service: any WindowControlling
    private let screens: () -> [WindowScreen]
    private var work: Task<Void, Never>?
    private var queue: [WindowAction] = []
    private(set) var sessionID: UUID?
    private(set) var snapshot: WindowControlSnapshot?
    private(set) var error: WindowControlError?
    private(set) var isBusy = false
    var canPerformActions: Bool {
        guard sessionID != nil else { return false }
        // An initial capture may still accept queued input. A lost permission or
        // target requires a fresh invocation; no action is replayed after recovery.
        switch error {
        case .permissionRequired, .noTarget, .applicationUnavailable, .sessionExpired, .unverified:
            return false
        default:
            return error == nil || snapshot != nil
        }
    }
    var onChange: (() -> Void)?
    var onFinished: ((WindowAction) -> Void)?

    init(service: any WindowControlling, screens: @escaping () -> [WindowScreen]) {
        self.service = service; self.screens = screens
    }

    func start(processIdentifier: Int32) {
        cancel()
        let session = UUID()
        sessionID = session; isBusy = true; onChange?()
        let displays = screens()
        work = Task { [weak self, service] in
            do {
                let result = try await service.capture(processIdentifier: processIdentifier, screens: displays, sessionID: session)
                guard let self, !Task.isCancelled, self.sessionID == session else { return }
                self.snapshot = result; self.isBusy = false; self.work = nil
                self.onChange?(); self.drain()
            } catch {
                self?.failed(error, session: session)
            }
        }
    }

    func perform(_ action: WindowAction) {
        guard canPerformActions, queue.count < 8 else { return }
        // Ignore repeated identical queued commands, without delaying the first one.
        if queue.last != action { queue.append(action) }
        drain()
    }

    private func drain() {
        guard !isBusy, snapshot != nil, let session = sessionID, !queue.isEmpty else { return }
        let action = queue.removeFirst()
        let displays = screens()
        isBusy = true; error = nil; onChange?()
        work = Task { [weak self, service] in
            do {
                let result = try await service.apply(action, screens: displays, sessionID: session)
                guard let self, !Task.isCancelled, self.sessionID == session else { return }
                self.snapshot = result; self.isBusy = false; self.work = nil
                self.onChange?()
                if self.queue.isEmpty { self.onFinished?(action) }
                else { self.drain() }
            } catch {
                self?.failed(error, session: session)
            }
        }
    }

    private func failed(_ failure: Error, session: UUID) {
        guard sessionID == session, !(failure is CancellationError) else { return }
        queue.removeAll(keepingCapacity: true); work = nil; isBusy = false
        error = failure as? WindowControlError ?? .operationFailed
        onChange?()
    }

    func cancel() {
        if let sessionID { service.cancel(sessionID: sessionID) }
        sessionID = nil; work?.cancel(); work = nil
        queue.removeAll(keepingCapacity: true); snapshot = nil; error = nil; isBusy = false
        onChange?()
    }
}

private enum WindowModeText {
    static func s(_ key: String, _ value: String) -> String { L10n.string(key, table: "WindowMode", value: value) }
    static let title = s("title", "Window Controls")
    static let settings = s("settings", "Window Settings")
    static let loading = s("loading", "Getting the current window…")
    static let applying = s("applying", "Adjusting window…")
    static let ready = s("ready", "Choose a layout or use the keyboard.")
    static let fill = s("fill", "Fill")
    static let center = s("center", "Center")
    static let restore = s("restore", "Restore")
    static let halves = s("halves", "Half screen")
    static let displays = s("displays", "Move to display")
    static let presets = s("presets", "Add 1–9 layouts in Window Settings.")
    static let accessibility = s("accessibility", "Open Permission Guide  ↵")
    static let noTarget = s("noTarget", "Select a window in another app, then try again.")
    static let permission = s("permission", "Cue needs macOS Accessibility access to adjust windows. Open the guide to grant access or fix an existing permission.")
    static let unsupported = s("unsupported", "This window does not support these adjustments.")
    static let minimized = s("minimized", "Restore the minimized window first.")
    static let fullScreen = s("fullScreen", "Leave macOS full screen before adjusting this window.")
    static let readOnly = s("readOnly", "This window cannot be moved.")
    static let cannotResize = s("cannotResize", "This window has a fixed size. Try Center or moving displays.")
    static let unavailable = s("unavailable", "The original window is no longer available. Invoke Window Controls again.")
    static let noScreen = s("noScreen", "No usable display is available.")
    static let noAdjacent = s("noAdjacent", "There is no display in that direction.")
    static let noRestore = s("noRestore", "There is no previous Cue layout to restore for this window.")
    static let invalidPreset = s("invalidPreset", "This layout is invalid. Edit it in Window Settings.")
    static let timeout = s("timeout", "The app did not respond in time. Try again.")
    static let failed = s("failed", "Couldn’t adjust this window. Try again.")
    static let unverified = s("unverified", "Couldn’t confirm the window’s final position. Invoke Window Controls again.")
    static let constrained = s("constrained", "The app limited the requested size or position.")
    static let partial = s("partial", "Only part of the adjustment succeeded. Tab can restore the previous layout.")
    static let adjusted = s("adjusted", "The previous display is unavailable; restored on the current display.")

    static func message(for error: WindowControlError) -> String {
        switch error {
        case .permissionRequired: permission
        case .noTarget: noTarget
        case .unsupportedWindow: unsupported
        case .minimized: minimized
        case .fullScreen: fullScreen
        case .readOnly: readOnly
        case .cannotResize: cannotResize
        case .applicationUnavailable, .sessionExpired: unavailable
        case .noScreen: noScreen
        case .noAdjacentScreen: noAdjacent
        case .nothingToRestore: noRestore
        case .invalidPreset: invalidPreset
        case .timedOut: timeout
        case .operationFailed: failed
        case .unverified: unverified
        }
    }
}

/// Normal key panel, like the launcher: focus is acquired immediately, without an event tap.
private final class WindowModePanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
final class WindowModeController: NSObject, NSWindowDelegate {
    let model: WindowModeModel
    private let preferences: WindowControlPreferences
    private let panel: WindowModePanel
    private let content = WindowModeView()
    private var source: NSRunningApplication?
    private var hiding = false
    private var observers: [NSObjectProtocol] = []
    private(set) var suspendedForSettings = false
    private var savedPreset: WindowPreset?
    var onSettings: (() -> Void)?
    var isVisible: Bool { panel.isVisible }
    var targetProcessIdentifier: Int32? { source?.processIdentifier }

    init(preferences: WindowControlPreferences) {
        self.preferences = preferences
        model = WindowModeModel(service: WindowControlService(), screens: Self.screenSnapshot)
        panel = WindowModePanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 330),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none; panel.hidesOnDeactivate = false
        panel.delegate = self; panel.contentView = content
        panel.onKey = { [weak self] in self?.handle($0) ?? false }
        content.onAction = { [weak self] in self?.model.perform($0) }
        content.onSettings = { [weak self] in self?.onSettings?() }
        model.onChange = { [weak self] in self?.refresh() }
        model.onFinished = { [weak self] action in
            guard let self, !self.preferences.snapshot.keepModeOpen else { return }
            // Keep constraints/partial-success notices visible instead of hiding errors.
            guard self.model.snapshot?.notice == nil else { return }
            if case .move = action { return }
            self.dismiss(returnFocus: true)
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isVisible == true { self?.dismiss(returnFocus: false) } }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(returnFocus: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, let source = self.source, !source.isTerminated else { return }
                // Discard queued geometry from the old topology. No automatic replay.
                self.model.start(processIdentifier: source.processIdentifier)
            }
        })
    }

    func toggle(sourceProcessIdentifier: Int32? = nil) {
        if isVisible { dismiss(returnFocus: true) }
        else { show(sourceProcessIdentifier: sourceProcessIdentifier) }
    }

    func show(sourceProcessIdentifier: Int32? = nil) {
        guard preferences.snapshot.enabled else { onSettings?(); return }
        let candidate = sourceProcessIdentifier.map { NSRunningApplication(processIdentifier: $0) }
            ?? NSWorkspace.shared.frontmostApplication
        source = candidate?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : candidate
        suspendedForSettings = false; savedPreset = nil
        content.target.stringValue = source?.localizedName ?? WindowModeText.title
        content.setPresets(preferences.snapshot.presets)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        }
        if let source, !source.isTerminated { model.start(processIdentifier: source.processIdentifier) }
        else { model.cancel(); content.status.stringValue = WindowModeText.noTarget }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(content)
    }

    func focusIfPresented() {
        guard isVisible, !hiding else { return }
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(content)
    }

    func dismiss(returnFocus: Bool) {
        guard !hiding else { return }
        hiding = true
        let shouldReturn = returnFocus && isVisible && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        suspendedForSettings = false; savedPreset = nil
        model.cancel(); panel.orderOut(nil)
        hiding = false
        if shouldReturn, let source, !source.isTerminated { source.activate(options: []) }
    }

    func suspendForSettings() {
        guard isVisible else { return }
        savedPreset = presetForCurrentWindow()
        suspendedForSettings = true; hiding = true
        model.cancel(); panel.orderOut(nil); hiding = false
    }

    func resumeAfterSettings() {
        guard suspendedForSettings else { return }
        suspendedForSettings = false
        guard preferences.snapshot.enabled, let source, !source.isTerminated else { return }
        show(sourceProcessIdentifier: source.processIdentifier)
    }

    func presetForCurrentWindow() -> WindowPreset? {
        if suspendedForSettings { return savedPreset }
        guard !model.isBusy, model.error == nil, let state = model.snapshot else { return nil }
        return WindowGeometry.preset(from: state.frame, on: state.screen, slot: 1, name: "Layout")
    }

    func settingsDidChange() {
        content.setPresets(preferences.snapshot.presets)
        if !preferences.snapshot.enabled { dismiss(returnFocus: false) }
    }

    func windowDidResignKey(_ notification: Notification) {
        if !hiding, isVisible { dismiss(returnFocus: false) }
    }

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        // Every key event belongs to this visible mode. Do not dispatch it to the source app.
        if event.isARepeat { return true }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53, flags.isEmpty { dismiss(returnFocus: true); return true }
        if event.keyCode == 43, flags == .command { onSettings?(); return true }
        if Self.opensPermissionGuide(for: event, error: model.error) { onSettings?(); return true }
        if preferences.snapshot.shortcut.matches(event: event) { dismiss(returnFocus: true); return true }
        if let action = Self.action(for: event, presets: preferences.snapshot.presets) { model.perform(action); return true }
        // Preserve macOS switching shortcuts and native menu handling.
        return flags.contains(.command) || flags.contains(.control) ? false : true
    }

    static func opensPermissionGuide(for event: NSEvent, error: WindowControlError?) -> Bool {
        error == .permissionRequired && event.type == .keyDown && !event.isARepeat
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            && (event.keyCode == 36 || event.keyCode == 76)
    }

    static func action(for event: NSEvent, presets: [WindowPreset]) -> WindowAction? {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let direction: WindowDirection? = switch event.keyCode {
        case 123: .left; case 124: .right; case 125: .down; case 126: .up; default: nil
        }
        if let direction, flags == .option { return .half(direction) }
        if let direction, flags == .command { return .move(direction) }
        guard flags.isEmpty else { return nil }
        switch event.keyCode {
        case 36, 76: return .fill
        case 49: return .center
        case 48: return .restore
        default:
            guard let index = CueKeyboardShortcut.resultIndex(keyCode: UInt32(event.keyCode), characters: event.charactersIgnoringModifiers),
                  let preset = presets.first(where: { $0.slot == index + 1 }) else { return nil }
            return .preset(preset)
        }
    }

    static func screenSnapshot() -> [WindowScreen] {
        let screens = NSScreen.screens
        guard let primary = screens.first?.frame else { return [] }
        return screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return WindowScreen(id: id.uint32Value,
                frame: WindowGeometry.accessibilityFrame(fromAppKit: screen.frame, primaryFrame: primary),
                visibleFrame: WindowGeometry.accessibilityFrame(fromAppKit: screen.visibleFrame, primaryFrame: primary))
        }
    }

    private func refresh() {
        content.update(from: model)
        content.layoutSubtreeIfNeeded()
        let height = content.preferredHeight
        if abs(panel.frame.height - height) > 0.5 {
            var frame = panel.frame
            frame.origin.y = frame.maxY - height; frame.size.height = height
            panel.setFrame(frame, display: isVisible, animate: false)
        }
    }
}

/// Small geometric preview only; no screenshots, screen recording or AX inspection.
final class WindowGeometryPreview: NSView {
    var snapshot: WindowControlSnapshot? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let area = snapshot?.screen.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = min((bounds.width - 24) / area.width, (bounds.height - 12) / area.height)
        let screen = CGRect(x: (bounds.width - area.width * scale) / 2, y: 6, width: area.width * scale, height: area.height * scale)
        NSColor.quaternaryLabelColor.setFill(); NSBezierPath(roundedRect: screen, xRadius: 5, yRadius: 5).fill()
        guard let frame = snapshot?.frame else { return }
        let visible = frame.intersection(area)
        guard !visible.isNull else { return }
        let rect = CGRect(x: screen.minX + (visible.minX - area.minX) * scale,
                          y: screen.minY + (visible.minY - area.minY) * scale,
                          width: visible.width * scale, height: visible.height * scale)
        NSColor.systemBlue.withAlphaComponent(0.18).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        path.fill(); NSColor.systemBlue.setStroke(); path.lineWidth = 1.2; path.stroke()
    }
}

final class WindowModeView: NSView {
    let target = NSTextField(labelWithString: WindowModeText.title)
    let status = NSTextField(wrappingLabelWithString: WindowModeText.ready)
    let preview = WindowGeometryPreview()
    let permissionGuide = NSButton(title: WindowModeText.accessibility, target: nil, action: nil)
    private let presetRow = NSStackView()
    private let stack = NSStackView()
    var preferredHeight: CGFloat { ceil(stack.fittingSize.height) + 28 }
    private var buttonActions: [ObjectIdentifier: (button: NSButton, action: WindowAction)] = [:]
    private(set) var canPerformActions = false {
        didSet {
            guard canPerformActions != oldValue else { return }
            for item in buttonActions.values { item.button.isEnabled = canPerformActions }
        }
    }
    var onAction: ((WindowAction) -> Void)?
    var onSettings: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let backdrop = LauncherBackdrop(frame: .zero)
        backdrop.translatesAutoresizingMaskIntoConstraints = false; addSubview(backdrop)
        NSLayoutConstraint.activate([backdrop.leadingAnchor.constraint(equalTo: leadingAnchor), backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     backdrop.topAnchor.constraint(equalTo: topAnchor), backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                                     stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                                     stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
                                     stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)])
        target.font = .systemFont(ofSize: 18, weight: .semibold); target.lineBreakMode = .byTruncatingTail
        let settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: WindowModeText.settings)!, target: self, action: #selector(openSettings))
        settings.bezelStyle = .inline; settings.toolTip = WindowModeText.settings
        let header = NSStackView(views: [target, NSView(), settings]); header.orientation = .horizontal
        stack.addArrangedSubview(header); header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(preview); preview.heightAnchor.constraint(equalToConstant: 90).isActive = true
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status); status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.heightAnchor.constraint(equalToConstant: 32).isActive = true
        // Use the same feature-settings route as the gear so the controller
        // suspends the source session before the permission guide opens.
        permissionGuide.target = self; permissionGuide.action = #selector(openSettings); permissionGuide.bezelStyle = .rounded
        permissionGuide.isHidden = true; stack.addArrangedSubview(permissionGuide)
        let halves = row(label: WindowModeText.halves, commands: [(.half(.left), "⌥←"), (.half(.up), "⌥↑"), (.half(.down), "⌥↓"), (.half(.right), "⌥→")])
        let displays = row(label: WindowModeText.displays, commands: [(.move(.left), "⌘←"), (.move(.up), "⌘↑"), (.move(.down), "⌘↓"), (.move(.right), "⌘→")])
        let basic = row(label: nil, commands: [(.fill, WindowModeText.fill + "  ↵"), (.center, WindowModeText.center + "  ␣"), (.restore, WindowModeText.restore + "  ⇥")])
        for row in [halves, displays, basic] { stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        presetRow.orientation = .horizontal; presetRow.spacing = 5
        stack.addArrangedSubview(presetRow); presetRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        setPresets([])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func row(label: String?, commands: [(WindowAction, String)]) -> NSStackView {
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 7
        if let label {
            let title = NSTextField(labelWithString: label); title.font = .systemFont(ofSize: 12)
            row.addArrangedSubview(title); title.widthAnchor.constraint(equalToConstant: 125).isActive = true
        }
        for (action, title) in commands {
            let button = NSButton(title: title, target: self, action: #selector(performAction(_:)))
            button.font = .systemFont(ofSize: 13, weight: .medium); button.bezelStyle = .rounded
            button.isEnabled = canPerformActions
            buttonActions[ObjectIdentifier(button)] = (button, action); row.addArrangedSubview(button)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        if label == nil { row.distribution = .fillEqually }
        return row
    }

    func setPresets(_ presets: [WindowPreset]) {
        for view in presetRow.arrangedSubviews {
            buttonActions.removeValue(forKey: ObjectIdentifier(view))
            presetRow.removeArrangedSubview(view); view.removeFromSuperview()
        }
        if presets.isEmpty {
            let label = NSTextField(labelWithString: WindowModeText.presets)
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            presetRow.addArrangedSubview(label)
        } else {
            for preset in presets {
                let button = NSButton(title: String(preset.slot), target: self, action: #selector(performAction(_:)))
                button.bezelStyle = .rounded; button.toolTip = preset.name
                button.setAccessibilityLabel("\(preset.slot) · \(preset.name)")
                button.isEnabled = canPerformActions
                buttonActions[ObjectIdentifier(button)] = (button, .preset(preset)); presetRow.addArrangedSubview(button)
            }
        }
    }
    func update(from model: WindowModeModel) {
        preview.snapshot = model.snapshot
        canPerformActions = model.canPerformActions
        permissionGuide.isHidden = model.error != .permissionRequired
        if let error = model.error { status.stringValue = WindowModeText.message(for: error) }
        else if model.isBusy { status.stringValue = model.snapshot == nil ? WindowModeText.loading : WindowModeText.applying }
        else if let notice = model.snapshot?.notice {
            status.stringValue = switch notice {
            case .constrained: WindowModeText.constrained
            case .partialSuccess: WindowModeText.partial
            case .restoreAdjusted: WindowModeText.adjusted
            }
        } else { status.stringValue = model.sessionID == nil ? WindowModeText.noTarget : WindowModeText.ready }
    }

    @objc private func performAction(_ sender: NSButton) {
        guard canPerformActions, let item = buttonActions[ObjectIdentifier(sender)] else { return }
        onAction?(item.action)
    }
    @objc private func openSettings() { onSettings?() }
}
