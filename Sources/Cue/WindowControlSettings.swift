import AppKit
@preconcurrency import ApplicationServices
import Combine
import CueCore
import SwiftUI

enum WindowSettingsText {
    static func text(_ key: String, _ fallback: String) -> String {
        L10n.string(key, table: "WindowSettings", value: fallback)
    }
    static let title = text("title", "Window Settings")
    static let enable = text("enable", "Enable window controls")
    static let shortcut = text("shortcut", "Open window controls")
    static let shortcutHelp = text("shortcut.help", "Click the shortcut, then press a key with ⌘, ⌥ or ⌃. Esc cancels recording.")
    static let invalidShortcut = text("shortcut.invalid", "Choose a shortcut that is not used by Cue, window actions, or standard editing.")
    static let keepOpen = text("keep_open", "Keep window controls open after an action")
    static let keepOpenHelp = text("keep_open.help", "When off, resizing, centering, and restoring close the panel. Moving to another display keeps it open so you can resize next.")
    static let accessHelp = text("access.help", "Window controls use macOS Accessibility permission. Everything stays on this Mac; no network access is needed.")
    static let accessTitle = text("access.title", "Accessibility Permission")
    static let accessRequired = text("access.required", "Permission required")
    static let accessEnabled = text("access.enabled", "Permission enabled")
    static let accessUnchecked = text("access.unchecked", "Not checked yet")
    static let accessPurpose = text("access.purpose", "Allow Cue to move and resize windows in other apps. All window adjustments stay on this Mac.")
    static let accessSetup = text("access.setup", "Open System Settings → Privacy & Security → Accessibility (called Device Control and Data Access on some macOS versions), then enable Cue.")
    static let accessOpen = text("access.open", "Open Accessibility Settings…")
    static let accessCheck = text("access.check", "Check Again")
    static let accessContinue = text("access.continue", "After permission is enabled, return to the window you want to adjust and press %@.")
    static let accessEnableFirst = text("access.enable_first", "Turn on Enable window controls above, then return to the window you want to adjust and press %@.")
    static let accessRepairTitle = text("access.repair.title", "Cue is already on, but permission is still required")
    static let accessRepairHelp = text("access.repair.help", "After an update, macOS may still recognize an older copy. First turn Cue off and on in that list. If Check Again still says permission is required, remove only the old Cue entry with −, then use + to add the current app shown below and enable it. Cue never resets or grants permission automatically.")
    static let accessCurrentApp = text("access.current_app", "Currently running app")
    static let accessReveal = text("access.reveal", "Show This Cue in Finder")
    static let accessOpenFailed = text("access.open_failed", "Couldn’t open the permission page. Open System Settings manually, choose Privacy & Security, then Accessibility or Device Control and Data Access.")
    static let presets = text("presets", "Number Presets")
    static let presetsHelp = text("presets.help", "Use 1–9 in window mode. Positions and sizes are percentages of the current display’s usable area, so they work on other displays too.")
    static let emptySlot = text("preset.empty", "Not assigned")
    static let add = text("preset.add", "Add…")
    static let edit = text("preset.edit", "Edit…")
    static let delete = text("preset.delete", "Delete")
    static let editTitle = text("editor.title", "Edit Number Preset")
    static let name = text("editor.name", "Name")
    static let x = text("editor.x", "From left")
    static let y = text("editor.y", "From top")
    static let width = text("editor.width", "Width")
    static let height = text("editor.height", "Height")
    static let geometryHelp = text("editor.help", "Enter percentages from 0 to 100. The whole rectangle must fit within the usable area. This preview does not move a real window.")
    static let useCurrent = text("editor.current", "Use Target Window’s Position")
    static let currentUnavailable = text("editor.no_target", "Open window controls on the window you want, then open Window Settings to use its position.")
    static let invalidPreset = text("editor.invalid", "Use a name of 1–80 characters and a rectangle that fits within 0–100%, with positive width and height.")
    static let preview = text("editor.preview", "Window position preview")
    static let save = text("save", "Save Preset")
    static let cancel = text("cancel", "Cancel")
    static let done = text("done", "Done")
    static let loading = text("loading", "Loading window settings…")
    static let loadError = text("error.load", "Couldn’t read window settings. The saved file has been left untouched. Check its format and folder permissions, then retry.")
    static let saveError = text("error.save", "Couldn’t save window settings. Your changes work for this session; check available disk space and folder permissions, then retry.")
    static let retry = text("retry", "Retry")
    static let controls = text("controls", "Keyboard Controls")
    static let half = text("controls.half", "Half screen")
    static let display = text("controls.display", "Move to another display")
    static let fill = text("controls.fill", "Fill usable area")
    static let center = text("controls.center", "Center")
    static let restore = text("controls.restore", "Restore previous position")
    static let close = text("controls.close", "Close window controls")
}

