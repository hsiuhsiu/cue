import AppKit
import Combine
import CueCore
import Darwin
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BackupSettingsService {
    var exportDocument: () async throws -> SettingsBackupDocument
    var readAPIKeyForExport: () async throws -> String?
    var preview: (SettingsBackupDocument) async throws -> SettingsBackupPreview
    var apply: (SettingsBackupDecoded, Set<SettingsBackupSection>, Bool, Bool) async throws -> SettingsBackupApplyResult
}

/// Explicitly injected I/O; tests never use a user-selected file or the real Keychain.
struct BackupFileAccess: Sendable {
    var read: @Sendable (URL) async throws -> Data
    var write: @Sendable (Data, URL) async throws -> Void

    static let live = BackupFileAccess(read: { url in
        try await backupBackground {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SettingsBackupError.invalidFile }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: SettingsBackupCodec.maximumFileBytes + 1) ?? Data()
            guard data.count <= SettingsBackupCodec.maximumFileBytes else { throw SettingsBackupError.tooLarge }
            return data
        }
    }, write: { data, url in
        try await backupBackground {
            guard data.count <= SettingsBackupCodec.maximumFileBytes else { throw SettingsBackupError.tooLarge }
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".cue-backup-\(UUID().uuidString).tmp")
            let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            defer { try? FileManager.default.removeItem(at: temporary) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
            catch { try? handle.close(); throw error }
            // Cancel before the single atomic publication point. No cleartext sidecar
            // exists for encrypted backups; only the final encoded bytes are written.
            try Task.checkCancellation()
            guard rename(temporary.path, url.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
    })
}

private func backupBackground<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
    let task = Task.detached(priority: .utility) {
        try Task.checkCancellation()
        let value = try operation()
        try Task.checkCancellation()
        return value
    }
    return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
}

enum BackupText {
    static func s(_ key: String, _ fallback: String) -> String { L10n.string(key, table: "Backup", value: fallback) }
    static let title = s("title", "Settings Backup & Transfer")
    static let export = s("export", "Export")
    static let importFile = s("import", "Import")
    static let exportHelp = s("export.help", "Save your Cue preferences, aliases, chosen browsers, and window presets. Clipboard history, conversations, usage learning, and this Mac’s network and startup choices are excluded.")
    static let protect = s("export.protect", "Protect with a password")
    static let protectHelp = s("export.protect.help", "Use at least 12 characters. Cue cannot recover a forgotten password. Your password is never saved.")
    static let password = s("password", "Password")
    static let confirmPassword = s("password.confirm", "Confirm password")
    static let includeKey = s("export.include_key", "Include my OpenAI API key")
    static let includeKeyHelp = s("export.include_key.help", "Requires password protection. Cue reads the key only after you choose Export; macOS may ask for Keychain access.")
    static let plaintextHelp = s("export.plaintext", "Without password protection, the file is readable JSON and never contains an API key. Custom names and aliases may still reveal personal preferences.")
    static let exportButton = s("export.button", "Export Settings…")
    static let importHelp = s("import.help", "Choose a Cue settings file to review its changes before applying anything. Unselected sections and this Mac’s network, recording, startup, and permission choices stay as they are.")
    static let choose = s("import.choose", "Choose Backup…")
    static let chooseAnother = s("import.choose_another", "Choose Another Backup…")
    static let unlockHelp = s("import.unlock.help", "This backup is password protected. Enter its password to preview the settings.")
    static let unlock = s("import.unlock", "Unlock Backup")
    static let preview = s("import.preview", "Choose What to Apply")
    static let current = s("import.current", "On this Mac")
    static let incoming = s("import.incoming", "In the backup")
    static let retentionConsent = s("import.retention_consent", "Apply retention even if it deletes older clipboard history on this Mac")
    static let retentionHelp = s("import.retention_help", "Deleted history cannot be restored by this settings backup. Clipboard recording remains unchanged.")
    static let restoreKey = s("import.restore_key", "Restore the API key from this backup, replacing this Mac’s saved key")
    static let restoreKeyHelp = s("import.restore_key.help", "The key goes directly into macOS Keychain. Cue does not show it or send a test request. Leave this off to keep your current key.")
    static let apply = s("import.apply", "Apply Selected Settings")
    static let busyExport = s("busy.export", "Preparing and saving backup…")
    static let busyRead = s("busy.read", "Reading backup…")
    static let busyUnlock = s("busy.unlock", "Unlocking and checking backup…")
    static let busyApply = s("busy.apply", "Applying selected settings…")
    static let exported = s("success.exported", "Settings backup saved.")
    static let imported = s("success.imported", "Selected settings applied. A language change takes effect after reopening Cue.")
    static let keyRestored = s("success.key", "The API key was saved in Keychain.")
    static let keyFailed = s("error.key_restore", "Couldn’t confirm that the API key was saved. Check GPT Settings before trying to restore it again.")
    static let ignoredFields = s("import.ignored_fields", "Ignored %d unsupported settings fields.")
    static let cleanupFailed = s("error.cleanup", "Settings were applied, but clipboard cleanup could not finish. Check Clipboard History before retrying.")
    static let mismatch = s("error.password_match", "The passwords do not match.")
    static let keyMissing = s("error.key_missing", "No saved API key was found. Turn off Include API key, or save one in GPT Settings first.")
    static let invalidFile = s("error.invalid_file", "This is not a valid Cue settings backup.")
    static let unsupported = s("error.version", "This backup uses a format this version of Cue does not support.")
    static let tooLarge = s("error.too_large", "This backup is too large. Cue accepts files up to 1 MiB.")
    static let invalidSettings = s("error.settings", "The backup contains invalid settings. Nothing was applied.")
    static let passwordRequired = s("error.password_required", "Enter the password for this backup.")
    static let invalidPassword = s("error.password_length", "Use a password with at least 12 characters and no more than 1,024 UTF-8 bytes.")
    static let encryptionRequired = s("error.encryption_required", "An API key can only be included in a password-protected backup.")
    static let authenticationFailed = s("error.authentication", "The password is incorrect or the backup has been damaged. Nothing was applied.")
    static let cryptographyFailure = s("error.crypto", "Couldn’t securely process this backup. Please try again.")
    static let operationFailed = s("error.operation", "Couldn’t complete this operation. Check the file and folder permissions, then try again.")
    static let cancel = s("cancel", "Cancel")
    static let done = s("done", "Done")
    static let noPreview = s("import.empty", "This backup contains no settings to apply.")

