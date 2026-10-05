import AppKit
import CueCore
import Foundation
import SwiftUI

private actor MemoryFiles {
    var data: [URL: Data] = [:]
    var writes = 0
    func put(_ value: Data, at url: URL) { data[url] = value }
    func read(_ url: URL) throws -> Data {
        guard let value = data[url] else { throw CocoaError(.fileReadNoSuchFile) }
        return value
    }
    func write(_ value: Data, to url: URL) { writes += 1; data[url] = value }
    func count() -> Int { writes }
    var access: BackupFileAccess {
        BackupFileAccess(read: { try await self.read($0) }, write: { await self.write($0, to: $1) })
    }
}

@MainActor private final class FakeService {
    var document: SettingsBackupDocument
    var key: String? = "sk-synthetic-backup-fixture-never-real"
    var keyReads = 0
    var previews = 0
    var applies = 0
    var restoredKey = false
    var appliedRetention = false
    var appliedSections = Set<SettingsBackupSection>()
    var failKey = false
    var failCleanup = false
    var holdApply = false
    var applyGate: CheckedContinuation<Void, Never>?
    init(_ document: SettingsBackupDocument) { self.document = document }
    var service: BackupSettingsService {
        BackupSettingsService(exportDocument: { self.document }, readAPIKeyForExport: {
            self.keyReads += 1; return self.key
        }, preview: { document in
            self.previews += 1
            return SettingsBackupPreview(rows: SettingsBackupSection.allCases.filter { document.sections.available.contains($0) }.map {
                .init(section: $0, current: "Current synthetic choice", incoming: "Incoming synthetic choice",
                      details: $0 == .clipboard ? ["Synthetic retention notice"] : [])
            }, warnings: [])
        }, apply: { _, sections, key, retention in
            self.applies += 1; self.restoredKey = key; self.appliedRetention = retention; self.appliedSections = sections
            if self.holdApply { await withCheckedContinuation { self.applyGate = $0 } }
            return SettingsBackupApplyResult(appliedSections: sections,
                keyStatus: key ? (self.failKey ? .failed : .restored) : .excluded,
                retentionStatus: retention ? (self.failCleanup ? .cleanupFailed : .applied) : .unchanged)
        })
    }
}

