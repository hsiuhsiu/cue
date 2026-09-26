import Foundation

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
            // Keep the Settings shortcut available inside Cue.
            && !(keyCode == 43 && modifiers == .command)
    }
}

public struct LauncherPreferences: Codable, Equatable, Sendable {
    public enum Display: String, Codable, CaseIterable, Sendable {
        case pointer
        case main
    }

    public static let resultLimits = [10, 20, 50, 100]

    public var shortcut: LauncherShortcut
    public var maxResults: Int
    public var display: Display
    public var dismissOnFocusLoss: Bool

    public init(
        shortcut: LauncherShortcut = .default,
        maxResults: Int = 20,
        display: Display = .pointer,
        dismissOnFocusLoss: Bool = true
    ) {
        self.shortcut = shortcut.isValid ? shortcut : .default
        self.maxResults = Self.resultLimits.contains(maxResults) ? maxResults : 20
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
            maxResults: (try? values.decode(Int.self, forKey: .maxResults)) ?? 20,
            display: (try? values.decode(Display.self, forKey: .display)) ?? .pointer,
            dismissOnFocusLoss: (try? values.decode(Bool.self, forKey: .dismissOnFocusLoss)) ?? true
        )
    }
}
