import AppKit

/// Only an explicit copy action reaches the pasteboard. Search stays synchronous
/// and local; pasteboard IPC stays away from the input thread.
actor CalculatorCopyService {
    enum Failure: Error, Equatable { case denied, writeFailed }
    private let name: NSPasteboard.Name

    init(pasteboardName: NSPasteboard.Name = .general) { name = pasteboardName }

    func copy(_ value: String) throws {
        try Task.checkCancellation()
        let board = NSPasteboard(name: name)
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { throw Failure.denied }
        let item = NSPasteboardItem()
        guard item.setString(value, forType: .string) else { throw Failure.writeFailed }
        try Task.checkCancellation()
        board.clearContents()
        guard board.writeObjects([item]) else { throw Failure.writeFailed }
    }
}