@main struct CheckBackupUI {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let document = SettingsBackupDocument(exportedByVersion: "0.10.0", sections: .init(
            general: .init(language: "system", shortcut: .default, display: .pointer, dismissOnFocusLoss: true),
            appAliases: [.init(bundleIdentifier: "com.example.Editor", alias: "ed")],
            conversionAliases: .init(traditional: "st", simplified: "ts"),
            browsers: [.init(bundleIdentifier: "com.example.Browser", name: "Synthetic Browser")],
            gpt: .init(model: "gpt-6-luna", translationTarget: "automatic"),
            clipboard: .init(retention: .week),
            windows: .init(shortcut: .init(keyCode: 46, modifiers: .option, key: "M"), keepModeOpen: false,
                presets: [.init(slot: 1, name: "Left 60%", x: 0, y: 0, width: 0.6, height: 1)])))
        let fake = FakeService(document), files = MemoryFiles()
        let model = BackupSettingsModel(service: fake.service, files: await files.access)
        let plainURL = URL(fileURLWithPath: "/synthetic/plain.json")
        let encryptedURL = URL(fileURLWithPath: "/synthetic/encrypted.json")
        check(!model.passwordProtected && !model.includeAPIKey, "Plain key-free default")
        model.export(to: plainURL)
        await model.waitForCurrentOperation()
        let plain = try await files.read(plainURL)
        check(model.success != nil && model.error == nil, "Plain export completes")
        check(fake.keyReads == 0, "Plain export never reads Keychain")
        check(!(String(data: plain, encoding: .utf8) ?? "").contains(fake.key!), "Plain export omits key")
        model.includeAPIKey = true
        check(!model.validateExport(), "API key requires protection")
        check(fake.keyReads == 0, "Rejected export never reads key")
        model.passwordProtected = true
        model.exportPassword = "short"; model.confirmPassword = "short"
        check(!model.validateExport(), "Reject weak length before Keychain")
        model.exportPassword = "twelve-plus-characters"; model.confirmPassword = "different-password"
        check(!model.validateExport(), "Confirmation mismatch rejected")
        model.confirmPassword = model.exportPassword
        model.export(to: encryptedURL)
        await model.waitForCurrentOperation()
        let encrypted = try await files.read(encryptedURL)
        check(fake.keyReads == 1 && model.success != nil, "Explicit protected export reads key once")
        check(model.exportPassword.isEmpty && model.confirmPassword.isEmpty, "Export clears password fields")
        check(!(String(data: encrypted, encoding: .utf8) ?? "").contains(fake.key!), "Encrypted bytes hide fixture key")
        model.load(from: plainURL)
        await model.waitForCurrentOperation()
        check(model.preview?.rows.count == 7 && !model.needsPassword, "Plain import previews seven sections")
        check(!model.selectedSections.contains(.clipboard), "Destructive retention initially unselected")
        check(!model.restoreAPIKey && !model.hasImportedAPIKey, "Plain import has no key restore")
        model.setSelected(.clipboard, selected: true)
        check(!model.canApply, "Retention needs separate explicit consent")
        model.applyRetention = true
        check(model.canApply, "Retention consent enables apply")
        model.setSelected(.browsers, selected: false)
        model.apply()
        await model.waitForCurrentOperation()
        check(fake.applies == 1 && fake.appliedRetention, "Confirmed retention passed explicitly")
        check(!fake.appliedSections.contains(.browsers) && !fake.restoredKey, "Unselected choices excluded")
        check(model.preview == nil && !model.isBusy, "Applied payload cleared")
        model.load(from: encryptedURL)
        await model.waitForCurrentOperation()
        check(model.needsPassword && model.preview == nil, "Protected file never previews before unlock")
        let previewsBefore = fake.previews
        model.importPassword = "incorrect-password"
        model.unlock(); await model.waitForCurrentOperation()
        check(model.error != nil && model.preview == nil && fake.previews == previewsBefore, "Wrong password changes no settings")
        check(model.importPassword.isEmpty && model.needsPassword, "Wrong password field cleared, retry available")
        model.importPassword = "twelve-plus-characters"
        model.unlock(); await model.waitForCurrentOperation()
        check(model.preview != nil && model.hasImportedAPIKey && !model.restoreAPIKey, "Unlocked key restore remains opt-in")
        check(model.importPassword.isEmpty, "Successful unlock clears password")
        for section in model.selectedSections { model.setSelected(section, selected: false) }
        check(!model.canApply, "No implicit import with empty selection")
        model.restoreAPIKey = true
        check(model.canApply, "Explicit key-only import supported")
        fake.holdApply = true
        model.apply()
        while fake.applyGate == nil { await Task.yield() }
        let controller = BackupSettingsController(model: model)
        check(model.isApplying && !controller.windowShouldClose(controller.window!), "Commit prevents closing until result")
        model.cancelPendingWork()
        check(model.isApplying && model.isBusy, "Cancel does not abandon a settings commit")
        let termination = Task { await model.prepareForTermination() }
        await Task.yield()
        check(model.isApplying, "Termination waits for transaction")
        fake.applyGate?.resume(); fake.applyGate = nil
        await termination.value
        check(!model.isApplying && model.preview == nil && !model.hasImportedAPIKey, "Termination clears sensitive drafts after commit")
        check(fake.restoredKey && fake.appliedSections.isEmpty, "Only selected key was restored")
        fake.holdApply = false; fake.failKey = true
        model.load(from: encryptedURL); await model.waitForCurrentOperation()
        model.importPassword = "twelve-plus-characters"; model.unlock(); await model.waitForCurrentOperation()
        model.restoreAPIKey = true
        model.apply(); await model.waitForCurrentOperation()
        check(!model.resultWarnings.isEmpty && model.success != nil, "Key failure is reported separately from applied settings")
        check(!model.hasImportedAPIKey && model.preview == nil, "Partial result clears credentials rather than auto retry")
        let readGate = ReadGate()
        let delayed = BackupSettingsModel(service: fake.service, files: .init(read: { _ in await readGate.read() }, write: { _, _ in }))
        delayed.load(from: plainURL)
        while !(await readGate.isWaiting()) { await Task.yield() }
        let oldWork = Task { await delayed.waitForCurrentOperation() }
        await Task.yield()
        delayed.cancelPendingWork()
        await readGate.finish(plain)
        await oldWork.value
        check(delayed.preview == nil && delayed.filename == nil && !delayed.isBusy, "Late read cannot repopulate closed settings")
        fake.key = nil
        model.reset(); model.passwordProtected = true; model.includeAPIKey = true
        model.exportPassword = "twelve-plus-characters"; model.confirmPassword = model.exportPassword
        let beforeMissing = await files.count()
        model.export(to: encryptedURL); await model.waitForCurrentOperation()
        let afterMissing = await files.count()
        check(model.error != nil && beforeMissing == afterMissing, "Missing requested key does not silently export an incomplete backup")
        model.reset(); model.passwordProtected = true
        model.exportPassword = "twelve-plus-characters"; model.confirmPassword = model.exportPassword
        let readsBeforeNoKey = fake.keyReads
        model.export(to: encryptedURL); await model.waitForCurrentOperation()
        check(fake.keyReads == readsBeforeNoKey, "Protected settings-only export avoids Keychain too")
        model.exportPassword = "cleared-on-close"; model.confirmPassword = "cleared-on-close"; model.importPassword = "cleared-on-close"
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        check(model.exportPassword.isEmpty && model.confirmPassword.isEmpty && model.importPassword.isEmpty, "Window close clears every password draft")
        // Actual file I/O is restricted to our newly created temporary directory.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cue-backup-ui-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("backup.json")
        try await BackupFileAccess.live.write(plain, destination)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        check(attributes[.posixPermissions] as? Int == 0o600, "Export file owner-only from creation")
        let readback = try await BackupFileAccess.live.read(destination)
        check(readback == plain, "Bounded disk round trip")
        let target = directory.appendingPathComponent("untouched.json")
        try Data("sentinel".utf8).write(to: target)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
        try await BackupFileAccess.live.write(plain, destination)
        let targetData = try Data(contentsOf: target)
        check(targetData == Data("sentinel".utf8), "Atomic publication replaces link, never follows its target")
        let oversized = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 32, count: SettingsBackupCodec.maximumFileBytes + 1).write(to: oversized)
        do { _ = try await BackupFileAccess.live.read(oversized); preconditionFailure("Oversized file accepted") }
        catch { check(error as? SettingsBackupError == .tooLarge, "Oversized read rejected before parsing") }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        check(!remaining.contains(where: { $0.hasPrefix(".cue-backup-") }), "No temporary export files left")
        model.reset(); model.passwordProtected = true
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        check(controller.window?.contentView?.frame.size == NSSize(width: 630, height: 630), "Native backup window stays bounded")
        check(!NSApp.isActive && controller.window?.isVisible == false, "Native checks never activate or display a window")
        if let output = ProcessInfo.processInfo.environment["CUE_BACKUP_PREVIEW_DIRECTORY"] {
            model.reset()
            try render(model, name: "backup-plain-export", directory: output)
            model.passwordProtected = true
            try render(model, name: "backup-protected-export", directory: output)
            model.load(from: plainURL); await model.waitForCurrentOperation()
            model.setSelected(.clipboard, selected: true)
            try render(model, name: "backup-import-preview", directory: output)
            check(model.preview != nil, "Bilingual import document rendered from real view tree")
            await files.put(encrypted, at: encryptedURL)
            model.load(from: encryptedURL); await model.waitForCurrentOperation()
            model.importPassword = "twelve-plus-characters"; model.unlock(); await model.waitForCurrentOperation()
            try render(model, name: "backup-key-import-preview", directory: output)
            check(model.hasImportedAPIKey && !model.restoreAPIKey, "Key preview rendered with explicit restore opt-in")
        }
        check(!NSApp.isActive, "No test takes desktop focus")
        print("Backup UI: \(checks) isolated checks passed")
    }
    @MainActor private static func render(_ model: BackupSettingsModel, name: String, directory: String) throws {
        let view = BackupSettingsView(model: model, chooseExport: {}, chooseImport: {}, close: {})
        let renderer = ImageRenderer(content: view.document.frame(width: 590).padding(20)
            .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        guard let data = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { preconditionFailure("Render failed") }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
}

private actor ReadGate {
    private var continuation: CheckedContinuation<Data, Never>?
    func read() async -> Data { await withCheckedContinuation { continuation = $0 } }
    func isWaiting() -> Bool { continuation != nil }
    func finish(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}
