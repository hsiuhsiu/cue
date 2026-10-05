import AppKit
import CueCore
import Foundation

private enum BackupCoordinatorText {
    static func text(_ key: String, _ fallback: String) -> String {
        L10n.string(key, table: "BackupCoordinator", value: fallback)
    }
    static let busy = text("error.busy", "Another settings import is in progress.")
    static let unavailable = text("error.unavailable", "Wait for settings to finish loading, then try again.")
    static let changed = text("error.changed", "Settings changed while preparing the import. Review the file again.")
    static let save = text("error.save", "Couldn’t save the imported settings. The previous settings were restored.")
    static let rollback = text("error.rollback", "Import failed and some previous settings could not be restored. Check Cue and Window Settings before continuing.")
    static let invalid = text("error.invalid", "The selected settings conflict with this Mac’s current preferences.")
    static let key = text("error.key", "An API key can only be restored from a valid encrypted backup.")
    static let none = text("none", "None")
    static let unavailableApp = text("app.unavailable", "%@ is not installed on this Mac; its saved choice will remain unavailable.")
    static let pathAliases = text("aliases.local", "Aliases tied only to a local file path stay on this Mac and are not included in the backup.")
    static let retention = text("retention.warning", "Applying this retention period can delete older history on this Mac. It requires the separate retention confirmation.")
    static let shortcutConflict = text("shortcut.conflict", "The launcher and window-mode shortcuts conflict. Change one before importing.")
    static let localFlags = text("local.preserved", "This Mac’s network access, recording, feature enablement, automatic updates, login items, and permissions stay unchanged.")
    static let language = text("summary.language", "Language")
    static let shortcut = text("summary.shortcut", "Shortcut")
    static let display = text("summary.display", "Display")
    static let focus = text("summary.focus", "Dismiss on focus loss")
    static let model = text("summary.model", "Model")
    static let translation = text("summary.translation", "Translation")
    static let keepOpen = text("summary.keep_open", "Keep window mode open")
    static let system = text("language.system", "Follow System")
    static let pointer = text("display.pointer", "Display with pointer")
    static let mainDisplay = text("display.main", "Main display")
    static let automatic = text("translation.automatic", "Automatic: Chinese ↔ English")
    static let traditional = text("translation.traditional", "Traditional Chinese (Taiwan)")
    static let english = text("translation.english", "English")
    static let toTraditional = text("conversion.traditional", "To Traditional Chinese")
    static let toSimplified = text("conversion.simplified", "To Simplified Chinese")
    static let hour = text("retention.hour", "1 hour")
    static let day = text("retention.day", "1 day")
    static let week = text("retention.week", "7 days")
    static let month = text("retention.month", "30 days")
    static let forever = text("retention.forever", "No time limit")
    static let on = text("on", "On")
    static let off = text("off", "Off")
}

/// UserDefaults is documented as thread safe. Only an explicit backup commit
/// waits for its persistence acknowledgement; the typing path never does.
private final class BackupDefaultsFlusher: @unchecked Sendable {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults) { self.defaults = defaults }
    func flush() async -> Bool {
        await Task.detached(priority: .utility) { [self] in defaults.synchronize() }.value
    }
}

/// Bounded snapshots bridge the portable file schema and the live feature stores.
/// All key access is explicit; no key, history, or network operation is part of preview.
@MainActor
final class SettingsBackupCoordinator {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Snapshot: Equatable {
        var language: AppLanguage
        var launcher: LauncherPreferences
        var aliases: [String: String]
        var conversion: ChineseConversionAliases
        var browsers: [WebSearchBrowser]
        var gpt: GPTConfiguration
        var retention: ClipboardRetention
        var windows: WindowControlConfiguration
    }