    static func section(_ value: SettingsBackupSection) -> String {
        switch value {
        case .general: s("section.general", "General & Interaction")
        case .appAliases: s("section.app_aliases", "App Search Aliases")
        case .conversionAliases: s("section.conversion", "Chinese Conversion Aliases")
        case .browsers: s("section.browsers", "Google Search Browsers")
        case .gpt: s("section.gpt", "GPT Model & Translation")
        case .clipboard: s("section.clipboard", "Clipboard Retention")
        case .windows: s("section.windows", "Window Controls & Presets")
        }
    }

    static func message(_ error: Error) -> String {
        guard let value = error as? SettingsBackupError else {
            return (error as? LocalizedError)?.errorDescription ?? operationFailed
        }
        return switch value {
        case .invalidFile: invalidFile
        case .unsupportedVersion: unsupported
        case .tooLarge: tooLarge
        case .invalidSettings: invalidSettings
        case .passwordRequired: passwordRequired
        case .invalidPassword: invalidPassword
        case .encryptionRequired: encryptionRequired
        case .authenticationFailed: authenticationFailed
        case .cryptographyFailure: cryptographyFailure
        }
    }
}

@MainActor
final class BackupSettingsModel: ObservableObject {
    enum Mode: String, CaseIterable { case export, `import` }
    @Published private(set) var mode: Mode = .export
    @Published var passwordProtected = false {
        didSet { if !passwordProtected { includeAPIKey = false; exportPassword = ""; confirmPassword = "" } }
    }
    @Published var includeAPIKey = false
    @Published var exportPassword = ""
    @Published var confirmPassword = ""
    @Published var importPassword = ""
    @Published private(set) var filename: String?
    @Published private(set) var needsPassword = false
    @Published private(set) var preview: SettingsBackupPreview?
    @Published private(set) var selectedSections: Set<SettingsBackupSection> = []
    @Published var restoreAPIKey = false
    @Published var applyRetention = false
    @Published private(set) var hasImportedAPIKey = false
    @Published private(set) var isBusy = false
    @Published private(set) var isApplying = false
    @Published private(set) var progress = ""
    @Published private(set) var error: String?
    @Published private(set) var success: String?
    @Published private(set) var resultWarnings: [String] = []
    private let service: BackupSettingsService
    private let files: BackupFileAccess
    private var imported: SettingsBackupDecoded?
    private var encryptedBytes: Data?
    private var generation = 0
    private var work: Task<Void, Never>?