/// Permission status is sampled only on an explicit UI/lifecycle event. The
/// initializer performs no system lookup and never prompts or changes access.
@MainActor
final class WindowAccessibilityAccess: ObservableObject {
    enum Status: Equatable { case unchecked, required, enabled }
    @Published private(set) var status: Status = .unchecked
    @Published private(set) var openingError: String?
    @Published var showsRepairHelp = false
    let currentAppURL: URL
    private let checker: () -> Bool
    private let openAction: () -> Bool
    private let revealAction: () -> Void

    init(checker: @escaping () -> Bool = { AXIsProcessTrusted() },
         openSettings: @escaping () -> Bool = {
             // This closure runs only from the explicit Open button. Let macOS
             // list this running copy; the person still owns the permission grant.
             _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
             guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
             return NSWorkspace.shared.open(url)
         },
         currentAppURL: URL = Bundle.main.bundleURL,
         revealCurrentApp: (() -> Void)? = nil) {
        self.checker = checker; self.openAction = openSettings; self.currentAppURL = currentAppURL
        self.revealAction = revealCurrentApp ?? { NSWorkspace.shared.activateFileViewerSelecting([currentAppURL]) }
    }

    func refresh() {
        let updated: Status = checker() ? .enabled : .required
        if status != updated { status = updated }
        if updated == .enabled { openingError = nil }
    }
    func openSettings() { openingError = openAction() ? nil : WindowSettingsText.accessOpenFailed }
    func revealCurrentApp() { revealAction() }
}

/// A portable, versioned value. No machine-specific display IDs or window titles.
struct WindowControlConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let defaultShortcut = LauncherShortcut(keyCode: 46, modifiers: .option, key: "M")
    let version: Int
    let enabled: Bool
    let shortcut: LauncherShortcut
    let keepModeOpen: Bool
    let presets: [WindowPreset]

    init(version: Int = currentVersion, enabled: Bool = true,
         shortcut: LauncherShortcut = defaultShortcut, keepModeOpen: Bool = false,
         presets: [WindowPreset] = []) {
        self.version = version
        self.enabled = enabled
        self.shortcut = shortcut
        self.keepModeOpen = keepModeOpen
        self.presets = presets.sorted { $0.slot < $1.slot }
    }

    static func isValidShortcut(_ value: LauncherShortcut) -> Bool {
        // A window-mode activation key must not consume a half-screen command.
        value.isValid && !(value.modifiers == .option && (123...126).contains(value.keyCode))
    }

    var isValid: Bool {
        version == Self.currentVersion && Self.isValidShortcut(shortcut)
            && presets.count <= 9 && Set(presets.map(\.slot)).count == presets.count
            && presets.allSatisfy(\.isValid)
    }

    func replacing(enabled: Bool? = nil, shortcut: LauncherShortcut? = nil,
                   keepModeOpen: Bool? = nil, presets: [WindowPreset]? = nil) -> Self {
        Self(version: version, enabled: enabled ?? self.enabled,
             shortcut: shortcut ?? self.shortcut, keepModeOpen: keepModeOpen ?? self.keepModeOpen,
             presets: presets ?? self.presets)
    }
}