    private let settings: CueSettings
    private let aliases: AppAliasPreferences
    private let conversion: ChineseConversionPreferences
    private let browsers: WebSearchPreferences
    private let gpt: GPTPreferences
    private let clipboard: ClipboardModel
    private let windows: WindowControlPreferences
    private let applyShortcuts: (LauncherShortcut, WindowControlConfiguration) -> String?
    private let flushDefaults: @Sendable () async -> Bool
    private let unavailableApplications: @Sendable ([String]) async -> Set<String>
    private let readKey: @Sendable () async throws -> String?
    private let saveKey: @Sendable (String) async throws -> Void
    private let onCredentialsChange: () -> Void
    private let exportedByVersion: String
    private(set) var isApplying = false

    init(settings: CueSettings, aliases: AppAliasPreferences, conversion: ChineseConversionPreferences,
         browsers: WebSearchPreferences, gpt: GPTPreferences, clipboard: ClipboardModel,
         windows: WindowControlPreferences, defaults: UserDefaults = .standard,
         exportedByVersion: String = AppVersion().displayVersion ?? "development",
         applyShortcuts: @escaping (LauncherShortcut, WindowControlConfiguration) -> String?,
         flushDefaults: (@Sendable () async -> Bool)? = nil,
         unavailableApplications: @escaping @Sendable ([String]) async -> Set<String> = SettingsBackupCoordinator.findUnavailable,
         readKey: @escaping @Sendable () async throws -> String? = SettingsBackupCoordinator.readStoredKey,
         saveKey: @escaping @Sendable (String) async throws -> Void = SettingsBackupCoordinator.saveStoredKey,
         onCredentialsChange: @escaping () -> Void = {}) {
        self.settings = settings; self.aliases = aliases; self.conversion = conversion
        self.browsers = browsers; self.gpt = gpt; self.clipboard = clipboard; self.windows = windows
        self.applyShortcuts = applyShortcuts
        self.exportedByVersion = exportedByVersion
        if let flushDefaults { self.flushDefaults = flushDefaults }
        else {
            let flusher = BackupDefaultsFlusher(defaults)
            self.flushDefaults = { await flusher.flush() }
        }
        self.unavailableApplications = unavailableApplications
        self.readKey = readKey; self.saveKey = saveKey
        self.onCredentialsChange = onCredentialsChange
    }

    func exportDocument() async throws -> SettingsBackupDocument {
        try await requireReady()
        return try document(from: snapshot()).validated()
    }

    /// Call only after the user selected an encrypted export including their key.
    func readAPIKeyForExport() async throws -> String? {
        try Task.checkCancellation()
        let key = try await readKey()
        try Task.checkCancellation()
        return key
    }

    func preview(_ document: SettingsBackupDocument) async throws -> SettingsBackupPreview {
        try await requireReady()
        let document = try document.validated()
        let before = snapshot()
        let incoming = merged(document, into: before, sections: document.sections.available)
        let identifiers = Set((document.sections.appAliases ?? []).map(\.bundleIdentifier)
            + (document.sections.browsers ?? []).map(\.bundleIdentifier))
        let unavailable = await unavailableApplications(Array(identifiers).sorted())
        try Task.checkCancellation()
        guard snapshot() == before else { throw Failure(message: BackupCoordinatorText.changed) }
        var warnings = [BackupCoordinatorText.localFlags]
        if before.aliases.keys.contains(where: { $0.hasPrefix("path:") }) { warnings.append(BackupCoordinatorText.pathAliases) }
        if let error = validationError(incoming) { warnings.append(error) }
        let rows = SettingsBackupSection.allCases.filter { document.sections.available.contains($0) }.map { section in
            var details: [String] = []
            let ids: [String]
            switch section {
            case .appAliases: ids = (document.sections.appAliases ?? []).map(\.bundleIdentifier)
            case .browsers: ids = (document.sections.browsers ?? []).map(\.bundleIdentifier)
            default: ids = []
            }
            for identifier in ids where unavailable.contains(identifier) {
                details.append(L10n.format(BackupCoordinatorText.unavailableApp, identifier))
            }
            if section == .clipboard { details.append(BackupCoordinatorText.retention) }
            return SettingsBackupPreview.Row(section: section, current: summary(before, section),
                                             incoming: summary(incoming, section), details: details)
        }
        return SettingsBackupPreview(rows: rows, warnings: warnings)
    }

