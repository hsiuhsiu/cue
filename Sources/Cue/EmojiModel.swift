import AppKit
import CueCore

/// Clipboard publication is an explicit action, never part of catalog loading or search.
private actor EmojiPasteboardWriter {
    private let name: NSPasteboard.Name
    enum Failure: Error, Equatable { case denied, writeFailed }

    init(name: NSPasteboard.Name) { self.name = name }

    func copy(_ emoji: String) throws {
        try Task.checkCancellation()
        let board = NSPasteboard(name: name)
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { throw Failure.denied }
        let item = NSPasteboardItem()
        guard item.setString(emoji, forType: .string) else { throw Failure.writeFailed }
        try Task.checkCancellation()
        // No suspension between the final cancellation check and publication.
        board.clearContents()
        guard board.writeObjects([item]) else { throw Failure.writeFailed }
    }
}

@MainActor
final class EmojiModel {
    private(set) var query = ""
    private(set) var results: [EmojiEntry] = []
    private(set) var selectedID: String?
    private(set) var isLoading = false
    private(set) var isCopying = false
    private(set) var errorMessage: String?
    var onChange: (() -> Void)?
    let glyphs = EmojiGlyphCache()
    var selectedEntry: EmojiEntry? { results.first { $0.id == selectedID } }

    private let loader: @Sendable () throws -> EmojiCatalog
    private let copier: @Sendable (String) async throws -> Void
    private var catalog: EmojiCatalog?
    private var loadTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var copyGeneration = 0
    private var presentationGeneration = 0
    private var isPresented = false

    init(pasteboardName: NSPasteboard.Name = .general,
         loader: @escaping @Sendable () throws -> EmojiCatalog = EmojiModel.loadCatalog,
         copier: (@Sendable (String) async throws -> Void)? = nil) {
        self.loader = loader
        if let copier { self.copier = copier }
        else {
            let writer = EmojiPasteboardWriter(name: pasteboardName)
            self.copier = { try await writer.copy($0) }
        }
    }

    deinit {
        loadTask?.cancel()
        copyTask?.cancel()
    }

    /// Prewarming is optional and asynchronous. The native input never waits for disk or decoding.
    func prepare() {
        guard catalog == nil, loadTask == nil else { return }
        isLoading = true
        errorMessage = nil
        if isPresented { onChange?() }
        loadTask = Task { [weak self, loader] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try loader() }.value
                guard !Task.isCancelled, let self else { return }
                self.catalog = loaded
                self.isLoading = false
                self.loadTask = nil
                self.refreshResults()
                if self.isPresented { self.onChange?() }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoading = false
                self.loadTask = nil
                self.errorMessage = EmojiText.shared.loadError
                if self.isPresented { self.onChange?() }
            }
        }
    }

    func open() {
        cancelCopy()
        presentationGeneration += 1
        isPresented = true
        query = ""
        errorMessage = nil
        refreshResults()
        prepare()
        onChange?()
    }

    func close() {
        isPresented = false
        presentationGeneration += 1
        cancelCopy()
        glyphs.prepare([])
    }

    func cancelPendingCopy() {
        let wasCopying = isCopying
        cancelCopy()
        if wasCopying { onChange?() }
    }

    func setQuery(_ value: String) {
        guard query != value else { return }
        cancelCopy()
        query = value
        if catalog != nil { errorMessage = nil }
        refreshResults()
        onChange?()
    }

    func select(_ id: String?) {
        let validID = results.contains { $0.id == id } ? id : nil
        guard selectedID != validID else { return }
        cancelCopy()
        selectedID = validID
        onChange?()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        select(results[min(max(current + offset, 0), results.count - 1)].id)
    }

    func copySelected(at index: Int? = nil, completion: @escaping () -> Void) {
        guard isPresented, copyTask == nil else { return }
        let entry: EmojiEntry?
        if let index {
            guard results.indices.contains(index) else { return }
            entry = results[index]
        } else { entry = selectedEntry }
        guard let entry else { return }
        selectedID = entry.id
        errorMessage = nil
        isCopying = true
        copyGeneration += 1
        let request = copyGeneration
        let presentation = presentationGeneration
        let requestedQuery = query
        onChange?()
        copyTask = Task { [weak self, copier] in
            do {
                try Task.checkCancellation()
                try await copier(entry.emoji)
                try Task.checkCancellation()
                guard let self, self.isPresented, self.copyGeneration == request,
                      self.presentationGeneration == presentation, self.query == requestedQuery else { return }
                self.copyTask = nil
                self.isCopying = false
                self.onChange?()
                completion()
            } catch {
                guard !Task.isCancelled, let self, self.isPresented,
                      self.copyGeneration == request, self.presentationGeneration == presentation else { return }
                self.copyTask = nil
                self.isCopying = false
                self.errorMessage = (error as? EmojiPasteboardWriter.Failure) == .denied
                    ? EmojiText.shared.accessError : EmojiText.shared.copyError
                self.onChange?()
            }
        }
    }

    private func cancelCopy() {
        copyGeneration += 1
        copyTask?.cancel()
        copyTask = nil
        isCopying = false
    }

    private func refreshResults() {
        results = catalog?.search(query, limit: 9) ?? []
        selectedID = results.first?.id
        glyphs.prepare(results)
    }

    nonisolated private static func loadCatalog() throws -> EmojiCatalog {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "EmojiCatalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try EmojiCatalog(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
}