private actor WindowConfigurationStore {
    let fileURL: URL
    private var writtenRevision: UInt64 = 0
    private static let maximumBytes = 64 * 1_024
    private enum Failure: Error { case invalidFile }

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() throws -> WindowControlConfiguration {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .init()
        }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw Failure.invalidFile }
        let value = try JSONDecoder().decode(WindowControlConfiguration.self, from: data)
        guard value.isValid else { throw Failure.invalidFile }
        return value.replacing() // Canonical slot order, including externally edited files.
    }

    func save(_ value: WindowControlConfiguration, revision: UInt64) throws {
        // Task scheduling need not be FIFO. Never let an older edit overwrite a newer one.
        guard revision >= writtenRevision else { return }
        guard value.isValid else { throw Failure.invalidFile }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumBytes else { throw Failure.invalidFile }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        writtenRevision = revision
    }
}

@MainActor
final class WindowControlPreferences: ObservableObject {
    // Stay inactive until the file is validated and the hotkey is registered.
    @Published private(set) var snapshot = WindowControlConfiguration(enabled: false)
    @Published private(set) var hasLoaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var persistenceError: String?
    @Published private(set) var runtimeError: String?
    /// Register/release the hotkey atomically before a configuration is accepted.
    /// A non-nil message leaves the previous configuration intact.
    var applyConfiguration: ((WindowControlConfiguration) -> String?)?
    var onChange: ((WindowControlConfiguration) -> Void)?
    let fileURL: URL
    private let store: WindowConfigurationStore
    private var revision: UInt64 = 0
    private var pendingWrite: Task<Void, Never>?
    private var isLoading = false

    init(fileURL: URL? = nil) {
        let defaultURL = URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yyhsiu.cue", isDirectory: true)
            .appendingPathComponent("WindowControls", isDirectory: true)
            .appendingPathComponent("settings.json")
        self.fileURL = fileURL ?? defaultURL
        store = WindowConfigurationStore(fileURL: self.fileURL)
    }

    /// Call once after wiring callbacks. File work happens on the store actor.
    func load() async {
        guard !isLoading, !hasLoaded || loadError != nil else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let saved = try await store.load()
            loadError = nil
            runtimeError = applyConfiguration?(saved)
            snapshot = runtimeError == nil ? saved : saved.replacing(enabled: false)
            // A startup shortcut conflict disables this session only; do not rewrite the file.
            onChange?(snapshot)
        } catch { loadError = WindowSettingsText.loadError }
    }

    @discardableResult func setEnabled(_ enabled: Bool) -> String? {
        apply(snapshot.replacing(enabled: enabled))
    }
    @discardableResult func setShortcut(_ shortcut: LauncherShortcut) -> String? {
        guard WindowControlConfiguration.isValidShortcut(shortcut) else { return WindowSettingsText.invalidShortcut }
        return apply(snapshot.replacing(shortcut: shortcut))
    }
    @discardableResult func setKeepModeOpen(_ keepOpen: Bool) -> String? {
        apply(snapshot.replacing(keepModeOpen: keepOpen))
    }
    @discardableResult func savePreset(_ preset: WindowPreset) -> String? {
        guard preset.isValid else { return WindowSettingsText.invalidPreset }
        let updated = snapshot.presets.filter { $0.slot != preset.slot } + [preset]
        return apply(snapshot.replacing(presets: updated))
    }
    @discardableResult func removePreset(slot: Int) -> String? {
        apply(snapshot.replacing(presets: snapshot.presets.filter { $0.slot != slot }))
    }
    func retrySave() { guard hasLoaded, loadError == nil else { return }; persist() }
    func flush() async { await pendingWrite?.value }

    /// Only the backup coordinator calls this after its combined launcher/window
    /// hotkey transaction succeeds. Local enablement is never imported.
    @discardableResult
    func replaceForBackup(_ candidate: WindowControlConfiguration) -> String? {
        guard hasLoaded, loadError == nil else { return WindowSettingsText.loadError }
        guard candidate.isValid, candidate.enabled == snapshot.enabled else { return WindowSettingsText.invalidPreset }
        guard candidate != snapshot else { return nil }
        runtimeError = nil
        snapshot = candidate
        onChange?(candidate)
        persist()
        return nil
    }

    private func apply(_ candidate: WindowControlConfiguration) -> String? {
        guard hasLoaded, loadError == nil else { return WindowSettingsText.loadError }
        guard candidate.isValid else { return WindowSettingsText.invalidPreset }
        guard candidate != snapshot else { return nil }
        if let error = applyConfiguration?(candidate) { runtimeError = error; return error }
        runtimeError = nil
        snapshot = candidate
        onChange?(candidate)
        persist()
        return nil
    }

    private func persist() {
        revision &+= 1
        let value = snapshot, generation = revision, store = store
        pendingWrite = Task { [weak self] in
            do {
                try await store.save(value, revision: generation)
                guard let self, revision == generation else { return }
                persistenceError = nil
            } catch {
                guard let self, revision == generation else { return }
                persistenceError = WindowSettingsText.saveError
            }
        }
    }
}