    func apply(_ decoded: SettingsBackupDecoded, sections: Set<SettingsBackupSection>,
               restoreAPIKey: Bool = false, applyRetention: Bool = false) async throws -> SettingsBackupApplyResult {
        guard !isApplying else { throw Failure(message: BackupCoordinatorText.busy) }
        isApplying = true
        defer { isApplying = false }
        try await requireReady()
        try Task.checkCancellation()
        let document = try decoded.document.validated()
        if restoreAPIKey {
            guard decoded.isEncrypted, let key = decoded.apiKey, GPTKeychain.isValidKey(key) else {
                throw Failure(message: BackupCoordinatorText.key)
            }
        }
        var selected = sections.intersection(document.sections.available)
        if !applyRetention { selected.remove(.clipboard) }
        let before = snapshot()
        let candidate = merged(document, into: before, sections: selected)
        if let message = validationError(candidate) { throw Failure(message: message) }
        // Flush previously accepted local edits first. A failure must not be
        // mistaken for a successful import or overwrite an existing corrupt file.
        await windows.flush()
        guard windows.persistenceError == nil, await flushDefaults() else { throw Failure(message: BackupCoordinatorText.unavailable) }
        try Task.checkCancellation()
        guard snapshot() == before else { throw Failure(message: BackupCoordinatorText.changed) }
        var runtimeApplied = false
        do {
            if let error = applyShortcuts(candidate.launcher.shortcut, candidate.windows) { throw Failure(message: error) }
            runtimeApplied = true
            try commit(candidate)
            await windows.flush()
            guard windows.persistenceError == nil, await flushDefaults() else { throw Failure(message: BackupCoordinatorText.save) }
            try Task.checkCancellation()
        } catch {
            // Registration failure is atomic in the injected runtime hook; no
            // setting changed yet, so there is nothing to roll back in that case.
            guard runtimeApplied else { throw error }
            let runtimeRollbackError = applyShortcuts(before.launcher.shortcut, before.windows)
            do { try commit(before) }
            catch { throw Failure(message: BackupCoordinatorText.rollback) }
            await windows.flush()
            let defaultsRestored = await flushDefaults()
            guard runtimeRollbackError == nil, windows.persistenceError == nil, defaultsRestored else {
                throw Failure(message: BackupCoordinatorText.rollback)
            }
            if error is CancellationError { throw error }
            throw Failure(message: BackupCoordinatorText.save)
        }
        // Retention is intentionally last: deleting old content is not rollbackable.
        let retentionStatus: SettingsBackupApplyResult.RetentionStatus
        if selected.contains(.clipboard), candidate.retention != before.retention {
            retentionStatus = await clipboard.finishImportedRetention(candidate.retention) ? .applied : .cleanupFailed
        } else { retentionStatus = .unchanged }
        var keyStatus = SettingsBackupApplyResult.KeyStatus.excluded
        if restoreAPIKey, let key = decoded.apiKey {
            do {
                try Task.checkCancellation()
                try await saveKey(key)
                onCredentialsChange()
                keyStatus = .restored
            } catch { keyStatus = .failed }
        }
        return SettingsBackupApplyResult(appliedSections: selected, keyStatus: keyStatus, retentionStatus: retentionStatus)
    }

    private func requireReady() async throws {
        await windows.load()
        guard windows.hasLoaded, windows.loadError == nil else { throw Failure(message: BackupCoordinatorText.unavailable) }
    }

    private func snapshot() -> Snapshot {
        Snapshot(language: settings.language, launcher: settings.preferences, aliases: aliases.aliases,
                 conversion: conversion.aliases, browsers: browsers.browsers, gpt: gpt.configuration,
                 retention: clipboard.retention, windows: windows.snapshot)
    }

