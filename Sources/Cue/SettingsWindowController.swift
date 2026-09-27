import AppKit
import CueCore
import SwiftUI

private enum SettingsText {
    static let windowTitle = L10n.string("window.title", table: "Settings", value: "Cue Settings")
    static let openCue = L10n.string("shortcut.open_cue", table: "Settings", value: "Open Cue")
    static let invalidShortcut = L10n.string("shortcut.invalid", table: "Settings", value: "Use ⌘, ⌥ or ⌃ with a key. ⌘, is reserved for Settings.")
    static let shortcutError = L10n.string("shortcut.error", table: "Settings", value: "Shortcut error: %@")
    static let keyboardShortcut = L10n.string("shortcut.heading", table: "Settings", value: "Keyboard Shortcut")
    static let shortcutHelp = L10n.string("shortcut.help", table: "Settings", value: "Click the shortcut, then press a key with ⌘, ⌥ or ⌃. Press Esc to cancel.")
    static let search = L10n.string("search.heading", table: "Settings", value: "Search")
    static let maximumResults = L10n.string("search.maximum_results", table: "Settings", value: "Maximum results")
    static let window = L10n.string("window.heading", table: "Settings", value: "Window")
    static let showCueOn = L10n.string("window.show_on", table: "Settings", value: "Show Cue on")
    static let pointerDisplay = L10n.string("window.pointer_display", table: "Settings", value: "Display with pointer")
    static let mainDisplay = L10n.string("window.main_display", table: "Settings", value: "Main display")
    static let dismissOnFocusLoss = L10n.string("window.dismiss_on_focus_loss", table: "Settings", value: "Dismiss when switching to another app")
    static let language = L10n.string("language.heading", table: "Settings", value: "Language")
    static let appLanguage = L10n.string("language.app_language", table: "Settings", value: "App language")
    static let followSystem = L10n.string("language.follow_system", table: "Settings", value: "Follow System")
    static let languageRestart = L10n.string("language.restart", table: "Settings", value: "Reopen Cue to apply a language change.")
    static let version = L10n.string("updates.version", table: "Settings", value: "Version")
    static let automaticUpdates = L10n.string("updates.automatic_checks", table: "Settings", value: "Automatically check for updates")
    static let availableVersion = L10n.string("updates.available_version", table: "Settings", value: "Version %@ is available")
    static let checkForUpdates = L10n.string("updates.check", table: "Settings", value: "Check for Updates…")
    static let showUpdate = L10n.string("updates.show", table: "Settings", value: "Show Update…")
    static let updates = L10n.string("updates.heading", table: "Settings", value: "Updates")
    static let updatesHelp = L10n.string("updates.help", table: "Settings", value: "Checks run in the background without interrupting search. You choose when to install and restart Cue.")
    static let developmentBuild = L10n.string("updates.development_build", table: "Settings", value: "Development build")
    static let recorderLabel = L10n.string("recorder.label", table: "Settings", value: "Open Cue keyboard shortcut")
    static let recorderHelp = L10n.string("recorder.help", table: "Settings", value: "Press to record a new keyboard shortcut. Escape cancels recording.")
    static let pressShortcut = L10n.string("recorder.prompt", table: "Settings", value: "Press shortcut…")
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: CueSettings, updates: UpdateController, applyShortcut: @escaping (LauncherShortcut) -> String?) {
        let contentSize = NSSize(width: 510, height: 660)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.title = SettingsText.windowTitle
        window.contentMinSize = contentSize
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: CueSettingsView(
            settings: settings, updates: updates, applyShortcut: applyShortcut
        ))
        super.init(window: window)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CueSettingsWindow")
        // Older releases saved a shorter window; retain its position, not its old content size.
        window.setContentSize(contentSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func windowDidResignKey(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    /// Carbon consumes the active shortcut before it reaches the recorder's key events.
    func finishRecordingCurrentShortcut() -> Bool {
        guard window?.isKeyWindow == true,
              let recorder = window?.firstResponder as? ShortcutRecorderButton,
              recorder.isRecording else { return false }
        recorder.finishRecording()
        return true
    }

    func show() {
        // This is an explicit user request from a nonactivating launcher. Plain activate()
        // can leave another app active, with Settings visible but unable to receive input.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct CueSettingsView: View {
    @ObservedObject var settings: CueSettings
    @ObservedObject var updates: UpdateController
    let applyShortcut: (LauncherShortcut) -> String?
    @State private var shortcutError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(SettingsText.openCue) {
                    ShortcutRecorder(
                        shortcut: settings.preferences.shortcut,
                        onCapture: { shortcut in
                            guard shortcut.isValid else {
                                let message = SettingsText.invalidShortcut
                                shortcutError = message
                                return message
                            }
                            let error = applyShortcut(shortcut)
                            shortcutError = error
                            if error == nil { settings.preferences.shortcut = shortcut }
                            return error
                        },
                        onBegin: { shortcutError = nil }
                    )
                    .frame(width: 175, height: 26)
                }
                if let shortcutError {
                    Text(shortcutError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(L10n.format(SettingsText.shortcutError, shortcutError))
                }
            } header: {
                Text(SettingsText.keyboardShortcut)
            } footer: {
                Text(SettingsText.shortcutHelp)
            }

            Section(SettingsText.search) {
                Picker(SettingsText.maximumResults, selection: $settings.preferences.maxResults) {
                    ForEach(LauncherPreferences.resultLimits, id: \.self) { count in
                        Text(verbatim: String(count)).tag(count)
                    }
                }
            }

            Section(SettingsText.window) {
                Picker(SettingsText.showCueOn, selection: $settings.preferences.display) {
                    Text(SettingsText.pointerDisplay).tag(LauncherPreferences.Display.pointer)
                    Text(SettingsText.mainDisplay).tag(LauncherPreferences.Display.main)
                }
                Toggle(SettingsText.dismissOnFocusLoss, isOn: $settings.preferences.dismissOnFocusLoss)
            }

            Section {
                Picker(SettingsText.appLanguage, selection: $settings.language) {
                    Text(SettingsText.followSystem).tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "正體中文").tag(AppLanguage.traditionalChinese)
                }
            } header: {
                Text(SettingsText.language)
            } footer: {
                if settings.languageChangeRequiresRestart {
                    Text(SettingsText.languageRestart)
                }
            }

            Section {
                LabeledContent(SettingsText.version, value: appVersion)
                Toggle(SettingsText.automaticUpdates, isOn: Binding(
                    get: { updates.automaticChecksEnabled },
                    set: { updates.setAutomaticChecksEnabled($0) }
                ))
                .disabled(updates.startupError != nil)
                HStack {
                    if let version = updates.availableVersion {
                        Text(L10n.format(SettingsText.availableVersion, version))
                            .font(.callout)
                    }
                    Spacer()
                    Button(updates.availableVersion == nil ? SettingsText.checkForUpdates : SettingsText.showUpdate) {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                }
                if let error = updates.startupError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(SettingsText.updates)
            } footer: {
                Text(SettingsText.updatesHelp)
            }
        }
        .formStyle(.grouped)
        .frame(width: 510, height: 660)
    }

    private var appVersion: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return SettingsText.developmentBuild
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "\(version) (\(build))"
        }
        return version
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: LauncherShortcut
    let onCapture: (LauncherShortcut) -> String?
    let onBegin: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        button.target = button
        button.action = #selector(ShortcutRecorderButton.beginRecording)
        button.setAccessibilityLabel(SettingsText.recorderLabel)
        button.setAccessibilityHelp(SettingsText.recorderHelp)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onCapture = onCapture
        button.onBegin = onBegin
        if !button.isRecording { button.title = shortcut.localizedDisplayName }
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var shortcut = LauncherShortcut.default
    var onCapture: ((LauncherShortcut) -> String?)?
    var onBegin: (() -> Void)?
    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        if isRecording {
            finishRecording()
            return
        }
        window?.makeFirstResponder(self)
        isRecording = true
        title = SettingsText.pressShortcut
        onBegin?()
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 {
            finishRecording()
            return
        }
        var modifiers: LauncherShortcut.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        let proposed = LauncherShortcut(
            keyCode: UInt32(event.keyCode), modifiers: modifiers,
            key: Self.label(for: event)
        )
        // Registration also validates saved values, and returns a user-facing error.
        if onCapture?(proposed) == nil, proposed.isValid {
            shortcut = proposed
            finishRecording()
        }
    }

    fileprivate func finishRecording() {
        isRecording = false
        title = shortcut.localizedDisplayName
    }

    private static func label(for event: NSEvent) -> String {
        let keyNames: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "⌫", 76: "Enter",
            114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20",
        ]
        return keyNames[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
    }
}
