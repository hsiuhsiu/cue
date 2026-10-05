import AppKit
import CueCore
import Foundation

private actor SyntheticWindowService: WindowControlling {
    let screen = WindowScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 850))
    var captures: [UUID: CheckedContinuation<WindowControlSnapshot, Error>] = [:]
    var applies: [CheckedContinuation<WindowControlSnapshot, Error>] = []
    var actions: [WindowAction] = []
    var holdApplies = false
    func capture(processIdentifier: Int32, screens: [WindowScreen], sessionID: UUID) async throws -> WindowControlSnapshot {
        try await withCheckedThrowingContinuation { captures[sessionID] = $0 }
    }
    func apply(_ action: WindowAction, screens: [WindowScreen], sessionID: UUID) async throws -> WindowControlSnapshot {
        actions.append(action)
        if holdApplies { return try await withCheckedThrowingContinuation { applies.append($0) } }
        return result()
    }
    nonisolated func cancel(sessionID: UUID) { /* Deliberately delivers late results, testing the caller's generation guard. */ }
    func captureCount() -> Int { captures.count }
    func actionCount() -> Int { actions.count }
    func hold(_ flag: Bool) { holdApplies = flag }
    func finishCapture(_ id: UUID, error: WindowControlError? = nil) {
        guard let continuation = captures.removeValue(forKey: id) else { preconditionFailure("Missing capture") }
        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result()) }
    }
    func finishApply(error: WindowControlError? = nil) {
        let continuation = applies.removeFirst()
        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result()) }
    }
    func result() -> WindowControlSnapshot {
        WindowControlSnapshot(processIdentifier: 987654, frame: CGRect(x: 100, y: 80, width: 720, height: 700), screen: screen, canMove: true, canResize: true, notice: nil)
    }
}

