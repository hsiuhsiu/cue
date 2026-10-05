import AppKit
import CueCore
import Foundation

private actor FlushFixture {
    private var values: [Bool] = []
    private var pauseAt: Int?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func configure(_ values: [Bool], pauseAt: Int? = nil) { self.values = values; self.pauseAt = pauseAt; calls = 0 }
    func flush() async -> Bool {
        calls += 1
        let number = calls
        if pauseAt == number { await withCheckedContinuation { continuation = $0 } }
        return values.indices.contains(number - 1) ? values[number - 1] : true
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor KeyFixture {
    private(set) var reads = 0
    private(set) var saves: [String] = []
    var fails = false
    func setFails(_ value: Bool) { fails = value }
    func read() -> String? { reads += 1; return "synthetic-secret-for-export-only" }
    func save(_ key: String) throws {
        if fails { throw GPTKeychainError.accessDenied }
        saves.append(key)
    }
}

@MainActor private final class Fixture {
    let root: URL
    let domain: String
    let defaults: UserDefaults
    let settings: CueSettings
    let aliases: AppAliasPreferences
    let conversion: ChineseConversionPreferences
    let browsers: WebSearchPreferences
    let gpt: GPTPreferences
    let clipboard: ClipboardModel
    let windows: WindowControlPreferences
    let board: NSPasteboard
    let flush = FlushFixture()
    let keys = KeyFixture()
    var shortcutCalls: [(LauncherShortcut, WindowControlConfiguration)] = []
    var denyShortcut = false
    var credentialsChanged = 0

    init() throws {
        domain = "com.yyhsiu.cue.tests.backup.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent(domain, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults.set(false, forKey: "networkAccessAllowed")
        defaults.set(true, forKey: "updates.automaticChecksEnabled")
        defaults.set(false, forKey: "webSearch.enabled")
        defaults.set(false, forKey: "clipboard.recordingEnabled")
        defaults.set("forever", forKey: "clipboard.retention")
        defaults.set(["en"], forKey: "AppleLanguages")
        defaults.set("keep unrelated local data", forKey: "unrelated.fixture")
        defaults.set(["bundle:local.app": "local", "path:/Synthetic/Path.app": "pathonly"], forKey: AppAliasPreferences.storageKey)
        settings = CueSettings(defaults: defaults, domainName: domain)
        aliases = AppAliasPreferences(defaults: defaults)
        conversion = ChineseConversionPreferences(defaults: defaults)
        browsers = WebSearchPreferences(defaults: defaults)
        gpt = GPTPreferences(defaults: defaults)
        board = NSPasteboard(name: .init(domain))
        precondition(board.name != .general)
        clipboard = ClipboardModel(defaults: defaults, fileURL: root.appendingPathComponent("Clipboard/history.json"), pasteboardName: board.name)
        windows = WindowControlPreferences(fileURL: root.appendingPathComponent("WindowControls/settings.json"))
    }

    func prepare() async throws {
        await windows.load()
        _ = windows.setEnabled(true)
        _ = windows.savePreset(.init(slot: 1, name: "Local preset", x: 0, y: 0, width: 0.5, height: 1))
        await windows.flush()
        try browsers.add(.init(bundleIdentifier: "org.test.localbrowser", name: "Local Browser"))
        for _ in 0..<200 {
            if !clipboard.isLoading { break }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func coordinator() -> SettingsBackupCoordinator {
        SettingsBackupCoordinator(settings: settings, aliases: aliases, conversion: conversion, browsers: browsers,
            gpt: gpt, clipboard: clipboard, windows: windows, defaults: defaults, exportedByVersion: "0.9.0",
            applyShortcuts: { [self] shortcut, config in
                if denyShortcut { return "Synthetic hotkey conflict" }
                shortcutCalls.append((shortcut, config)); return nil
            }, flushDefaults: { [flush] in await flush.flush() },
            unavailableApplications: { identifiers in Set(identifiers.filter { $0 == "new.app" || $0 == "org.test.browser" }) },
            readKey: { [keys] in await keys.read() }, saveKey: { [keys] in try await keys.save($0) },
            onCredentialsChange: { [weak self] in self?.credentialsChanged += 1 })
    }

    func finish() async {
        await clipboard.prepareForTermination()
        await windows.flush()
        defaults.removePersistentDomain(forName: domain)
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }
}

/// Runtime preferences use only isolated suites, named pasteboards, temporary
/// files, and injected hotkeys/key storage. No desktop or network operations.
@main struct CheckSettingsBackup {
    @MainActor private static var checks = 0
    @MainActor private static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }
    @MainActor private static func rejects(_ message: String, _ operation: () async throws -> Void) async {
        do { try await operation(); check(false, message) }
        catch { checks += 1 }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.mainMenu = nil
        try await checkExportAndMerge()
        try await checkFailuresAndSecrets()
        try await checkRetentionTransaction()
        try await checkLocalShortcutAndFileFailure()
        check(!NSApplication.shared.isActive && NSApplication.shared.windows.allSatisfy { !$0.isVisible }, "Never activate or present a window")
        print("Settings backup coordinator passed: \(checks) checks; isolated preferences/files and mock keys/hotkeys only.")
    }

    private static func incoming() -> SettingsBackupDocument {
        .init(exportedByVersion: "0.9.0", sections: .init(
            general: .init(language: "zh-Hant", shortcut: .init(keyCode: 37, modifiers: .control, key: "L"), display: .main, dismissOnFocusLoss: false),
            appAliases: [.init(bundleIdentifier: "new.app", alias: "newalias")],
            conversionAliases: .init(traditional: "trad", simplified: "simp"),
            browsers: [.init(bundleIdentifier: "org.test.browser", name: "Imported Browser")],
            gpt: .init(model: "gpt-synthetic-model", translationTarget: "english"),
            clipboard: .init(retention: .hour),
            windows: .init(shortcut: .init(keyCode: 35, modifiers: .option, key: "P"), keepModeOpen: true,
                presets: [.init(slot: 3, name: "Imported preset", x: 0.5, y: 0, width: 0.5, height: 1)])))
    }

    @MainActor private static func checkExportAndMerge() async throws {
        let fixture = try Fixture(); try await fixture.prepare()
        let coordinator = fixture.coordinator()
        let exported = try await coordinator.exportDocument()
        let text = String(decoding: try JSONEncoder().encode(exported), as: UTF8.self)
        check(exported.sections.appAliases?.map(\.bundleIdentifier) == ["local.app"], "Export includes only portable bundle-ID aliases")
        check(!text.contains("/Synthetic/") && !text.contains("apiKey") && !text.contains("networkAccessAllowed")
            && !text.contains("enabled") && !text.contains("history.json"), "Export excludes secrets, paths, content, and local enable flags")
        check(await fixture.keys.reads == 0, "Ordinary export never reads Keychain")
        let preview = try await coordinator.preview(incoming())
        check(preview.rows.count == 7 && preview.warnings.count >= 2, "Preview lists every present section and preserved local settings/path exclusions")
        check(preview.rows.first { $0.section == .appAliases }?.details.contains { $0.contains("new.app") } == true,
            "Unavailable App identity is shown in preview without launching it")
        check(preview.rows.first { $0.section == .windows }?.incoming.contains("Local preset") == true,
            "Preview shows merged presets rather than implying unlisted items are deleted")
        check(await fixture.keys.reads == 0 && fixture.shortcutCalls.isEmpty, "Preview never reads a key or registers hotkeys")
        let decoded = SettingsBackupDecoded(document: incoming(), apiKey: nil, isEncrypted: false)
        let result = try await coordinator.apply(decoded, sections: incoming().sections.available)
        check(result.appliedSections.count == 6 && !result.appliedSections.contains(.clipboard), "Retention requires separate opt-in even when its section was selected")
        check(fixture.settings.language == .traditionalChinese && fixture.settings.preferences.display == .main, "General portable choices apply")
        check(fixture.aliases.aliases["bundle:local.app"] == "local" && fixture.aliases.aliases["bundle:new.app"] == "newalias"
            && fixture.aliases.aliases["path:/Synthetic/Path.app"] == "pathonly", "Imported aliases merge and preserve local path-only aliases")
        check(fixture.browsers.browsers.map(\.bundleIdentifier) == ["org.test.browser", "org.test.localbrowser"], "Explicit browser order imports while unlisted browsers remain")
        check(fixture.windows.snapshot.presets.map(\.slot) == [1, 3] && fixture.windows.snapshot.enabled, "Presets merge by slot and window enablement stays local")
        check(fixture.clipboard.retention == .forever && !fixture.clipboard.recordingEnabled
            && !fixture.browsers.isEnabled && !fixture.defaults.bool(forKey: "networkAccessAllowed")
            && fixture.defaults.bool(forKey: "updates.automaticChecksEnabled"), "Import preserves local network, update, recording and browser enable flags")
        check(fixture.defaults.string(forKey: "unrelated.fixture") == "keep unrelated local data", "Import does not replace the whole preferences domain")
        let persisted = try JSONDecoder().decode(WindowControlConfiguration.self, from: Data(contentsOf: fixture.windows.fileURL))
        check(persisted == fixture.windows.snapshot && fixture.shortcutCalls.count == 1, "Import waits for window persistence and applies the combined hotkey pair once")
        let after = try await coordinator.exportDocument()
        check(after.sections.gpt?.model == "gpt-synthetic-model" && after.sections.conversionAliases?.traditional == "trad", "Feature values round-trip from their live stores")
        await fixture.finish()
    }

    @MainActor private static func checkFailuresAndSecrets() async throws {
        let fixture = try Fixture(); try await fixture.prepare()
        let coordinator = fixture.coordinator()
        let before = try await coordinator.exportDocument()
        let incoming = incoming()
        let decoded = SettingsBackupDecoded(document: incoming, apiKey: nil, isEncrypted: false)
        fixture.denyShortcut = true
        await rejects("An occupied hotkey must fail before changing preferences") {
            _ = try await coordinator.apply(decoded, sections: incoming.sections.available)
        }
        check(try await coordinator.exportDocument() == before && fixture.shortcutCalls.isEmpty, "Hotkey failure leaves all saved values untouched")
        fixture.denyShortcut = false
        await fixture.flush.configure([true, false, true])
        await rejects("A failed persistence acknowledgement must roll back the imported snapshot") {
            _ = try await coordinator.apply(decoded, sections: incoming.sections.available, applyRetention: true)
        }
        check(try await coordinator.exportDocument() == before, "Rollback restores general and feature settings, including retention")
        check(fixture.shortcutCalls.count == 2 && fixture.shortcutCalls.last?.0 == before.sections.general?.shortcut,
            "Persistence failure restores the earlier combined hotkey registration")
        let persisted = try JSONDecoder().decode(WindowControlConfiguration.self, from: Data(contentsOf: fixture.windows.fileURL))
        check(persisted == fixture.windows.snapshot && persisted.presets.count == 1, "Rollback is flushed to the window settings file")
        await fixture.flush.configure([])
        let conflict = SettingsBackupDocument(exportedByVersion: "0.9.0", sections: .init(appAliases: [.init(bundleIdentifier: "other.app", alias: "local")]))
        await rejects("Incoming alias must be checked against retained aliases before writes") {
            _ = try await coordinator.apply(.init(document: conflict, apiKey: nil, isEncrypted: false), sections: [.appAliases])
        }
        check(try await coordinator.exportDocument() == before, "Merged conflict rejection leaves settings intact")
        let key = "synthetic-imported-secret-for-fixtures"
        let plaintextKey = SettingsBackupDecoded(document: incoming, apiKey: key, isEncrypted: false)
        await rejects("Credential restore must require an authenticated encrypted backup") {
            _ = try await coordinator.apply(plaintextKey, sections: [.gpt], restoreAPIKey: true)
        }
        check(await fixture.keys.saves.isEmpty, "Rejected plaintext credentials never reach the key store")
        let encrypted = SettingsBackupDecoded(document: incoming, apiKey: key, isEncrypted: true)
        _ = try await coordinator.apply(encrypted, sections: [.gpt])
        check(await fixture.keys.saves.isEmpty, "Encrypted backups still exclude the key unless explicitly selected")
        let restored = try await coordinator.apply(encrypted, sections: [], restoreAPIKey: true)
        check(restored.keyStatus == .restored && fixture.credentialsChanged == 1, "Explicit key import reports success and invalidates active GPT work")
        check(await fixture.keys.saves == [key], "Only the selected synthetic key reaches the injected store")
        await fixture.keys.setFails(true)
        let keyFailure = try await coordinator.apply(encrypted, sections: [.general], restoreAPIKey: true)
        check(keyFailure.keyStatus == .failed && keyFailure.appliedSections == [.general]
            && fixture.settings.language == .traditionalChinese, "Keychain failure is reported separately from successfully imported settings")
        check(try await coordinator.readAPIKeyForExport() == "synthetic-secret-for-export-only", "Explicit encrypted-export opt-in uses the injected key reader")
        check(await fixture.keys.reads == 1, "Key export reads exactly once and never during preview")
        await fixture.finish()
    }

    @MainActor private static func checkLocalShortcutAndFileFailure() async throws {
        let fixture = try Fixture(); try await fixture.prepare()
        let coordinator = fixture.coordinator()
        _ = fixture.windows.setEnabled(false)
        await fixture.windows.flush()
        let sameShortcut = SettingsBackupDocument(exportedByVersion: "0.9.0", sections: .init(general: .init(
            language: "en", shortcut: WindowControlConfiguration.defaultShortcut, display: .pointer, dismissOnFocusLoss: true)))
        let decoded = SettingsBackupDecoded(document: sameShortcut, apiKey: nil, isEncrypted: false)
        _ = try await coordinator.apply(decoded, sections: [.general])
        check(fixture.settings.preferences.shortcut == fixture.windows.snapshot.shortcut && !fixture.windows.snapshot.enabled,
              "A disabled window feature may store the same shortcut as the active launcher")
        check(try await coordinator.exportDocument().sections.general?.shortcut == WindowControlConfiguration.defaultShortcut,
              "Legitimate disabled-feature shortcut preferences remain exportable")
        fixture.settings.preferences = .init()
        _ = fixture.windows.setEnabled(true)
        await fixture.windows.flush()
        await rejects("The same imported shortcut conflicts when window controls are enabled on this Mac") {
            _ = try await coordinator.apply(decoded, sections: [.general])
        }
        check(fixture.settings.preferences.shortcut == .default && fixture.windows.snapshot.enabled,
              "An enabled-feature conflict preserves both current shortcut choices")
        let before = try await coordinator.exportDocument()
        let originalFile = try Data(contentsOf: fixture.windows.fileURL)
        try FileManager.default.removeItem(at: fixture.windows.fileURL)
        try FileManager.default.createDirectory(at: fixture.windows.fileURL, withIntermediateDirectories: false)
        let replacement = SettingsBackupDocument(exportedByVersion: "0.9.0", sections: .init(windows: .init(
            shortcut: WindowControlConfiguration.defaultShortcut, keepModeOpen: true,
            presets: [.init(slot: 7, name: "Cannot persist", x: 0, y: 0, width: 1, height: 1)])))
        await rejects("A real window-settings file write failure must not be reported as a successful import") {
            _ = try await coordinator.apply(.init(document: replacement, apiKey: nil, isEncrypted: false), sections: [.windows])
        }
        check(fixture.windows.persistenceError != nil && fixture.windows.snapshot.keepModeOpen == false
              && fixture.windows.snapshot.presets.map(\.slot) == [1],
              "Even when disk rollback cannot complete, runtime settings revert and expose the persistence failure")
        check(try await coordinator.exportDocument() == before, "File write failure preserves unrelated live preferences")
        try FileManager.default.removeItem(at: fixture.windows.fileURL)
        try originalFile.write(to: fixture.windows.fileURL, options: .atomic)
        fixture.windows.retrySave()
        await fixture.windows.flush()
        check(fixture.windows.persistenceError == nil, "The synthetic file fixture can recover and persist the original settings")
        await fixture.finish()
    }

    @MainActor private static func checkRetentionTransaction() async throws {
        let fixture = try Fixture(); try await fixture.prepare()
        // Capture only synthetic content on the private pasteboard. The old item
        // is seeded into a separate store before this model opens its history.
        let historyURL = fixture.root.appendingPathComponent("Retention/history.json")
        _ = try await ClipboardStore(fileURL: historyURL).record(text: "Synthetic older retained item", retention: .forever,
                                                                now: Date().addingTimeInterval(-7_200))
        let history = ClipboardModel(defaults: fixture.defaults, fileURL: historyURL, pasteboardName: fixture.board.name)
        for _ in 0..<200 { if !history.isLoading { break }; try await Task.sleep(for: .milliseconds(5)) }
        let coordinator = SettingsBackupCoordinator(settings: fixture.settings, aliases: fixture.aliases, conversion: fixture.conversion,
            browsers: fixture.browsers, gpt: fixture.gpt, clipboard: history, windows: fixture.windows, defaults: fixture.defaults,
            applyShortcuts: { _, _ in nil }, flushDefaults: { [flush = fixture.flush] in await flush.flush() },
            unavailableApplications: { _ in [] }, readKey: { nil }, saveKey: { _ in })
        await fixture.flush.configure([true, false, true], pauseAt: 2)
        let doc = SettingsBackupDocument(exportedByVersion: "0.9.0", sections: .init(clipboard: .init(retention: .hour)))
        let task = Task { try await coordinator.apply(.init(document: doc, apiKey: nil, isEncrypted: false), sections: [.clipboard], applyRetention: true) }
        for _ in 0..<200 { if await fixture.flush.calls == 2 { break }; try await Task.sleep(for: .milliseconds(5)) }
        check(coordinator.isApplying && history.retention == .forever, "Pending persistence keeps live retention unchanged")
        history.open() // Runs ordinary opening-time maintenance while the import is waiting.
        for _ in 0..<200 { if history.results.count == 1 { break }; try await Task.sleep(for: .milliseconds(5)) }
        check(history.results.count == 1, "Background maintenance does not apply an uncommitted shorter retention")
        await rejects("Concurrent imports must not interleave their snapshots") {
            _ = try await coordinator.apply(.init(document: doc, apiKey: nil, isEncrypted: false), sections: [.clipboard], applyRetention: true)
        }
        await fixture.flush.release()
        await rejects("The staged failing retention import must fail after rollback") { _ = try await task.value }
        let retained = try await ClipboardStore(fileURL: historyURL).load(retention: .forever)
        check(retained.count == 1 && history.retention == .forever && fixture.defaults.string(forKey: "clipboard.retention") == "forever",
            "Rollback preserves old clipboard content and both persisted/live retention")
        await fixture.flush.configure([])
        let applied = try await coordinator.apply(.init(document: doc, apiKey: nil, isEncrypted: false), sections: [.clipboard], applyRetention: true)
        check(applied.retentionStatus == .applied && history.retention == .hour, "Confirmed retention activates only after successful persistence")
        let cleaned = try await ClipboardStore(fileURL: historyURL).load(retention: .forever)
        check(cleaned.isEmpty, "Only successful explicitly confirmed retention deletes the expired synthetic item")
        await history.prepareForTermination()
        await fixture.finish()
    }
}
