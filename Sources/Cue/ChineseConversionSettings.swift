import AppKit
@preconcurrency import ApplicationServices
import Combine
import CueCore
import SwiftUI

enum ChineseConversionText {
    static let title = L10n.string("settings.title", table: "ChineseConversion", value: "Chinese Conversion")
    static let aliases = L10n.string("aliases.heading", table: "ChineseConversion", value: "Search Aliases")
    static let traditional = L10n.string("aliases.traditional", table: "ChineseConversion", value: "Traditional Chinese · Taiwan")
    static let simplified = L10n.string("aliases.simplified", table: "ChineseConversion", value: "Simplified Chinese · Mainland China")
    static let help = L10n.string("aliases.help", table: "ChineseConversion", value: "Type an exact alias in Cue, then press Return to replace selected text. Leave it empty to disable the alias.")
    static let invalid = L10n.string("aliases.invalid", table: "ChineseConversion", value: "Use two different, short aliases without line breaks.")
    static let save = L10n.string("settings.save", table: "ChineseConversion", value: "Save")
    static let cancel = L10n.string("settings.cancel", table: "ChineseConversion", value: "Cancel")
    static let defaults = L10n.string("settings.defaults", table: "ChineseConversion", value: "Restore Defaults")
    static let access = L10n.string("access.heading", table: "ChineseConversion", value: "Selected Text Access")
    static let accessHelp = L10n.string("access.help", table: "ChineseConversion", value: "Allow Cue in System Settings → Privacy & Security → Accessibility to replace selected text in other apps. Then select the text again and retry.")
    static let accessAllowed = L10n.string("access.allowed", table: "ChineseConversion", value: "Accessibility access is enabled.")
    static let openAccess = L10n.string("access.open", table: "ChineseConversion", value: "Open Accessibility Settings…")
    static let converting = L10n.string("status.converting", table: "ChineseConversion", value: "Converting selected text…")
    static let noSelection = L10n.string("error.selection", table: "ChineseConversion", value: "Select text in an editable field in another app, then try again.")
    static let unsupported = L10n.string("error.unsupported", table: "ChineseConversion", value: "This field does not support replacing selected text. Try an editable text field.")
    static let changed = L10n.string("error.changed", table: "ChineseConversion", value: "The app or selection changed. Select the text again and retry.")
    static let tooLarge = L10n.string("error.tooLarge", table: "ChineseConversion", value: "Select a smaller passage (up to 256 KiB).")
    static let clipboard = L10n.string("error.clipboard", table: "ChineseConversion", value: "Cue couldn’t temporarily use the clipboard. Your text was not replaced.")
    static let unverified = L10n.string("error.unverified", table: "ChineseConversion", value: "Couldn’t confirm the replacement. Converted text remains on the clipboard; check the original app before retrying.")
    static let failed = L10n.string("error.failed", table: "ChineseConversion", value: "Couldn’t convert the selected text. Please try again.")

    static func message(for error: Error) -> String {
        guard let error = error as? SelectedTextError else { return failed }
        switch error {
        case .permissionRequired: return accessHelp
        case .noTarget, .noSelection: return noSelection
        case .secureField, .readOnly, .unsupportedField: return unsupported
        case .selectionChanged, .applicationUnavailable: return changed
        case .textTooLarge: return tooLarge
        case .clipboardUnavailable: return clipboard
        case .replacementUnverified: return unverified
        case .replacementFailed, .busy: return failed
        }
    }
}

@MainActor
final class ChineseConversionPreferences: ObservableObject {
    @Published private(set) var aliases: ChineseConversionAliases
    var onChange: ((ChineseConversionAliases) -> Void)?
    var validateAliases: ((ChineseConversionAliases) -> String?)?
    private let defaults: UserDefaults
    private static let key = "chineseConversion.aliases"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let values = defaults.dictionary(forKey: Self.key) as? [String: String]
        aliases = (try? ChineseConversionAliases(
            traditional: values?["traditional"] ?? "st",
            simplified: values?["simplified"] ?? "ts"
        )) ?? .defaults
    }

    func save(traditional: String, simplified: String) throws {
        let value = try ChineseConversionAliases(traditional: traditional, simplified: simplified)
        if let message = validateAliases?(value) { throw AliasConflict(message: message) }
        guard aliases != value else { return }
        defaults.set(["traditional": value.traditional, "simplified": value.simplified], forKey: Self.key)
        aliases = value
        onChange?(value)
    }

    struct AliasConflict: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

@MainActor
final class ChineseConversionSettingsController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let preferences: ChineseConversionPreferences
    private var accessGranted = false

    init(preferences: ChineseConversionPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = ChineseConversionText.title
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func show() {
        accessGranted = AXIsProcessTrusted()
        prepareContent()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshAccess() {
        guard window?.isVisible == true else { return }
        let updated = AXIsProcessTrusted()
        guard updated != accessGranted else { return }
        accessGranted = updated
        // Keep in-progress alias edits intact when returning from System Settings.
        if let host = window?.contentView as? NSHostingView<ChineseConversionSettingsView> {
            host.rootView.accessGranted = updated
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        onClose?()
    }

    func prepareContent() {
        window?.contentView = NSHostingView(rootView: ChineseConversionSettingsView(
            preferences: preferences, accessGranted: accessGranted,
            close: { [weak self] in self?.window?.performClose(nil) }
        ))
    }
}

private struct ChineseConversionSettingsView: View {
    @ObservedObject var preferences: ChineseConversionPreferences
    var accessGranted: Bool
    let close: () -> Void
    @State private var traditional: String
    @State private var simplified: String
    @State private var error: String?

    init(preferences: ChineseConversionPreferences, accessGranted: Bool, close: @escaping () -> Void) {
        self.preferences = preferences
        self.accessGranted = accessGranted
        self.close = close
        _traditional = State(initialValue: preferences.aliases.traditional)
        _simplified = State(initialValue: preferences.aliases.simplified)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ChineseConversionText.aliases).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text(ChineseConversionText.traditional)
                    TextField("st", text: $traditional).accessibilityLabel(ChineseConversionText.traditional)
                }
                GridRow {
                    Text(ChineseConversionText.simplified)
                    TextField("ts", text: $simplified).accessibilityLabel(ChineseConversionText.simplified)
                }
            }.textFieldStyle(.roundedBorder)
            Text(error ?? ChineseConversionText.help)
                .font(.caption).foregroundStyle(error == nil ? Color.secondary : .red)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(ChineseConversionText.access).font(.headline)
            Text(accessGranted ? ChineseConversionText.accessAllowed : ChineseConversionText.accessHelp)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !accessGranted {
                Button(ChineseConversionText.openAccess) {
                    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button(ChineseConversionText.defaults) {
                    traditional = ChineseConversionAliases.defaults.traditional
                    simplified = ChineseConversionAliases.defaults.simplified
                    error = nil
                }
                Spacer()
                Button(ChineseConversionText.cancel, action: close).keyboardShortcut(.cancelAction)
                Button(ChineseConversionText.save) {
                    do {
                        try preferences.save(traditional: traditional, simplified: simplified)
                        close()
                    } catch let conflict as ChineseConversionPreferences.AliasConflict {
                        self.error = conflict.message
                    } catch { self.error = ChineseConversionText.invalid }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 540, height: 440)
    }
}
