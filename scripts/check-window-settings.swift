import AppKit
import CueCore
import Foundation
import SwiftUI

/// Synthetic storage and offscreen native views only; no desktop activation or real settings.
@main struct CheckWindowSettings {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cue-window-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); count += 1
        }
        let url = root.appendingPathComponent("WindowControls/settings.json")
        let prefs = WindowControlPreferences(fileURL: url)
        expect(!prefs.hasLoaded && !prefs.snapshot.enabled, "Inactive until asynchronous load and registration")
        await prefs.load()
        expect(prefs.hasLoaded && prefs.loadError == nil, "Missing file defaults load")
        expect(prefs.snapshot.enabled && prefs.snapshot.presets.isEmpty, "Missing settings enable the new feature by default")
        expect(prefs.snapshot.shortcut == WindowControlConfiguration.defaultShortcut, "Option M default")
        expect(!FileManager.default.fileExists(atPath: url.path), "Read does not write defaults")
        let conflictURL = root.appendingPathComponent("new-install-conflict/settings.json")
        let newInstallConflict = WindowControlPreferences(fileURL: conflictURL)
        newInstallConflict.applyConfiguration = { $0.enabled ? "Synthetic conflict" : nil }
        await newInstallConflict.load()
        expect(!newInstallConflict.snapshot.enabled && newInstallConflict.runtimeError != nil, "Startup registration conflict disables this session")
        expect(newInstallConflict.setEnabled(true) == "Synthetic conflict", "Registration error exposed")
        expect(!newInstallConflict.snapshot.enabled, "Failed registration rolls back")
        expect(!FileManager.default.fileExists(atPath: conflictURL.path), "Rejected change not saved")
        prefs.applyConfiguration = { _ in nil }
        expect(prefs.setEnabled(false) == nil, "Explicit disable accepted")
        await prefs.flush()
        let explicitlyDisabled = WindowControlPreferences(fileURL: url)
        await explicitlyDisabled.load()
        expect(!explicitlyDisabled.snapshot.enabled, "Explicit saved false survives default-on upgrade")
        expect(prefs.setEnabled(true) == nil, "Enable accepted")
        expect(prefs.runtimeError == nil, "Successful edit clears runtime error")
        await prefs.flush()
        var decoded = try JSONDecoder().decode(WindowControlConfiguration.self, from: Data(contentsOf: url))
        expect(decoded.enabled && decoded.version == 1, "Versioned persistence")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        expect(attributes[.posixPermissions] as? Int == 0o600, "Owner-only config permissions")
        let right = WindowPreset(slot: 9, name: "Right 40%", x: 0.6, y: 0, width: 0.4, height: 1)
        let left = WindowPreset(slot: 1, name: "Left 60%", x: 0, y: 0, width: 0.6, height: 1)
        expect(prefs.savePreset(right) == nil && prefs.savePreset(left) == nil, "Save valid presets")
        expect(prefs.snapshot.presets.map(\.slot) == [1, 9], "Canonical slot order")
        expect(prefs.savePreset(WindowPreset(slot: 1, name: "Bad", x: .nan, y: 0, width: 1, height: 1)) != nil, "Reject nonfinite")
        expect(prefs.savePreset(WindowPreset(slot: 1, name: "Bad", x: 0.9, y: 0, width: 0.5, height: 1)) != nil, "Reject offscreen")
        expect(prefs.snapshot.presets.first == left, "Rejected preset preserves original")
        expect(prefs.setShortcut(LauncherShortcut(keyCode: 123, modifiers: .option, key: "←")) != nil, "Reserve half screen keys")
        expect(prefs.setShortcut(LauncherShortcut(keyCode: 43, modifiers: .command, key: ",")) != nil, "Reserve settings shortcut")
        for i in 0..<50 { expect(prefs.setKeepModeOpen(i % 2 == 0) == nil, "Serial save edit") }
        await prefs.flush()
        decoded = try JSONDecoder().decode(WindowControlConfiguration.self, from: Data(contentsOf: url))
        expect(decoded == prefs.snapshot, "Rapid writes preserve last edit")
        let reload = WindowControlPreferences(fileURL: url)
        await reload.load()
        expect(reload.snapshot == prefs.snapshot, "Portable round trip")
        let conflict = WindowControlPreferences(fileURL: url)
        conflict.applyConfiguration = { $0.enabled ? "Synthetic occupied shortcut" : nil }
        await conflict.load()
        expect(!conflict.snapshot.enabled && conflict.runtimeError != nil, "Startup conflict disables runtime")
        let afterConflict = try JSONDecoder().decode(WindowControlConfiguration.self, from: Data(contentsOf: url))
        expect(afterConflict.enabled, "Startup conflict preserves file")
        expect(prefs.removePreset(slot: 9) == nil, "Delete preset")
        await prefs.flush()
        expect(prefs.snapshot.presets == [left], "Delete is targeted")
        let badURL = root.appendingPathComponent("invalid.json")
        let unsupported = try JSONEncoder().encode(WindowControlConfiguration(version: 999, presets: [left]))
        try unsupported.write(to: badURL)
        let invalid = WindowControlPreferences(fileURL: badURL)
        await invalid.load()
        expect(invalid.hasLoaded && invalid.loadError != nil, "Unsupported schema is blocked")
        expect(!invalid.snapshot.enabled, "Unsupported settings remain inactive")
        expect(invalid.setEnabled(true) != nil, "Invalid file cannot be silently replaced")
        let preserved = try Data(contentsOf: badURL)
        expect(preserved == unsupported, "Unsupported config preserved")
        try JSONEncoder().encode(WindowControlConfiguration(presets: [left])).write(to: badURL)
        await invalid.load()
        expect(invalid.loadError == nil && invalid.snapshot.presets == [left], "Retry loading repaired config")
        let oversized = root.appendingPathComponent("oversized.json")
        try Data(repeating: 32, count: 65_537).write(to: oversized)
        let oversizedPrefs = WindowControlPreferences(fileURL: oversized)
        await oversizedPrefs.load()
        expect(oversizedPrefs.loadError != nil, "Bounded file read")
        let duplicate = root.appendingPathComponent("duplicate.json")
        try JSONEncoder().encode(WindowControlConfiguration(presets: [left, left])).write(to: duplicate)
        let duplicatePrefs = WindowControlPreferences(fileURL: duplicate)
        await duplicatePrefs.load()
        expect(duplicatePrefs.loadError != nil, "Duplicate slots rejected on load")
        let blockedParent = root.appendingPathComponent("blocked")
        let failed = WindowControlPreferences(fileURL: blockedParent.appendingPathComponent("settings.json"))
        await failed.load()
        try Data("not a folder".utf8).write(to: blockedParent)
        expect(failed.setKeepModeOpen(true) == nil, "Runtime change accepts before async write")
        await failed.flush()
        expect(failed.persistenceError != nil && failed.snapshot.enabled, "Persistence failure shown without lying about runtime")
        try FileManager.default.removeItem(at: blockedParent)
        failed.retrySave()
        await failed.flush()
        expect(failed.persistenceError == nil, "Retry async write recovers")
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        var trusted = false, trustChecks = 0, settingsOpens = 0, reveals = 0, opensSuccessfully = false
        let access = WindowAccessibilityAccess(checker: { trustChecks += 1; return trusted },
            openSettings: { settingsOpens += 1; return opensSuccessfully },
            currentAppURL: URL(fileURLWithPath: "/Synthetic/Current/Cue.app"), revealCurrentApp: { reveals += 1 })
        expect(access.status == .unchecked && trustChecks == 0 && settingsOpens == 0, "Permission initialization performs no system query or prompt")
        let controller = WindowControlSettingsController(preferences: prefs, accessibility: access)
        guard let window = controller.window, let content = window.contentView else {
            preconditionFailure("Missing settings content")
        }
        content.layoutSubtreeIfNeeded()
        controller.refreshAccess()
        expect(trustChecks == 0, "Hidden app activation does not query permissions")
        let initialSnapshot = prefs.snapshot
        access.refresh()
        expect(access.status == .required && trustChecks == 1, "First denied check shows required status")
        access.openSettings()
        expect(settingsOpens == 1 && access.openingError != nil, "Opening failure has actionable manual fallback")
        opensSuccessfully = true
        access.openSettings()
        expect(settingsOpens == 2 && access.status == .required && access.openingError == nil, "Opening system page never grants or assumes permission")
        expect(trustChecks == 1, "Open action waits for a later refresh")
        opensSuccessfully = false; access.openSettings()
        trusted = true; access.refresh()
        expect(access.status == .enabled && access.openingError == nil, "Grant detected and obsolete opening error cleared")
        trusted = false; access.refresh()
        expect(access.status == .required, "Update or revoked permission replaces stale granted state")
        access.showsRepairHelp = true
        let hostIdentity = ObjectIdentifier(content)
        access.refresh(); access.refresh()
        expect(access.showsRepairHelp, "Repeated refresh preserves expanded recovery instructions")
        expect(ObjectIdentifier(controller.window!.contentView!) == hostIdentity, "Permission refresh retains the hosting tree and preset editor state")
        expect(prefs.snapshot == initialSnapshot, "Permission changes never alter presets or enablement")
        access.revealCurrentApp()
        expect(reveals == 1 && access.currentAppURL.path == "/Synthetic/Current/Cue.app", "Explicit reveal targets the current app via injected action")
        var grantedChecks = 0
        let alreadyGranted = WindowAccessibilityAccess(checker: { grantedChecks += 1; return true },
            openSettings: { preconditionFailure("Granted-state test must not open System Settings") },
            currentAppURL: URL(fileURLWithPath: "/Synthetic/Current/Cue.app"), revealCurrentApp: {})
        expect(grantedChecks == 0, "Already-granted initialization still stays lazy")
        alreadyGranted.refresh()
        expect(alreadyGranted.status == .enabled && grantedChecks == 1, "Existing permission is recognized on first refresh")
        expect(!window.isVisible && !NSApp.isActive, "Settings do not activate in offscreen checks")
        expect(content.frame.width == 590 && content.frame.height == 650, "Settings have bounded dimensions")
        expect(content.fittingSize.width.isFinite && content.fittingSize.height.isFinite, "Finite native layout")
        let scrolls = descendants(content).compactMap { $0 as? NSScrollView }
        expect(!scrolls.isEmpty, "Presets document scrolls within fixed window")
        expect(scrolls.allSatisfy { $0.contentSize.height > 300 }, "Useful preset viewport")
        var closed = 0
        controller.onClose = { closed += 1 }
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        expect(closed == 1, "Closing restores owning UI via callback")
        if let directory = ProcessInfo.processInfo.environment["CUE_WINDOW_SETTINGS_PREVIEW_DIRECTORY"] {
            let view = WindowControlSettingsView(preferences: prefs, accessibility: access, capturedPreset: { left }, close: {})
            // The image renderer does not support native ScrollView. Render the same
            // document tree and check the actual hidden viewport independently above.
            let renderer = ImageRenderer(content: view.settingsContent.frame(width: 550).padding(20)
                .background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            try save(renderer.nsImage, named: "window-settings", directory: directory)
            access.showsRepairHelp = false
            let deniedRenderer = ImageRenderer(content: view.settingsContent.frame(width: 550).padding(20)
                .background(Color(nsColor: .windowBackgroundColor)))
            deniedRenderer.scale = 2
            try save(deniedRenderer.nsImage, named: "window-settings-permission-required", directory: directory)
            trusted = true; access.refresh()
            let grantedRenderer = ImageRenderer(content: view.settingsContent.frame(width: 550).padding(20)
                .background(Color(nsColor: .windowBackgroundColor)))
            grantedRenderer.scale = 2
            try save(grantedRenderer.nsImage, named: "window-settings-permission-enabled", directory: directory)
            expect(deniedRenderer.nsImage != nil && grantedRenderer.nsImage != nil, "Required and granted states render in both localizations")
            let editor = WindowPresetEditor(slot: 1, existing: left, capturedPreset: { left }, save: { _ in nil }, close: {})
            let editorRenderer = ImageRenderer(content: editor.background(Color(nsColor: .windowBackgroundColor)))
            editorRenderer.scale = 2
            try save(editorRenderer.nsImage, named: "window-preset-editor", directory: directory)
            expect(renderer.nsImage != nil && editorRenderer.nsImage != nil, "Offscreen previews rendered")
        }
        expect(!NSApp.isActive && !window.isVisible, "No test takes desktop focus")
        print("Window settings: \(count) isolated checks passed")
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    @MainActor private static func save(_ image: NSImage?, named name: String, directory: String) throws {
        guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Offscreen rendering failed")
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try png.write(to: url.appendingPathComponent(name + ".png"))
    }
}
