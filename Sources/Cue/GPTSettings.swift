import AppKit
import CueCore
import SwiftUI

enum GPTSettingsText {
    static let title = text("settings.title", "GPT Settings")
    static let networkOff = text("network.off", "Cue’s network access is off. GPT stays offline until you enable it in Cue Settings.")
    static let cueSettings = text("network.settings", "Cue Settings…")
    static let key = text("key.heading", "OpenAI API Key")
    static let keyPlaceholder = text("key.placeholder", "Enter a new API key")
    static let keyHelp = text("key.help", "Stored only in this Mac’s Keychain. Saved keys are never shown here.")
    static let keySaved = text("key.saved", "API key saved")
    static let keyMissing = text("key.missing", "No API key saved")
    static let keyChecking = text("key.checking", "Checking Keychain…")
    static let keyUnknown = text("key.unknown", "Key status unavailable")
    static let keyRemoved = text("key.removed", "API key removed")
    static let keyInvalid = text("key.invalid", "Enter a complete API key without spaces or line breaks.")
    static let keyDenied = text("key.denied", "Keychain access was not allowed. Unlock your Mac or allow Cue’s Keychain request, then try again.")
    static let keyUnavailable = text("key.unavailable", "The API key could not be accessed in Keychain. Please try again.")
    static let keyCreate = text("key.create", "Create an API Key…")
    static let save = text("action.saveKey", "Save Key")
    static let remove = text("action.removeKey", "Remove Key")
    static let model = text("model.heading", "Model")
    static let modelHelp = text("model.help", "GPT-6 Luna is the default for fast, inexpensive answers and translation. Enter another OpenAI Responses API model ID to change it.")
    static let modelInvalid = text("model.invalid", "Enter a valid model ID, such as gpt-6-luna, using up to 128 letters, numbers, periods, hyphens, underscores or colons.")
    static let applyModel = text("model.apply", "Save Model")
    static let unsavedModel = text("model.unsaved", "Save to apply this model. Closing leaves the saved model unchanged.")
    static let resetModel = text("model.reset", "Use Default")
    static let translation = text("translation.heading", "Translate To")
    static let automatic = text("translation.automatic", "Automatic: Chinese ↔ English")
    static let traditionalChinese = text("translation.traditionalChinese", "Traditional Chinese (Taiwan)")
    static let english = text("translation.english", "English")
    static let translationHelp = text("translation.help", "Automatic translates Chinese into English and other languages into Traditional Chinese with Taiwanese terminology.")
    static let privacy = text("privacy.help", "Only text you submit is sent to OpenAI; never while typing. No GPT history is saved. Copied replies follow Clipboard History settings. No live web search.")
    static let billing = text("billing.help", "OpenAI API usage is billed separately from a ChatGPT subscription. Changing models can change the cost.")
    static let done = text("action.done", "Done")

    private static func text(_ key: String, _ value: String) -> String {
        L10n.string(key, table: "GPTSettings", value: value)
    }
}

@MainActor
final class GPTPreferences: ObservableObject {
    nonisolated static let modelKey = "gpt.model"
    nonisolated static let translationKey = "gpt.translationTarget"
    enum ValidationError: Error, Equatable, Sendable { case invalidModel }

    @Published private(set) var configuration: GPTConfiguration
    var onChange: (() -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Self.modelKey) as? String ?? ""
        configuration = GPTConfiguration(
            model: GPTConfiguration.isValidModelID(saved) ? saved : GPTConfiguration.defaultModel,
            translationTarget: (defaults.object(forKey: Self.translationKey) as? String)
                .flatMap(GPTTranslationTarget.init(rawValue:)) ?? .automatic
        )
    }

    func setConfiguration(_ value: GPTConfiguration) throws {
        let model = value.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GPTConfiguration.isValidModelID(model) else { throw ValidationError.invalidModel }
        let updated = GPTConfiguration(model: model, translationTarget: value.translationTarget)
        guard updated != configuration else { return }
        defaults.set(updated.model, forKey: Self.modelKey)
        defaults.set(updated.translationTarget.rawValue, forKey: Self.translationKey)
        configuration = updated
        onChange?()
    }
}

