import AppKit
import CueCore
import SwiftUI

enum AppAliasText {
    static let action = L10n.string("action.edit", table: "AppAliases", value: "Edit Search Alias…")
    static let title = L10n.string("window.title", table: "AppAliases", value: "Search Alias — %@")
    static let alias = L10n.string("alias.label", table: "AppAliases", value: "Search alias")
    static let help = L10n.string("alias.help", table: "AppAliases", value: "Enter this alias in Cue to put this app first. Start with a letter; use up to 32 letters, numbers, - or _, without spaces. Leave it empty to remove the alias.")
    static let invalid = L10n.string("error.invalid", table: "AppAliases", value: "Start with a letter and use up to 32 letters, numbers, - or _, without spaces.")
    static let duplicate = L10n.string("error.duplicate", table: "AppAliases", value: "Another app already uses this alias. Choose a different one.")
    static let conversionConflict = L10n.string("error.conversionConflict", table: "AppAliases", value: "Chinese Conversion already uses this alias. Choose a different one or change it in Chinese Conversion Settings.")
    static let appConflict = L10n.string("error.appConflict", table: "AppAliases", value: "An app already uses “%@” as its search alias. Choose a different conversion alias or edit that app’s alias first.")
    static let limit = L10n.string("error.limit", table: "AppAliases", value: "You can save aliases for up to 256 apps. Remove an existing alias before adding another.")
    static let invalidApp = L10n.string("error.invalidApp", table: "AppAliases", value: "This app’s information is invalid. Update the app index and try again.")
    static let save = L10n.string("action.save", table: "AppAliases", value: "Save")
    static let cancel = L10n.string("action.cancel", table: "AppAliases", value: "Cancel")
}

/// Explicit app choices, stored separately from learned usage. Search receives a
/// prepared snapshot; neither defaults nor alias validation run while typing.
@MainActor
final class AppAliasPreferences {
    nonisolated static let storageKey = "application.searchAliases"
    nonisolated static let maximumAliases = 256
    private(set) var aliases: [String: String]
    var onChange: (([String: String]) -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String: String] = [:]
        var usedAliases = Set<String>()
        // Sort only bounded input so corrupt preferences cannot create unbounded
        // startup work. Oversized maps are ignored, never used for searching.
        if let stored = defaults.dictionary(forKey: Self.storageKey),
           stored.count <= Self.maximumAliases {
            for identifier in stored.keys.sorted() {
                guard Self.isValidIdentifier(identifier), let value = stored[identifier] as? String,
                      let normalized = Self.validated(value), !normalized.isEmpty,
                      usedAliases.insert(normalized).inserted else { continue }
                loaded[identifier] = value
            }
        }
        aliases = loaded
    }

    func alias(for application: IndexedApplication) -> String {
        aliases[application.aliasPreferenceID] ?? ""
    }

    @discardableResult
    func setAlias(_ value: String, for application: IndexedApplication,
                  conversionAliases: ChineseConversionAliases) -> String? {
        let identifier = application.aliasPreferenceID
        guard Self.isValidIdentifier(identifier) else { return AppAliasText.invalidApp }
        guard let normalized = Self.validated(value) else { return AppAliasText.invalid }
        if !normalized.isEmpty {
            let conversionNames = [conversionAliases.traditional, conversionAliases.simplified]
            guard !conversionNames.contains(where: { Self.normalize($0) == normalized }) else {
                return AppAliasText.conversionConflict
            }
            guard !aliases.contains(where: { $0.key != identifier && Self.normalize($0.value) == normalized }) else {
                return AppAliasText.duplicate
            }
            guard aliases[identifier] != nil || aliases.count < Self.maximumAliases else { return AppAliasText.limit }
        }
        guard (aliases[identifier] ?? "") != value else { return nil }
        if value.isEmpty { aliases.removeValue(forKey: identifier) }
        else { aliases[identifier] = value }
        defaults.set(aliases, forKey: Self.storageKey)
        onChange?(aliases)
        return nil
    }

    /// Used by the conversion editor too, so conflicts cannot be introduced by
    /// editing the other side of an existing app/command alias pair.
    func conflict(with conversionAliases: ChineseConversionAliases) -> String? {
        let usedAliases = Set(aliases.values.map(Self.normalize))
        for value in [conversionAliases.traditional, conversionAliases.simplified]
        where !value.isEmpty && usedAliases.contains(Self.normalize(value)) {
            return L10n.format(AppAliasText.appConflict, value)
        }
        return nil
    }

    private static func validated(_ value: String) -> String? {
        guard value.utf8.count <= 128, value.count <= 32 else { return nil }
        if value.isEmpty { return "" }
        guard !value.contains(where: \.isWhitespace),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let normalized = normalize(value)
        guard normalized.count <= 32, normalized.first?.isLetter == true,
              normalized.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return normalized
    }

    private static func normalize(_ value: String) -> String {
        SearchEngine.normalize(value)
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard value.utf8.count <= 4_096,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        if value.hasPrefix("bundle:") {
            let identifier = value.dropFirst("bundle:".count)
            return !identifier.isEmpty && identifier == identifier.lowercased()
                && !identifier.contains(where: \.isWhitespace)
        }
        return value.hasPrefix("path:/") && value.count > "path:/".count
    }
}

@MainActor
final class AppAliasSettingsController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let application: IndexedApplication
    private let preferences: AppAliasPreferences
    private let conversionAliases: () -> ChineseConversionAliases

    init(application: IndexedApplication, preferences: AppAliasPreferences,
         conversionAliases: @escaping () -> ChineseConversionAliases) {
        self.application = application
        self.preferences = preferences
        self.conversionAliases = conversionAliases
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 230),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.format(AppAliasText.title, application.name)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func prepareContent() {
        window?.contentView = NSHostingView(rootView: AppAliasSettingsView(
            application: application, preferences: preferences, conversionAliases: conversionAliases,
            close: { [weak self] in self?.window?.performClose(nil) }
        ))
    }

    func show() {
        prepareContent()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        onClose?()
    }
}

private struct AppAliasSettingsView: View {
    let application: IndexedApplication
    let preferences: AppAliasPreferences
    let conversionAliases: () -> ChineseConversionAliases
    let close: () -> Void
    @State private var alias: String
    @State private var error: String?
    @FocusState private var isAliasFocused: Bool

    init(application: IndexedApplication, preferences: AppAliasPreferences,
         conversionAliases: @escaping () -> ChineseConversionAliases, close: @escaping () -> Void) {
        self.application = application
        self.preferences = preferences
        self.conversionAliases = conversionAliases
        self.close = close
        _alias = State(initialValue: preferences.alias(for: application))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(application.name).font(.headline).lineLimit(1)
            TextField(AppAliasText.alias, text: $alias)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(AppAliasText.alias)
                .focused($isAliasFocused)
                .onChange(of: alias) { _, _ in error = nil }
            Text(error ?? AppAliasText.help)
                .font(.caption).foregroundStyle(error == nil ? Color.secondary : .red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(AppAliasText.cancel, action: close).keyboardShortcut(.cancelAction)
                Button(AppAliasText.save) {
                    error = preferences.setAlias(alias, for: application, conversionAliases: conversionAliases())
                    if error == nil { close() }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 470, height: 230)
        .onAppear { isAliasFocused = true }
    }
}