@main struct CheckWindowMode {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var checks = 0
        func expect(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        func eventually(_ check: @MainActor () async -> Bool) async {
            for _ in 0..<500 {
                if await check() { return }
                try? await Task.sleep(for: .milliseconds(2))
            }
            preconditionFailure("Timed out waiting for isolated fixture")
        }
        let service = SyntheticWindowService()
        let screen = service.screen
        let model = WindowModeModel(service: service, screens: { [screen] })
        let presets = (1...9).map { WindowPreset(slot: $0, name: "Preset \($0)", x: 0, y: 0, width: 0.6, height: 1) }
        let view = WindowModeView(frame: CGRect(x: 0, y: 0, width: 500, height: 375))
        view.target.stringValue = "Test Window"
        view.setPresets(presets)
        model.onChange = { view.update(from: model) }
        view.onAction = { model.perform($0) }
        var settingsRequests = 0
        view.onSettings = { settingsRequests += 1 }
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        func layout() {
            window.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: 500, height: view.preferredHeight))
            window.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
        }
        func descendants(_ root: NSView) -> [NSView] { root.subviews.flatMap { [$0] + descendants($0) } }
        func actionButtons() -> [NSButton] {
            descendants(view).compactMap { $0 as? NSButton }.filter { $0.action == NSSelectorFromString("performAction:") }
        }
        func savePreview(_ filename: String) throws {
            guard let output = ProcessInfo.processInfo.environment["CUE_WINDOW_MODE_PREVIEW_DIRECTORY"] else { return }
            let url = URL(fileURLWithPath: output).appendingPathComponent(filename)
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: url)
            }
        }
        var completions = 0
        model.onFinished = { _ in completions += 1 }
        model.start(processIdentifier: 987654)
        let old = model.sessionID!
        model.perform(.half(.left))
        expect(model.isBusy, "Capture acknowledges immediately while commands queue")
        expect(model.canPerformActions && actionButtons().allSatisfy(\.isEnabled), "Capture in progress still accepts immediate commands")
        await eventually { await service.captureCount() == 1 }
        expect(await service.actionCount() == 0, "No mutation before target capture")
        model.cancel()
        await service.finishCapture(old)
        await Task.yield()
        expect(model.snapshot == nil && model.sessionID == nil, "Late cancelled capture must not revive UI")
        expect(await service.actionCount() == 0, "Cancelled queue never executes")
        model.start(processIdentifier: 987654)
        let current = model.sessionID!
        await eventually { await service.captureCount() == 1 }
        await service.finishCapture(current)
        await eventually { model.snapshot != nil }
        await service.hold(true)
        model.perform(.move(.right))
        model.perform(.half(.left))
        await eventually { await service.actionCount() == 1 }
        expect(model.isBusy && completions == 0, "Actions serialize without blocking input")
        await service.finishApply()
        await eventually { await service.actionCount() == 2 }
        await service.finishApply()
        await eventually { !model.isBusy }
        expect(completions == 1, "Completion waits until queued commands finish")
        model.perform(.fill)
        await eventually { await service.actionCount() == 3 }
        model.cancel()
        await service.finishApply()
        await Task.yield()
        expect(model.snapshot == nil && completions == 1, "Late mutation result cannot restore a dismissed session")
        model.start(processIdentifier: 987654)
        let denied = model.sessionID!
        model.perform(.half(.right))
        await eventually { await service.captureCount() == 1 }
        await service.finishCapture(denied, error: .permissionRequired)
        await eventually { model.error != nil }
        expect(model.error == .permissionRequired && !model.isBusy, "Permission error ends progress and remains explicit")
        expect(!model.canPerformActions && !view.canPerformActions, "Denied capture disables model and view actions")
        expect(actionButtons().count == 20 && actionButtons().allSatisfy { !$0.isEnabled }, "Every layout and preset button is visibly unavailable when denied")
        expect(!view.permissionGuide.isHidden && view.permissionGuide.isEnabled, "Permission guide remains available after capture denial")
        let localizedPermission = L10n.string("permission", table: "WindowMode", value: "missing")
        expect(localizedPermission != "missing" && view.status.stringValue == localizedPermission, "Denied status uses the complete localized explanation")
        view.permissionGuide.performClick(nil)
        expect(settingsRequests == 1, "Permission guide opens the same feature-settings callback without requesting system access")
        let gear = descendants(view).compactMap { $0 as? NSButton }.first { $0.image != nil }!
        expect(gear.isEnabled, "Settings gear remains usable while actions are disabled")
        gear.performClick(nil)
        expect(settingsRequests == 2, "Settings gear and permission guide share the safe settings route")
        view.setPresets(Array(presets.prefix(2)))
        expect(actionButtons().count == 13 && actionButtons().allSatisfy { !$0.isEnabled }, "New preset buttons inherit the denied state")
        view.setPresets(presets)
        layout()
        let statusHeight = view.status.cell!.cellSize(forBounds: CGRect(x: 0, y: 0, width: view.status.bounds.width, height: 1000)).height
        expect(statusHeight <= view.status.bounds.height + 1, "Permission explanation fits without clipping in this language")
        expect(view.bounds.contains(view.convert(view.permissionGuide.bounds, from: view.permissionGuide)), "Permission guide stays inside the compact panel")
        expect(view.permissionGuide.cell!.cellSize.width <= view.permissionGuide.bounds.width + 1, "Permission guide label fits")
        try savePreview("window-mode-permission.png")
        model.perform(.center)
        actionButtons().first!.performClick(nil)
        expect(await service.actionCount() == 3, "No target means no writes")

        // Returning from feature settings creates a fresh session. Old actions
        // are neither retained nor replayed when permission becomes available.
        model.start(processIdentifier: 987654)
        let granted = model.sessionID!
        expect(granted != denied && model.canPerformActions, "Fresh capture resets permission failure without delaying input")
        await eventually { await service.captureCount() == 1 }
        await service.finishCapture(granted)
        await eventually { !model.isBusy }
        expect(model.error == nil && model.snapshot != nil && view.permissionGuide.isHidden, "Fresh granted capture clears guide and error")
        expect(await service.actionCount() == 3 && completions == 1, "Granting permission alone never replays a denied command")
        expect(actionButtons().allSatisfy(\.isEnabled), "Actions become enabled after capture recovers")
        model.perform(.fill)
        model.perform(.center)
        await eventually { await service.actionCount() == 4 }
        await service.finishApply(error: .permissionRequired)
        await eventually { model.error == .permissionRequired }
        expect(model.snapshot != nil && !model.canPerformActions, "Revoked permission disables actions even with an earlier snapshot")
        expect(actionButtons().allSatisfy { !$0.isEnabled } && !view.permissionGuide.isHidden, "Revocation also updates the visible actions and guide")
        model.perform(.half(.right))
        expect(await service.actionCount() == 4, "Revocation discards queued work and refuses further actions")
        model.cancel()
        model.start(processIdentifier: 987654)
        let recovered = model.sessionID!
        await eventually { await service.captureCount() == 1 }
        await service.finishCapture(recovered)
        await eventually { !model.isBusy }
        expect(await service.actionCount() == 4, "Fresh capture after revocation does not replay queued work")
        model.perform(.center)
        await eventually { await service.actionCount() == 5 }
        await service.finishApply()
        await eventually { !model.isBusy }
        expect(completions == 2, "Only a new explicit action executes after recovery")
        for (action, failure) in [(WindowAction.move(.right), WindowControlError.noAdjacentScreen), (.restore, .nothingToRestore)] {
            let before = await service.actionCount()
            model.perform(action)
            await eventually { await service.actionCount() == before + 1 }
            await service.finishApply(error: failure)
            await eventually { model.error == failure }
            expect(model.canPerformActions && actionButtons().allSatisfy(\.isEnabled), "Recoverable geometry errors leave other actions available")
            expect(view.permissionGuide.isHidden, "Geometry errors never imply missing permission")
        }
        model.start(processIdentifier: 987654)
        let noTarget = model.sessionID!
        await eventually { await service.captureCount() == 1 }
        await service.finishCapture(noTarget, error: .noTarget)
        await eventually { model.error == .noTarget }
        expect(!model.canPerformActions && actionButtons().allSatisfy { !$0.isEnabled }, "Capture without a target disables layout actions")
        expect(view.permissionGuide.isHidden, "Missing target does not show an unrelated permission guide")
        model.cancel()
        expect(!view.canPerformActions && actionButtons().allSatisfy { !$0.isEnabled }, "Cancelled or absent sessions keep actions unavailable")

        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "", repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: code)!
        }
        for code: UInt16 in [36, 76] {
            expect(WindowModeController.opensPermissionGuide(for: key(code), error: .permissionRequired), "Explicit Return opens the guide after permission denial")
            expect(!WindowModeController.opensPermissionGuide(for: key(code), error: nil), "Return during capture or ready state never opens settings")
            expect(!WindowModeController.opensPermissionGuide(for: key(code), error: .noTarget), "Missing target does not redirect Return to permission settings")
            expect(!WindowModeController.opensPermissionGuide(for: key(code, repeated: true), error: .permissionRequired), "Held Return cannot open the guide after an asynchronous denial")
            for flags: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
                expect(!WindowModeController.opensPermissionGuide(for: key(code, flags), error: .permissionRequired), "Modified Return never opens permission settings")
            }
        }
        for code: UInt16 in [48, 49, 53, 18, 123] {
            expect(!WindowModeController.opensPermissionGuide(for: key(code), error: .permissionRequired), "Other layout and escape keys do not open the permission guide")
        }
        for (code, direction) in [(UInt16(123), WindowDirection.left), (124, .right), (125, .down), (126, .up)] {
            expect(WindowModeController.action(for: key(code, .option), presets: presets) == .half(direction), "Half-screen routing")
            expect(WindowModeController.action(for: key(code, .command), presets: presets) == .move(direction), "Display routing")
            for flags: NSEvent.ModifierFlags in [[], .shift, .control, [.command, .option], [.option, .shift]] {
                expect(WindowModeController.action(for: key(code, flags), presets: presets) == nil, "Wrong modifiers never adjust")
            }
            expect(WindowModeController.action(for: key(code, .option, repeated: true), presets: presets) == nil, "Held keys do not repeatedly adjust")
        }
        for (code, action) in [(UInt16(36), WindowAction.fill), (76, .fill), (49, .center), (48, .restore)] {
            expect(WindowModeController.action(for: key(code), presets: presets) == action, "Direct action")
            expect(WindowModeController.action(for: key(code, .command), presets: presets) == nil, "Modified direct action ignored")
        }
        for (index, code) in [18,19,20,21,23,22,26,28,25].enumerated() {
            expect(WindowModeController.action(for: key(UInt16(code), [], String(index + 1)), presets: presets) == .preset(presets[index]), "Number row presets")
            expect(WindowModeController.action(for: key(UInt16(code)), presets: []) == nil, "Unset presets never execute")
        }
        expect(WindowModeController.action(for: key(83), presets: presets) == .preset(presets[0]), "Keypad support")

        model.start(processIdentifier: 987654)
        let previewSession = model.sessionID!
        await eventually { await service.captureCount() == 1 }
        await service.finishCapture(previewSession)
        await eventually { !model.isBusy }
        layout()
        expect(view.preferredHeight < 350, "Compact panel without excess bottom padding")
        expect(view.status.frame.minY >= 0 && view.status.frame.maxY <= view.bounds.height, "Status remains inside panel")
        expect(view.preview.frame.height > 0 && view.preview.frame.width > 0, "Visible geometric preview bounds")
        try savePreview("window-mode.png")
        model.cancel()
        expect(!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible }, "No desktop activation or visible windows")
        print("Window mode passed: \(checks) mocked lifecycle, cancellation, keyboard and offscreen layout checks; no real AX calls or user windows.")
    }
}