    init(service: BackupSettingsService, files: BackupFileAccess = .live) {
        self.service = service; self.files = files
    }
    var canApply: Bool {
        !isBusy && imported != nil && (!selectedSections.isEmpty || restoreAPIKey)
            && (!selectedSections.contains(.clipboard) || applyRetention)
    }
    func setMode(_ mode: Mode) { guard self.mode != mode else { return }; reset(mode: mode) }
    func reset(mode: Mode = .export) {
        guard !isApplying else { return }
        cancelPendingWork()
        self.mode = mode; passwordProtected = false; includeAPIKey = false
    }
    func cancelPendingWork() {
        // Once the adapter starts its transaction, wait for its explicit outcome.
        // Closing or quitting must never silently hide a partially committed import.
        guard !isApplying else { return }
        generation &+= 1; work?.cancel(); work = nil; isBusy = false; progress = ""
        exportPassword = ""; confirmPassword = ""; importPassword = ""
        imported = nil; encryptedBytes = nil; filename = nil; preview = nil
        needsPassword = false; hasImportedAPIKey = false; restoreAPIKey = false; applyRetention = false
        selectedSections = []; error = nil; success = nil; resultWarnings = []
        includeAPIKey = false; passwordProtected = false
    }
    func prepareForTermination() async {
        if isApplying { await work?.value }
        cancelPendingWork()
    }
    /// Also lets isolated checks wait for an operation without timing-based sleeps.
    func waitForCurrentOperation() async { await work?.value }
    func setSelected(_ section: SettingsBackupSection, selected: Bool) {
        guard !isBusy, preview?.rows.contains(where: { $0.section == section }) == true else { return }
        if selected { selectedSections.insert(section) } else { selectedSections.remove(section) }
        if section == .clipboard { applyRetention = false }
    }
    @discardableResult func validateExport() -> Bool {
        error = nil
        guard !includeAPIKey || passwordProtected else { error = BackupText.encryptionRequired; return false }
        guard passwordProtected else { return true }
        let password = exportPassword.precomposedStringWithCanonicalMapping
        guard SettingsBackupCodec.isValidPassword(password) else { error = BackupText.invalidPassword; return false }
        guard password == confirmPassword.precomposedStringWithCanonicalMapping else { error = BackupText.mismatch; return false }
        return true
    }
    func export(to url: URL) {
        guard !isBusy, validateExport() else { return }
        let password = passwordProtected ? exportPassword : nil, includeKey = includeAPIKey
        exportPassword = ""; confirmPassword = ""
        let token = begin(BackupText.busyExport), service = service, files = files
        work = Task { [weak self] in
            do {
                let document = try await service.exportDocument()
                try Task.checkCancellation()
                var key: String?
                if includeKey {
                    key = try await service.readAPIKeyForExport()
                    guard key != nil else { throw BackupUIError.message(BackupText.keyMissing) }
                }
                try Task.checkCancellation()
                let capturedKey = key
                let data = try await backupBackground { try SettingsBackupCodec.encode(document, password: password, apiKey: capturedKey) }
                key = nil
                try Task.checkCancellation()
                guard self?.generation == token else { return }
                try await files.write(data, url)
                guard let self, generation == token, !Task.isCancelled else { return }
                finish(); success = BackupText.exported
            } catch { self?.failed(error, token: token) }
        }
    }
    func load(from url: URL) {
        guard !isBusy else { return }
        cancelPendingWork(); mode = .import; filename = url.lastPathComponent
        let token = begin(BackupText.busyRead), files = files
        work = Task { [weak self] in
            do {
                let data = try await files.read(url)
                let encrypted = try await backupBackground { try SettingsBackupCodec.isEncrypted(data) }
                guard let self, generation == token, !Task.isCancelled else { return }
                if encrypted { encryptedBytes = data; needsPassword = true; finish() }
                else { try await decodeAndPreview(data, password: nil, token: token) }
            } catch { self?.failed(error, token: token) }
        }
    }
    func unlock() {
        guard !isBusy, let encryptedBytes else { return }
        guard !importPassword.isEmpty else { error = BackupText.passwordRequired; return }
        let password = importPassword; importPassword = ""
        let token = begin(BackupText.busyUnlock)
        work = Task { [weak self] in
            do { try await self?.decodeAndPreview(encryptedBytes, password: password, token: token) }
            catch { self?.failed(error, token: token) }
        }
    }
    func apply() {
        guard canApply, let imported else { return }
        let selected = selectedSections, restoreKey = restoreAPIKey && hasImportedAPIKey
        let retention = selected.contains(.clipboard) && applyRetention
        let token = begin(BackupText.busyApply), service = service
        isApplying = true
        work = Task { [weak self] in
            do {
                let result = try await service.apply(imported, selected, restoreKey, retention)
                guard let self, generation == token, !Task.isCancelled else { return }
                finish(); success = result.appliedSections.isEmpty ? nil : BackupText.imported
                resultWarnings = []
                switch result.keyStatus {
                case .excluded: break
                case .restored: success = [success, BackupText.keyRestored].compactMap { $0 }.joined(separator: "\n")
                case .failed: resultWarnings.append(BackupText.keyFailed)
                }
                if case .cleanupFailed = result.retentionStatus { resultWarnings.append(BackupText.cleanupFailed) }
                // A partial credential failure is a fresh explicit import, never an automatic retry.
                self.imported = nil; encryptedBytes = nil; preview = nil; needsPassword = false
                hasImportedAPIKey = false; restoreAPIKey = false; applyRetention = false; selectedSections = []
                importPassword = ""
            } catch { self?.failed(error, token: token) }
        }
    }
    private func decodeAndPreview(_ data: Data, password: String?, token: Int) async throws {
        let decoded = try await backupBackground { try SettingsBackupCodec.decode(data, password: password) }
        try Task.checkCancellation()
        guard generation == token else { return }
        let value = try await service.preview(decoded.document)
        guard generation == token, !Task.isCancelled else { return }
        imported = decoded
        let ignored = decoded.warnings.isEmpty ? [] : [L10n.format(BackupText.ignoredFields, decoded.warnings.count)]
        preview = SettingsBackupPreview(rows: value.rows, warnings: ignored + value.warnings)
        encryptedBytes = nil; needsPassword = false
        hasImportedAPIKey = decoded.isEncrypted && decoded.apiKey != nil
        selectedSections = Set(value.rows.map(\.section)).subtracting([.clipboard])
        restoreAPIKey = false; applyRetention = false; finish()
    }
    private func begin(_ progress: String) -> Int {
        generation &+= 1; isBusy = true; self.progress = progress; error = nil; success = nil; resultWarnings = []
        return generation
    }
    private func finish() { isBusy = false; isApplying = false; progress = ""; work = nil }
    private func failed(_ failure: Error, token: Int) {
        guard generation == token else { return }
        finish()
        guard !(failure is CancellationError) else { return }
        error = BackupText.message(failure)
    }
    private enum BackupUIError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
    }
}