    private func document(from value: Snapshot) -> SettingsBackupDocument {
        let portableAliases = value.aliases.keys.sorted().compactMap { identifier -> SettingsBackupAppAlias? in
            guard identifier.hasPrefix("bundle:"), let alias = value.aliases[identifier] else { return nil }
            return .init(bundleIdentifier: String(identifier.dropFirst("bundle:".count)), alias: alias)
        }
        return SettingsBackupDocument(exportedByVersion: exportedByVersion, sections: .init(
            general: .init(language: value.language.rawValue, shortcut: value.launcher.shortcut,
                           display: value.launcher.display, dismissOnFocusLoss: value.launcher.dismissOnFocusLoss),
            appAliases: portableAliases,
            conversionAliases: .init(traditional: value.conversion.traditional, simplified: value.conversion.simplified),
            browsers: value.browsers.map { .init(bundleIdentifier: $0.bundleIdentifier, name: $0.name) },
            gpt: .init(model: value.gpt.model, translationTarget: value.gpt.translationTarget.rawValue),
            clipboard: .init(retention: value.retention),
            windows: .init(shortcut: value.windows.shortcut, keepModeOpen: value.windows.keepModeOpen, presets: value.windows.presets)
        ))
    }

    private func merged(_ document: SettingsBackupDocument, into before: Snapshot,
                        sections: Set<SettingsBackupSection>) -> Snapshot {
        var value = before
        let imported = document.sections
        if sections.contains(.general), let general = imported.general {
            value.language = AppLanguage(rawValue: general.language) ?? .system
            value.launcher = .init(shortcut: general.shortcut, display: general.display, dismissOnFocusLoss: general.dismissOnFocusLoss)
        }
        if sections.contains(.appAliases), let additions = imported.appAliases {
            for alias in additions { value.aliases["bundle:" + alias.bundleIdentifier.lowercased()] = alias.alias }
        }
        if sections.contains(.conversionAliases), let aliases = imported.conversionAliases,
           let converted = try? ChineseConversionAliases(traditional: aliases.traditional, simplified: aliases.simplified) {
            value.conversion = converted
        }
        if sections.contains(.browsers), let additions = imported.browsers {
            let ids = Set(additions.map { $0.bundleIdentifier.lowercased() })
            value.browsers = additions.map { .init(bundleIdentifier: $0.bundleIdentifier, name: $0.name) }
                + before.browsers.filter { !ids.contains($0.bundleIdentifier.lowercased()) }
        }
        if sections.contains(.gpt), let gpt = imported.gpt {
            value.gpt = .init(model: gpt.model, translationTarget: GPTTranslationTarget(rawValue: gpt.translationTarget) ?? .automatic)
        }
        if sections.contains(.clipboard), let clipboard = imported.clipboard { value.retention = clipboard.retention }
        if sections.contains(.windows), let windows = imported.windows {
            let slots = Set(windows.presets.map(\.slot))
            value.windows = before.windows.replacing(shortcut: windows.shortcut, keepModeOpen: windows.keepModeOpen,
                presets: windows.presets + before.windows.presets.filter { !slots.contains($0.slot) })
        }
        return value
    }

    private func validationError(_ value: Snapshot) -> String? {
        if let error = AppAliasPreferences.backupValidationError(value.aliases, conversion: value.conversion) { return error }
        guard value.launcher.shortcut.isValid, value.windows.isValid else { return BackupCoordinatorText.invalid }
        if value.windows.enabled, value.windows.shortcut.keyCode == value.launcher.shortcut.keyCode,
           value.windows.shortcut.modifiers == value.launcher.shortcut.modifiers { return BackupCoordinatorText.shortcutConflict }
        if value.windows.enabled, !WindowControlConfiguration.isValidShortcut(value.launcher.shortcut) { return BackupCoordinatorText.shortcutConflict }
        guard value.browsers.count <= WebSearchPreferences.maximumBrowsers,
              (try? value.browsers.map(WebSearchPreferences.validated)) != nil,
              GPTConfiguration.isValidModelID(value.gpt.model) else { return BackupCoordinatorText.invalid }
        return nil
    }

