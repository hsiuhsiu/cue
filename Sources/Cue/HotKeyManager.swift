import AppKit
import Carbon
import CueCore

/// Carbon hot keys are delivered by the main event loop and need no event tap permission.
@MainActor
final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registeredShortcut: LauncherShortcut?
    private var registeredID: UInt32?
    private var isPressed = false
    // Every manager shares one Carbon target/signature. IDs must be unique across
    // the launcher and window mode, including replacement registrations.
    private static var nextID: UInt32 = 1
    private let onPress: () -> Void
    private static let signature: OSType = 0x43756531 // Cue1

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Claim the replacement first so a conflict never disables the working shortcut.
    func register(shortcut: LauncherShortcut = .default) -> OSStatus {
        let prepared = prepare(shortcut: shortcut)
        guard prepared.status == noErr else { return prepared.status }
        if let registration = prepared.registration { commit(registration) }
        return noErr
    }

    /// Reserve both replacements before releasing either current shortcut. A
    /// conflict (including swapping two occupied shortcuts) leaves both intact.
    static func replacePair(
        launcher: HotKeyManager, launcherShortcut: LauncherShortcut,
        window: HotKeyManager, windowShortcut: LauncherShortcut?
    ) -> OSStatus {
        guard launcher !== window else { return OSStatus(paramErr) }
        if let windowShortcut,
           launcherShortcut.keyCode == windowShortcut.keyCode,
           launcherShortcut.modifiers == windowShortcut.modifiers { return OSStatus(paramErr) }
        let first = launcher.prepare(shortcut: launcherShortcut)
        guard first.status == noErr else { return first.status }
        let second = windowShortcut.map { window.prepare(shortcut: $0) }
        if let second, second.status != noErr {
            if let reservation = first.registration { UnregisterEventHotKey(reservation.reference) }
            return second.status
        }
        if let reservation = first.registration { launcher.commit(reservation) }
        if let reservation = second?.registration { window.commit(reservation) }
        if windowShortcut == nil { window.unregister() }
        return noErr
    }

    private struct Registration {
        let reference: EventHotKeyRef
        let shortcut: LauncherShortcut
        let identifier: UInt32
    }

    private func prepare(shortcut: LauncherShortcut) -> (registration: Registration?, status: OSStatus) {
        guard shortcut.isValid else { return (nil, OSStatus(paramErr)) }
        if let registeredShortcut,
           registeredShortcut.keyCode == shortcut.keyCode,
           registeredShortcut.modifiers == shortcut.modifiers {
            return (nil, noErr)
        }
        let handlerStatus = installHandlerIfNeeded()
        guard handlerStatus == noErr else { return (nil, handlerStatus) }

        let identifier = Self.nextID
        Self.nextID &+= 1
        if Self.nextID == 0 { Self.nextID = 1 }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement
        )
        guard status == noErr else { return (nil, status) }
        guard let replacement else { return (nil, OSStatus(eventInternalErr)) }
        return (Registration(reference: replacement, shortcut: shortcut, identifier: identifier), noErr)
    }

    private func commit(_ registration: Registration) {
        let previous = hotKey
        hotKey = registration.reference
        registeredShortcut = registration.shortcut
        registeredID = registration.identifier
        isPressed = false
        if let previous { UnregisterEventHotKey(previous) }
    }

    private func installHandlerIfNeeded() -> OSStatus {
        guard handler == nil else { return noErr }
        var eventTypes = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        return InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
                )
                guard status == noErr else { return status }
                return MainActor.assumeIsolated {
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                    guard identifier.signature == HotKeyManager.signature,
                          identifier.id == manager.registeredID else {
                        return OSStatus(eventNotHandledErr)
                    }
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                        manager.isPressed = false
                    } else if !manager.isPressed {
                        manager.isPressed = true
                        manager.onPress()
                    }
                    return noErr
                }
            },
            eventTypes.count, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }

    /// macOS may sleep before delivering the release event for a held shortcut.
    func resetPressedState() { isPressed = false }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        registeredShortcut = nil
        registeredID = nil
        isPressed = false
    }
}

extension LauncherShortcut {
    fileprivate var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// Ignore state flags such as Caps Lock, matching Carbon's shortcut registration.
    func matches(event: NSEvent) -> Bool {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return UInt32(event.keyCode) == keyCode
            && event.modifierFlags.intersection([.command, .option, .control, .shift]) == flags
    }
}