/// Transient secure-field state. Construction does not touch Keychain or the network.
@MainActor
final class GPTCredentialModel: ObservableObject {
    @Published var draftKey = ""
    @Published private(set) var hasSavedKey: Bool?
    @Published private(set) var isBusy = false
    @Published private(set) var notice: String?
    @Published private(set) var isError = false
    var onCredentialsChange: (() -> Void)?
    private let store: GPTKeyStore
    private var revision = 0

    init(store: GPTKeyStore = .keychain) { self.store = store }

    func refresh() async {
        guard !isBusy else { return }
        let current = begin()
        defer { if current == revision { isBusy = false } }
        do {
            let exists = try await store.contains()
            guard current == revision, !Task.isCancelled else { return }
            hasSavedKey = exists
            isBusy = false
        } catch {
            finish(error: error, revision: current)
        }
    }

    func save() async {
        guard !isBusy else { return }
        guard GPTKeychain.isValidKey(draftKey) else {
            notice = GPTSettingsText.keyInvalid
            isError = true
            return
        }
        let value = draftKey
        draftKey = ""
        let current = begin()
        defer { if current == revision { isBusy = false } }
        onCredentialsChange?()
        do {
            try await store.save(value)
            guard current == revision, !Task.isCancelled else { return }
            hasSavedKey = true
            notice = GPTSettingsText.keySaved
            isBusy = false
        } catch {
            finish(error: error, revision: current)
        }
    }

    func remove() async {
        guard !isBusy else { return }
        draftKey = ""
        let current = begin()
        defer { if current == revision { isBusy = false } }
        onCredentialsChange?()
        do {
            try await store.delete()
            guard current == revision, !Task.isCancelled else { return }
            hasSavedKey = false
            notice = GPTSettingsText.keyRemoved
            isBusy = false
        } catch {
            finish(error: error, revision: current)
        }
    }

    func close() {
        revision += 1
        draftKey = ""
        notice = nil
        isError = false
        isBusy = false
        hasSavedKey = nil
    }

    private func begin() -> Int {
        revision += 1
        isBusy = true
        notice = nil
        isError = false
        return revision
    }

    private func finish(error: Error, revision current: Int) {
        guard current == revision else { return }
        isBusy = false
        guard !(error is CancellationError), !Task.isCancelled else { return }
        isError = true
        switch error as? GPTKeychainError {
        case .invalidKey: notice = GPTSettingsText.keyInvalid
        case .accessDenied: notice = GPTSettingsText.keyDenied
        default: notice = GPTSettingsText.keyUnavailable
        }
    }
}