    private func commit(_ value: Snapshot) throws {
        if let error = windows.replaceForBackup(value.windows) { throw Failure(message: error) }
        if let error = aliases.replaceForBackup(value.aliases, conversion: value.conversion) { throw Failure(message: error) }
        conversion.replaceForBackup(value.conversion)
        try browsers.replaceForBackup(value.browsers)
        try gpt.setConfiguration(value.gpt)
        settings.preferences = value.launcher
        settings.language = value.language
        clipboard.stageRetentionForBackup(value.retention)
    }

    private func summary(_ value: Snapshot, _ section: SettingsBackupSection) -> String {
        func flag(_ value: Bool) -> String { value ? BackupCoordinatorText.on : BackupCoordinatorText.off }
        switch section {
        case .general:
            let language = value.language == .system ? BackupCoordinatorText.system : (value.language == .english ? "English" : "正體中文")
            let display = value.launcher.display == .pointer ? BackupCoordinatorText.pointer : BackupCoordinatorText.mainDisplay
            return "\(BackupCoordinatorText.language): \(language)\n\(BackupCoordinatorText.shortcut): \(value.launcher.shortcut.localizedDisplayName)\n\(BackupCoordinatorText.display): \(display)\n\(BackupCoordinatorText.focus): \(flag(value.launcher.dismissOnFocusLoss))"
        case .appAliases:
            return value.aliases.keys.sorted().filter { $0.hasPrefix("bundle:") }.map {
                "\($0.dropFirst("bundle:".count)) → \(value.aliases[$0]!)"
            }.joined(separator: "\n").nonemptyBackupSummary
        case .conversionAliases: return "\(BackupCoordinatorText.toTraditional): \(value.conversion.traditional)\n\(BackupCoordinatorText.toSimplified): \(value.conversion.simplified)"
        case .browsers: return value.browsers.map { "\($0.name) (\($0.bundleIdentifier))" }.joined(separator: "\n").nonemptyBackupSummary
        case .gpt:
            let translation = switch value.gpt.translationTarget {
            case .automatic: BackupCoordinatorText.automatic
            case .traditionalChinese: BackupCoordinatorText.traditional
            case .english: BackupCoordinatorText.english
            }
            return "\(BackupCoordinatorText.model): \(value.gpt.model)\n\(BackupCoordinatorText.translation): \(translation)"
        case .clipboard:
            return switch value.retention {
            case .hour: BackupCoordinatorText.hour
            case .day: BackupCoordinatorText.day
            case .week: BackupCoordinatorText.week
            case .month: BackupCoordinatorText.month
            case .forever: BackupCoordinatorText.forever
            }
        case .windows:
            let geometry = value.windows.presets.map { "\($0.slot). \($0.name): x \(Int(($0.x * 100).rounded()))%, y \(Int(($0.y * 100).rounded()))%, \(Int(($0.width * 100).rounded()))% × \(Int(($0.height * 100).rounded()))%" }.joined(separator: "\n")
            return "\(BackupCoordinatorText.shortcut): \(value.windows.shortcut.localizedDisplayName)\n\(BackupCoordinatorText.keepOpen): \(flag(value.windows.keepModeOpen))\n" + geometry.nonemptyBackupSummary
        }
    }

    nonisolated private static func readStoredKey() async throws -> String? { try await GPTKeychain.shared.read() }
    nonisolated private static func saveStoredKey(_ value: String) async throws { try await GPTKeychain.shared.save(value) }

    nonisolated private static func findUnavailable(_ identifiers: [String]) async -> Set<String> {
        await Task.detached(priority: .utility) {
            var missing = Set<String>()
            for id in identifiers.prefix(AppAliasPreferences.maximumAliases + WebSearchPreferences.maximumBrowsers) {
                if Task.isCancelled { break }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil { missing.insert(id) }
            }
            return missing
        }.value
    }
}

private extension String {
    var nonemptyBackupSummary: String { isEmpty ? BackupCoordinatorText.none : self }
}
