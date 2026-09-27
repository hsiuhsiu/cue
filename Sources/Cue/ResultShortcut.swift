import AppKit
import Carbon

/// Shared numbering for the launcher's two result lists.
enum ResultShortcut {
    private static let labels = (1...9).map { "⌘\($0)" }

    static func label(for row: Int) -> String {
        guard row >= 0 else { return "" }
        return row < labels.count ? labels[row] : String(row + 1)
    }

    static func index(for event: NSEvent) -> Int? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else { return nil }
        if let characters = event.charactersIgnoringModifiers,
           characters.utf8.count == 1, let digit = characters.utf8.first,
           (49...57).contains(digit) { return Int(digit - 49) }
        // Keep number-row and keypad shortcuts usable with non-Latin input methods.
        switch Int(event.keyCode) {
        case kVK_ANSI_1, kVK_ANSI_Keypad1: return 0
        case kVK_ANSI_2, kVK_ANSI_Keypad2: return 1
        case kVK_ANSI_3, kVK_ANSI_Keypad3: return 2
        case kVK_ANSI_4, kVK_ANSI_Keypad4: return 3
        case kVK_ANSI_5, kVK_ANSI_Keypad5: return 4
        case kVK_ANSI_6, kVK_ANSI_Keypad6: return 5
        case kVK_ANSI_7, kVK_ANSI_Keypad7: return 6
        case kVK_ANSI_8, kVK_ANSI_Keypad8: return 7
        case kVK_ANSI_9, kVK_ANSI_Keypad9: return 8
        default: return nil
        }
    }
}