@MainActor
final class GPTSettingsController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onOpenGeneralSettings: (() -> Void)?
    var onCredentialsChange: (() -> Void)?
    private let preferences: GPTPreferences
    private let policy: NetworkPolicy
    private let credentials: GPTCredentialModel
    private var refreshTask: Task<Void, Never>?

    init(preferences: GPTPreferences, policy: NetworkPolicy, keyStore: GPTKeyStore = .keychain) {
        self.preferences = preferences
        self.policy = policy
        credentials = GPTCredentialModel(store: keyStore)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = GPTSettingsText.title
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        super.init(window: window)
        credentials.onCredentialsChange = { [weak self] in self?.onCredentialsChange?() }
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func show() {
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.deminiaturize(nil)
            window?.makeKeyAndOrderFront(nil)
            return
        }
        refreshTask?.cancel()
        prepareContent()
        refreshTask = Task { [weak self] in await self?.credentials.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func prepareContent() {
        window?.contentView = NSHostingView(rootView: GPTSettingsView(
            preferences: preferences, policy: policy, credentials: credentials,
            openGeneralSettings: { [weak self] in self?.onOpenGeneralSettings?() },
            close: { [weak self] in self?.window?.performClose(nil) }
        ))
    }

    func windowWillClose(_ notification: Notification) {
        refreshTask?.cancel()
        refreshTask = nil
        credentials.close()
        window?.makeFirstResponder(nil)
        onClose?()
    }
}

struct GPTSettingsView: View {
    @ObservedObject var preferences: GPTPreferences
    @ObservedObject var policy: NetworkPolicy
    @ObservedObject var credentials: GPTCredentialModel
    let openGeneralSettings: () -> Void
    let close: () -> Void
    @State private var model: String
    @State private var modelError: String?

    init(preferences: GPTPreferences, policy: NetworkPolicy, credentials: GPTCredentialModel,
         openGeneralSettings: @escaping () -> Void, close: @escaping () -> Void) {
        self.preferences = preferences
        self.policy = policy
        self.credentials = credentials
        self.openGeneralSettings = openGeneralSettings
        self.close = close
        _model = State(initialValue: preferences.configuration.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !policy.allowsNetwork {
                HStack(alignment: .top, spacing: 12) {
                    Text(GPTSettingsText.networkOff).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(GPTSettingsText.cueSettings, action: openGeneralSettings)
                }.padding(10).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(GPTSettingsText.key).font(.headline)
                    Spacer()
                    Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    SecureField(GPTSettingsText.keyPlaceholder, text: $credentials.draftKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(GPTSettingsText.key)
                        .disabled(credentials.isBusy)
                        .onSubmit { Task { await credentials.save() } }
                    Button(GPTSettingsText.save) { Task { await credentials.save() } }
                        .disabled(credentials.isBusy || credentials.draftKey.isEmpty)
                    Button(GPTSettingsText.remove) { Task { await credentials.remove() } }
                        .disabled(credentials.isBusy || credentials.hasSavedKey != true)
                }
                Text(credentials.notice ?? GPTSettingsText.keyHelp)
                    .font(.caption).foregroundStyle(credentials.isError ? Color.red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(GPTSettingsText.keyCreate) {
                    if let url = URL(string: "https://platform.openai.com/api-keys") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.link)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(GPTSettingsText.model).font(.headline)
                HStack {
                    TextField(GPTSettingsText.model, text: $model)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(GPTSettingsText.model)
                        .onChange(of: model) { _, _ in modelError = nil }
                        .onSubmit { _ = applyModel() }
                    Button(GPTSettingsText.applyModel) { _ = applyModel() }
                        .disabled(model == preferences.configuration.model)
                    Button(GPTSettingsText.resetModel) {
                        model = GPTConfiguration.defaultModel
                        modelError = nil
                    }.disabled(model == GPTConfiguration.defaultModel)
                }
                Text(modelError ?? (model == preferences.configuration.model ? GPTSettingsText.modelHelp : GPTSettingsText.unsavedModel))
                    .font(.caption).foregroundStyle(modelError == nil ? Color.secondary : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Picker(GPTSettingsText.translation, selection: Binding(
                    get: { preferences.configuration.translationTarget },
                    set: { target in
                        try? preferences.setConfiguration(GPTConfiguration(
                            model: preferences.configuration.model, translationTarget: target
                        ))
                    }
                )) {
                    Text(GPTSettingsText.automatic).tag(GPTTranslationTarget.automatic)
                    Text(GPTSettingsText.traditionalChinese).tag(GPTTranslationTarget.traditionalChinese)
                    Text(GPTSettingsText.english).tag(GPTTranslationTarget.english)
                }
                Text(GPTSettingsText.translationHelp).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(GPTSettingsText.privacy)
                Text(GPTSettingsText.billing)
            }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(GPTSettingsText.done, action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 560, height: 540)
    }

    private var keyStatus: String {
        if credentials.isBusy { return GPTSettingsText.keyChecking }
        if let exists = credentials.hasSavedKey { return exists ? GPTSettingsText.keySaved : GPTSettingsText.keyMissing }
        return GPTSettingsText.keyUnknown
    }

    private func applyModel() -> Bool {
        do {
            try preferences.setConfiguration(GPTConfiguration(
                model: model, translationTarget: preferences.configuration.translationTarget
            ))
            model = preferences.configuration.model
            modelError = nil
            return true
        } catch {
            modelError = GPTSettingsText.modelInvalid
            return false
        }
    }
}