@MainActor
final class WindowControlSettingsController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    /// Supplies an already captured source snapshot. Never reads AX from this view.
    var capturedPreset: (() -> WindowPreset?)?
    let accessibility: WindowAccessibilityAccess
    private let preferences: WindowControlPreferences

    init(preferences: WindowControlPreferences, accessibility: WindowAccessibilityAccess = .init()) {
        self.preferences = preferences
        self.accessibility = accessibility
        let size = NSSize(width: 590, height: 650)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = WindowSettingsText.title
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        super.init(window: window)
        window.delegate = self
        window.center()
        prepareContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func prepareContent() {
        window?.contentView = NSHostingView(rootView: WindowControlSettingsView(
            preferences: preferences, accessibility: accessibility,
            capturedPreset: { [weak self] in self?.capturedPreset?() },
            close: { [weak self] in self?.window?.performClose(nil) }))
    }

    func show() {
        accessibility.refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// App activation may follow a permission change in System Settings. Updating
    /// the observable child preserves the existing editor and disclosure state.
    func refreshAccess() {
        guard window?.isVisible == true else { return }
        accessibility.refresh()
    }

    func hide() { window?.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { window?.makeFirstResponder(nil) }
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        onClose?()
    }
    func finishRecordingCurrentShortcut() -> Bool {
        guard window?.isKeyWindow == true,
              let recorder = window?.firstResponder as? ShortcutRecorderButton,
              recorder.isRecording else { return false }
        recorder.finishRecording()
        return true
    }
}

struct WindowControlSettingsView: View {
    @ObservedObject var preferences: WindowControlPreferences
    let accessibility: WindowAccessibilityAccess
    let capturedPreset: () -> WindowPreset?
    let close: () -> Void
    @ViewState private var error: String?
    @ViewState private var editingSlot: PresetSlot?

    private struct PresetSlot: Identifiable { let id: Int }

    var body: some View {
        VStack(spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !preferences.hasLoaded { ProgressView(WindowSettingsText.loading) }
                    if let message = preferences.loadError {
                        errorMessage(message)
                        Button(WindowSettingsText.retry) { Task { await preferences.load() } }
                    }
                    if let message = error ?? preferences.runtimeError { errorMessage(message) }
                    settingsContent
                    if let message = preferences.persistenceError {
                        errorMessage(message)
                        Button(WindowSettingsText.retry) { preferences.retrySave() }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(WindowSettingsText.accessHelp).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button(WindowSettingsText.done, action: close).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 590, height: 650)
        .sheet(item: $editingSlot) { item in
            WindowPresetEditor(slot: item.id,
                existing: preferences.snapshot.presets.first { $0.slot == item.id },
                capturedPreset: capturedPreset,
                save: { preferences.savePreset($0) }, close: { editingSlot = nil })
        }
    }

    var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                Toggle(WindowSettingsText.enable, isOn: Binding(
                    get: { preferences.snapshot.enabled }, set: {
                        error = preferences.setEnabled($0)
                        if $0 && error == nil { accessibility.refresh() }
                    }))
                    .font(.headline)
                LabeledContent(WindowSettingsText.shortcut) {
                    ShortcutRecorder(shortcut: preferences.snapshot.shortcut,
                        onCapture: { let result = preferences.setShortcut($0); error = result; return result },
                        onBegin: { error = nil }, accessibilityLabel: WindowSettingsText.shortcut,
                        accessibilityHelp: WindowSettingsText.shortcutHelp)
                        .frame(width: 175, height: 26)
                }
                Text(WindowSettingsText.shortcutHelp).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(WindowSettingsText.keepOpen, isOn: Binding(
                    get: { preferences.snapshot.keepModeOpen }, set: { error = preferences.setKeepModeOpen($0) }))
                Text(WindowSettingsText.keepOpenHelp).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.disabled(!preferences.hasLoaded || preferences.loadError != nil)
            WindowAccessibilityCard(accessibility: accessibility,
                featureEnabled: preferences.snapshot.enabled, shortcut: preferences.snapshot.shortcut)
            card {
                Text(WindowSettingsText.presets).font(.headline)
                Text(WindowSettingsText.presetsHelp).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(1...9, id: \.self) { slot in presetRow(slot) }
            }.disabled(!preferences.hasLoaded || preferences.loadError != nil)
            card {
                Text(WindowSettingsText.controls).font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    shortcutRow("⌥ ← ↑ ↓ →", WindowSettingsText.half)
                    shortcutRow("⌘ ← ↑ ↓ →", WindowSettingsText.display)
                    shortcutRow("↩", WindowSettingsText.fill)
                    shortcutRow("Space", WindowSettingsText.center)
                    shortcutRow("Tab", WindowSettingsText.restore)
                    shortcutRow("Esc", WindowSettingsText.close)
                }.font(.callout)
            }
        }
    }

    private func presetRow(_ slot: Int) -> some View {
        let preset = preferences.snapshot.presets.first { $0.slot == slot }
        return HStack(spacing: 10) {
            Text("\(slot)").font(.system(.callout, design: .monospaced).weight(.medium))
                .frame(width: 24, height: 24).background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            WindowPresetThumbnail(preset: preset).frame(width: 44, height: 29)
            Text(preset?.name ?? WindowSettingsText.emptySlot).lineLimit(1)
                .foregroundStyle(preset == nil ? Color.secondary : Color.primary)
            Spacer(minLength: 8)
            Button(preset == nil ? WindowSettingsText.add : WindowSettingsText.edit) { editingSlot = .init(id: slot) }
                .accessibilityLabel("\(preset == nil ? WindowSettingsText.add : WindowSettingsText.edit) \(slot)")
            if preset != nil {
                Button { error = preferences.removePreset(slot: slot) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help(WindowSettingsText.delete)
                    .accessibilityLabel("\(WindowSettingsText.delete) \(slot)")
            } else { Color.clear.frame(width: 14, height: 16) }
        }.frame(minHeight: 31)
    }

    private func shortcutRow(_ key: String, _ label: String) -> some View {
        GridRow { Text(key).monospaced(); Text(label) }
    }
    private func errorMessage(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Only this card observes permission changes; preset editing state lives outside
/// it and is never rebuilt to reflect a grant or revocation.
struct WindowAccessibilityCard: View {
    @ObservedObject var accessibility: WindowAccessibilityAccess
    let featureEnabled: Bool
    let shortcut: LauncherShortcut

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(WindowSettingsText.accessTitle).font(.headline)
                Spacer(minLength: 12)
                Label(statusText, systemImage: accessibility.status == .enabled ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption).foregroundStyle(accessibility.status == .enabled ? Color.green : Color.secondary)
            }
            detail(WindowSettingsText.accessPurpose)
            if accessibility.status != .enabled { detail(WindowSettingsText.accessSetup) }
            HStack {
                Button(WindowSettingsText.accessOpen) { accessibility.openSettings() }
                Button(WindowSettingsText.accessCheck) { accessibility.refresh() }
            }
            if let error = accessibility.openingError { detail(error, color: .red) }
            if accessibility.status != .enabled {
                DisclosureGroup(WindowSettingsText.accessRepairTitle, isExpanded: $accessibility.showsRepairHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        detail(WindowSettingsText.accessRepairHelp)
                        Text(WindowSettingsText.accessCurrentApp).font(.caption.weight(.medium))
                        Text(verbatim: accessibility.currentAppURL.path)
                            .font(.caption).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(WindowSettingsText.accessReveal) { accessibility.revealCurrentApp() }
                    }.padding(.top, 6)
                }.font(.caption)
            }
            detail(L10n.format(featureEnabled ? WindowSettingsText.accessContinue : WindowSettingsText.accessEnableFirst,
                               shortcut.localizedDisplayName))
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.16)))
    }
    private var statusText: String {
        switch accessibility.status {
        case .unchecked: WindowSettingsText.accessUnchecked
        case .required: WindowSettingsText.accessRequired
        case .enabled: WindowSettingsText.accessEnabled
        }
    }
    private func detail(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

struct WindowPresetEditor: View {
    let slot: Int
    let capturedPreset: () -> WindowPreset?
    let save: (WindowPreset) -> String?
    let close: () -> Void
    @ViewState private var name: String
    @ViewState private var x: String
    @ViewState private var y: String
    @ViewState private var width: String
    @ViewState private var height: String
    @ViewState private var error: String?

    init(slot: Int, existing: WindowPreset?, capturedPreset: @escaping () -> WindowPreset?,
         save: @escaping (WindowPreset) -> String?, close: @escaping () -> Void) {
        self.slot = slot; self.capturedPreset = capturedPreset; self.save = save; self.close = close
        _name = State(initialValue: existing?.name ?? "")
        _x = State(initialValue: Self.percent(existing?.x ?? 0))
        _y = State(initialValue: Self.percent(existing?.y ?? 0))
        _width = State(initialValue: Self.percent(existing?.width ?? 0.5))
        _height = State(initialValue: Self.percent(existing?.height ?? 1))
    }

    private var draft: WindowPreset? {
        guard let x = Self.number(x), let y = Self.number(y),
              let width = Self.number(width), let height = Self.number(height) else { return nil }
        return WindowPreset(slot: slot, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            x: x / 100, y: y / 100, width: width / 100, height: height / 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(WindowSettingsText.editTitle) · \(slot)").font(.headline)
            TextField(WindowSettingsText.name, text: $name).textFieldStyle(.roundedBorder)
            HStack(alignment: .center, spacing: 24) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    percentRow(WindowSettingsText.x, $x)
                    percentRow(WindowSettingsText.y, $y)
                    percentRow(WindowSettingsText.width, $width)
                    percentRow(WindowSettingsText.height, $height)
                }
                WindowPresetThumbnail(preset: previewPreset).frame(width: 185, height: 120)
                    .accessibilityLabel(WindowSettingsText.preview)
            }
            Text(WindowSettingsText.geometryHelp).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(WindowSettingsText.useCurrent) {
                guard let captured = capturedPreset(), captured.isValid else {
                    error = WindowSettingsText.currentUnavailable; return
                }
                x = Self.percent(captured.x); y = Self.percent(captured.y)
                width = Self.percent(captured.width); height = Self.percent(captured.height)
                error = nil
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button(WindowSettingsText.cancel, action: close).keyboardShortcut(.cancelAction)
                Button(WindowSettingsText.save) {
                    guard let draft, draft.isValid else { error = WindowSettingsText.invalidPreset; return }
                    if let message = save(draft) { error = message } else { close() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 505)
    }

    private var previewPreset: WindowPreset? {
        guard let draft else { return nil }
        let preview = WindowPreset(slot: slot, name: "Preview", x: draft.x, y: draft.y,
                                   width: draft.width, height: draft.height)
        return preview.isValid ? preview : nil
    }
    private func percentRow(_ label: String, _ value: Binding<String>) -> some View {
        GridRow {
            Text(label)
            HStack(spacing: 4) {
                TextField("", text: value).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    .frame(width: 66).accessibilityLabel(label)
                Text("%") .foregroundStyle(.secondary)
            }
        }
    }
    private static func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0...3)))
    }
    private static func number(_ value: String) -> Double? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return try? Double(value, format: .number.locale(Locale.current), lenient: false)
    }
}

struct WindowPresetThumbnail: View {
    let preset: WindowPreset?
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.16)))
            if let preset, preset.isValid {
                Rectangle().fill(Color.accentColor.opacity(0.25))
                    .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                    .frame(width: max(1, (size.width - 4) * preset.width), height: max(1, (size.height - 4) * preset.height))
                    .offset(x: 2 + (size.width - 4) * preset.x, y: 2 + (size.height - 4) * preset.y)
            }
        }.accessibilityHidden(true)
    }
}