@MainActor
final class BackupSettingsController: NSWindowController, NSWindowDelegate {
    let model: BackupSettingsModel
    var onClose: (() -> Void)?
    init(model: BackupSettingsModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 630),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = BackupText.title; window.isReleasedWhenClosed = false; window.animationBehavior = .none
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: BackupSettingsView(model: model,
            chooseExport: { [weak self] in self?.chooseExport() }, chooseImport: { [weak self] in self?.chooseImport() },
            close: { [weak self] in self?.window?.performClose(nil) }))
        window.center()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func show(mode: BackupSettingsModel.Mode = .export) {
        model.reset(mode: mode)
        NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
    func cancelPendingWork() { model.cancelPendingWork() }
    func prepareForTermination() async { await model.prepareForTermination() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !model.isApplying }
    func windowWillClose(_ notification: Notification) {
        model.cancelPendingWork(); window?.makeFirstResponder(nil); onClose?()
    }
    private func chooseExport() {
        guard let window, !model.isBusy, model.validateExport() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = model.passwordProtected ? "Cue-settings-encrypted.json" : "Cue-settings.json"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.window?.isVisible == true, response == .OK, let url = panel.url else { return }
            self.model.export(to: url)
        }
    }
    private func chooseImport() {
        guard let window, !model.isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.window?.isVisible == true, response == .OK, let url = panel.url else { return }
            self.model.load(from: url)
        }
    }
}

