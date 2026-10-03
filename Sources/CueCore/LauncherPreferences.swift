import Foundation

/// Key codes shared by result dispatch and global-hotkey validation. Keeping the
/// reservation here also sanitizes older saved shortcuts before registration.
public enum CueKeyboardShortcut {
    public static func resultIndex(keyCode: UInt32, characters: String? = nil) -> Int? {
        if let characters, characters.utf8.count == 1,
           let digit = characters.utf8.first, (49...57).contains(digit) {
            return Int(digit - 49)
        }
        // Number row and numeric keypad, including non-Latin input methods.
        return switch keyCode {
        case 18, 83: 0
        case 19, 84: 1
        case 20, 85: 2
        case 21, 86: 3
        case 23, 87: 4
        case 22, 88: 5
        case 26, 89: 6
        case 28, 91: 7
        case 25, 92: 8
        default: nil
        }
    }

    public static func isReserved(keyCode: UInt32, modifiers: LauncherShortcut.Modifiers,
                                  characters: String? = nil) -> Bool {
        // Keep native Undo/Redo available in editable fields.
        if modifiers == [.command, .shift] { return keyCode == 6 }
        guard modifiers == .command else { return false }
        if resultIndex(keyCode: keyCode, characters: characters) != nil { return true }
        switch keyCode {
        // A/C/V/X/Z: select, copy, paste, cut, undo; Y: clipboard preview.
        case 0, 8, 9, 7, 6, 16,
             // E/K/comma: app alias, query actions, settings.
             14, 40, 43,
             // Return/keypad Enter; backward/forward Delete.
             36, 76, 51, 117,
             // Native text navigation using Command plus an arrow.
             123, 124, 125, 126:
            return true
        default:
            return false
        }
    }
}

public struct LauncherShortcut: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Self(rawValue: 1 << 0)
        public static let option = Self(rawValue: 1 << 1)
        public static let control = Self(rawValue: 1 << 2)
        public static let shift = Self(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers
    public var key: String

    public static let `default` = Self(keyCode: 49, modifiers: .option, key: "Space")

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public var displayName: String {
        (modifiers.contains(.control) ? "⌃" : "")
            + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "")
            + (modifiers.contains(.command) ? "⌘" : "")
            + key
    }

    public var isValid: Bool {
        let supported: Modifiers = [.command, .option, .control, .shift]
        let required: Modifiers = [.command, .option, .control]
        let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        return keyCode <= 126
            && !modifierKeyCodes.contains(keyCode)
            && !modifiers.intersection(required).isEmpty
            && modifiers.subtracting(supported).isEmpty
            && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && key.count <= 24
            && !CueKeyboardShortcut.isReserved(keyCode: keyCode, modifiers: modifiers, characters: key)
    }
}

public struct LauncherPreferences: Codable, Equatable, Sendable {
    public enum Display: String, Codable, CaseIterable, Sendable {
        case pointer
        case main
    }

    /// The complete list fits in the launcher and maps directly to ⌘1–⌘9.
    public static let maximumVisibleResults = 9

    public var shortcut: LauncherShortcut
    public var maxResults: Int
    public var display: Display
    public var dismissOnFocusLoss: Bool

    public init(
        shortcut: LauncherShortcut = .default,
        maxResults: Int = maximumVisibleResults,
        display: Display = .pointer,
        dismissOnFocusLoss: Bool = true
    ) {
        self.shortcut = shortcut.isValid ? shortcut : .default
        // Keep the persisted field readable so older preferences migrate without
        // discarding shortcut or display choices, but results now have one fixed cap.
        self.maxResults = Self.maximumVisibleResults
        self.display = display
        self.dismissOnFocusLoss = dismissOnFocusLoss
    }

    public func sanitized() -> Self {
        Self(
            shortcut: shortcut, maxResults: maxResults,
            display: display, dismissOnFocusLoss: dismissOnFocusLoss
        )
    }

    private enum CodingKeys: String, CodingKey {
        case shortcut, maxResults, display, dismissOnFocusLoss
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shortcut: (try? values.decode(LauncherShortcut.self, forKey: .shortcut)) ?? .default,
            maxResults: (try? values.decode(Int.self, forKey: .maxResults)) ?? Self.maximumVisibleResults,
            display: (try? values.decode(Display.self, forKey: .display)) ?? .pointer,
            dismissOnFocusLoss: (try? values.decode(Bool.self, forKey: .dismissOnFocusLoss)) ?? true
        )
    }
}
