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
    private var nextID: UInt32 = 1
    private let onPress: () -> Void
    private static let signature: OSType = 0x43756531 // Cue1

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Claim the replacement first so a conflict never disables the working shortcut.
    func register(shortcut: LauncherShortcut = .default) -> OSStatus {
        guard shortcut.isValid else { return OSStatus(paramErr) }
        if let registeredShortcut,
           registeredShortcut.keyCode == shortcut.keyCode,
           registeredShortcut.modifiers == shortcut.modifiers {
            return noErr
        }
        let handlerStatus = installHandlerIfNeeded()
        guard handlerStatus == noErr else { return handlerStatus }

        let identifier = nextID
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement
        )
        guard status == noErr else { return status }
        guard let replacement else { return OSStatus(eventInternalErr) }

        let previous = hotKey
        hotKey = replacement
        registeredShortcut = shortcut
        registeredID = identifier
        if let previous { UnregisterEventHotKey(previous) }
        return noErr
    }

    private func installHandlerIfNeeded() -> OSStatus {
        guard handler == nil else { return noErr }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
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
                    manager.onPress()
                    return noErr
                }
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        registeredShortcut = nil
        registeredID = nil
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
