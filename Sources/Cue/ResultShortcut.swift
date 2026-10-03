import AppKit
import CueCore

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
        return CueKeyboardShortcut.resultIndex(keyCode: UInt32(event.keyCode),
                                               characters: event.charactersIgnoringModifiers)
    }
}
