import AppKit
import CueCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: CueSettings, applyShortcut: @escaping (LauncherShortcut) -> String?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 510, height: 420),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.title = "Cue Settings"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: CueSettingsView(
            settings: settings, applyShortcut: applyShortcut
        ))
        super.init(window: window)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CueSettingsWindow")
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
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct CueSettingsView: View {
    @ObservedObject var settings: CueSettings
    let applyShortcut: (LauncherShortcut) -> String?
    @State private var shortcutError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Open Cue") {
                    ShortcutRecorder(
                        shortcut: settings.preferences.shortcut,
                        onCapture: { shortcut in
                            guard shortcut.isValid else {
                                let message = "Use ⌘, ⌥ or ⌃ with a key. ⌘, is reserved for Settings."
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
                        .accessibilityLabel("Shortcut error: \(shortcutError)")
                }
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("Click the shortcut, then press a key with ⌘, ⌥ or ⌃. Press Esc to cancel.")
            }

            Section("Search") {
                Picker("Maximum results", selection: $settings.preferences.maxResults) {
                    ForEach(LauncherPreferences.resultLimits, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }

            Section("Window") {
                Picker("Show Cue on", selection: $settings.preferences.display) {
                    Text("Display with pointer").tag(LauncherPreferences.Display.pointer)
                    Text("Main display").tag(LauncherPreferences.Display.main)
                }
                Toggle("Dismiss when switching to another app", isOn: $settings.preferences.dismissOnFocusLoss)
            }
        }
        .formStyle(.grouped)
        .frame(width: 510, height: 420)
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
        button.setAccessibilityLabel("Open Cue keyboard shortcut")
        button.setAccessibilityHelp("Press to record a new keyboard shortcut. Escape cancels recording.")
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onCapture = onCapture
        button.onBegin = onBegin
        if !button.isRecording { button.title = shortcut.displayName }
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
        title = "Press shortcut…"
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
        title = shortcut.displayName
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