struct BackupSettingsView: View {
    @ObservedObject var model: BackupSettingsModel
    let chooseExport: () -> Void
    let chooseImport: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text(BackupText.export).tag(BackupSettingsModel.Mode.export)
                Text(BackupText.importFile).tag(BackupSettingsModel.Mode.import)
            }.pickerStyle(.segmented).disabled(model.isBusy).accessibilityLabel(BackupText.title)
            ScrollView { document.frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            HStack(spacing: 12) {
                if model.isBusy { ProgressView().controlSize(.small); Text(model.progress).font(.caption) }
                Spacer()
                Button(model.isBusy && !model.isApplying ? BackupText.cancel : BackupText.done, action: close)
                    .keyboardShortcut(.cancelAction).disabled(model.isApplying)
                if model.mode == .export {
                    Button(BackupText.exportButton, action: chooseExport).keyboardShortcut(.defaultAction).disabled(model.isBusy)
                } else if model.needsPassword {
                    Button(BackupText.unlock) { model.unlock() }.keyboardShortcut(.defaultAction)
                        .disabled(model.isBusy || model.importPassword.isEmpty)
                } else if model.preview != nil {
                    Button(BackupText.apply) { model.apply() }.keyboardShortcut(.defaultAction).disabled(!model.canApply)
                }
            }
        }.padding(20).frame(width: 630, height: 630)
    }
    var document: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.mode == .export { exportContent } else { importContent }
            if let error = model.error { message(error, color: .red) }
            if let success = model.success { message(success, color: .secondary) }
            ForEach(Array(model.resultWarnings.enumerated()), id: \.offset) { _, warning in message(warning, color: .orange) }
        }
    }
    private var exportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            message(BackupText.exportHelp)
            card {
                Toggle(BackupText.protect, isOn: $model.passwordProtected).font(.headline)
                if model.passwordProtected {
                    SecureField(BackupText.password, text: $model.exportPassword)
                    SecureField(BackupText.confirmPassword, text: $model.confirmPassword)
                    message(BackupText.protectHelp)
                } else { message(BackupText.plaintextHelp) }
            }
            card {
                Toggle(BackupText.includeKey, isOn: $model.includeAPIKey).disabled(!model.passwordProtected)
                message(BackupText.includeKeyHelp)
            }
        }.textFieldStyle(.roundedBorder).disabled(model.isBusy)
    }
    private var importContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            message(BackupText.importHelp)
            HStack {
                Button(model.filename == nil ? BackupText.choose : BackupText.chooseAnother, action: chooseImport).disabled(model.isBusy)
                if let filename = model.filename { Text(filename).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            if model.needsPassword {
                card {
                    message(BackupText.unlockHelp)
                    SecureField(BackupText.password, text: $model.importPassword).textFieldStyle(.roundedBorder).disabled(model.isBusy)
                }
            }
            if let preview = model.preview {
                Text(BackupText.preview).font(.headline)
                if preview.rows.isEmpty && !model.hasImportedAPIKey { message(BackupText.noPreview) }
                ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in message(warning) }
                ForEach(preview.rows, id: \.section) { row in
                    card {
                        Toggle(BackupText.section(row.section), isOn: Binding(
                            get: { model.selectedSections.contains(row.section) },
                            set: { model.setSelected(row.section, selected: $0) })).font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                            GridRow { Text(BackupText.current).foregroundStyle(.secondary); Text(row.current) }
                            GridRow { Text(BackupText.incoming).foregroundStyle(.secondary); Text(row.incoming) }
                        }.font(.callout).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(row.details.enumerated()), id: \.offset) { _, detail in message(detail) }
                        if row.section == .clipboard, model.selectedSections.contains(.clipboard) {
                            Toggle(BackupText.retentionConsent, isOn: $model.applyRetention)
                            message(BackupText.retentionHelp)
                        }
                    }.disabled(model.isBusy)
                }
                if model.hasImportedAPIKey {
                    card {
                        Toggle(BackupText.restoreKey, isOn: $model.restoreAPIKey)
                        message(BackupText.restoreKeyHelp)
                    }.disabled(model.isBusy)
                }
            }
        }
    }
    private func message(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}
