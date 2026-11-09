import AppKit
@preconcurrency import ApplicationServices

enum ClipboardPasteError: Error, Equatable {
    case permissionRequired, noTarget, targetChanged, unavailable, clipboardChanged
}

struct ClipboardPasteTarget: Sendable, Equatable {
    let id: UUID
    let processID: Int32
}

protocol ClipboardPasting: Sendable {
    func capture(processID: Int32) async throws -> ClipboardPasteTarget
    func paste(_ target: ClipboardPasteTarget, text: String) async throws
    func discard(_ target: ClipboardPasteTarget) async
}

protocol ClipboardPasteDriver: Sendable {
    func capture(processID: Int32) throws -> ClipboardPasteTarget
    func isFocused(_ target: ClipboardPasteTarget) throws -> Bool
    func postPaste(_ target: ClipboardPasteTarget) throws
    func discard(_ target: ClipboardPasteTarget)
}

/// Runs only after an explicit history selection. Reads window/element identity,
/// never destination text or selection contents. The clipboard check below
/// verifies only the chosen item that Cue just copied.
actor ClipboardPasteService: ClipboardPasting {
    private let driver: any ClipboardPasteDriver
    private let pasteboardName: NSPasteboard.Name
    init(driver: any ClipboardPasteDriver = AXClipboardPasteDriver(), pasteboardName: NSPasteboard.Name = .general) {
        self.driver = driver; self.pasteboardName = pasteboardName
    }

    func capture(processID: Int32) throws -> ClipboardPasteTarget {
        try Task.checkCancellation()
        guard processID > 0, processID != ProcessInfo.processInfo.processIdentifier else { throw ClipboardPasteError.noTarget }
        return try driver.capture(processID: processID)
    }

    func paste(_ target: ClipboardPasteTarget, text: String) async throws {
        defer { driver.discard(target) }
        let board = NSPasteboard(name: pasteboardName)
        let changeCount = board.changeCount
        guard board.availableType(from: [ClipboardMonitor.ownMarker]) != nil,
              board.string(forType: .string)?.utf16.elementsEqual(text.utf16) == true,
              board.changeCount == changeCount else { throw ClipboardPasteError.clipboardChanged }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        repeat {
            try Task.checkCancellation()
            if try driver.isFocused(target) {
                try Task.checkCancellation()
                guard board.changeCount == changeCount else { throw ClipboardPasteError.clipboardChanged }
                // The driver revalidates immediately before posting, without an
                // actor suspension. Never retry a posted Paste command.
                try driver.postPaste(target)
                return
            }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            try await Task.sleep(for: min(.milliseconds(8), remaining))
        } while ContinuousClock.now < deadline
        throw ClipboardPasteError.targetChanged
    }

    func discard(_ target: ClipboardPasteTarget) { driver.discard(target) }

    @MainActor static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// References stay on the service actor. One bounded target is retained until
/// completion/cancellation or the next capture; no destination content is read.
private final class AXClipboardPasteDriver: ClipboardPasteDriver, @unchecked Sendable {
    private struct Pending {
        let target: ClipboardPasteTarget
        let launched: Date
        let window: AXUIElement
        let element: AXUIElement
    }
    private var pending: Pending?

    func capture(processID: Int32) throws -> ClipboardPasteTarget {
        pending = nil
        guard AXIsProcessTrusted() else { throw ClipboardPasteError.permissionRequired }
        guard let app = NSRunningApplication(processIdentifier: processID), !app.isTerminated,
              let launched = app.launchDate else { throw ClipboardPasteError.noTarget }
        let application = AXUIElementCreateApplication(processID)
        let window = try element(application, kAXFocusedWindowAttribute)
        let focused = try element(application, kAXFocusedUIElementAttribute)
        let target = ClipboardPasteTarget(id: UUID(), processID: processID)
        pending = Pending(target: target, launched: launched, window: window, element: focused)
        return target
    }

    func isFocused(_ target: ClipboardPasteTarget) throws -> Bool {
        guard AXIsProcessTrusted() else { throw ClipboardPasteError.permissionRequired }
        guard let pending, pending.target == target,
              let app = NSRunningApplication(processIdentifier: target.processID), !app.isTerminated,
              app.launchDate == pending.launched else { throw ClipboardPasteError.targetChanged }
        let system = AXUIElementCreateSystemWide()
        let application = try element(system, kAXFocusedApplicationAttribute)
        var pid: pid_t = 0
        guard AXUIElementGetPid(application, &pid) == .success else { throw ClipboardPasteError.unavailable }
        if pid == ProcessInfo.processInfo.processIdentifier { return false } // Panel is still relinquishing focus.
        guard pid == target.processID else { throw ClipboardPasteError.targetChanged }
        let window = try element(application, kAXFocusedWindowAttribute)
        let focused = try element(application, kAXFocusedUIElementAttribute)
        guard CFEqual(window, pending.window), CFEqual(focused, pending.element) else { throw ClipboardPasteError.targetChanged }
        return true
    }

    func postPaste(_ target: ClipboardPasteTarget) throws {
        guard try isFocused(target),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            throw ClipboardPasteError.unavailable
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(target.processID); up.postToPid(target.processID)
    }

    func discard(_ target: ClipboardPasteTarget) { if pending?.target == target { pending = nil } }

    private func element(_ object: AXUIElement, _ attribute: String) throws -> AXUIElement {
        guard AXUIElementSetMessagingTimeout(object, 0.12) == .success else { throw ClipboardPasteError.unavailable }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(object, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { throw ClipboardPasteError.unavailable }
        return value as! AXUIElement
    }
}
