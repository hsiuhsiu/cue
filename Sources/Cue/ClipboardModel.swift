import AppKit
import CueCore

/// Pasteboard servers may be slow. Publication stays off the UI actor and checks
/// cancellation again immediately before the irreversible clear/write operation.
private actor ClipboardPasteboardWriter {
    private let name: NSPasteboard.Name
    enum Failure: Error { case writeFailed }

    init(name: NSPasteboard.Name) { self.name = name }

    func copy(_ text: String) throws {
        try Task.checkCancellation()
        let board = NSPasteboard(name: name)
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setData(Data(), forType: ClipboardMonitor.ownMarker) else { throw Failure.writeFailed }
        try Task.checkCancellation()
        // A publication already in progress cannot be rolled back safely: another
        // app may own the pasteboard next. There is no suspension after this check.
        board.clearContents()
        guard board.writeObjects([item]) else { throw Failure.writeFailed }
    }
}

@MainActor
final class ClipboardModel {
    private(set) var query = ""
    private(set) var results: [ClipboardEntry] = []
    private(set) var selectedID: UUID?
    private(set) var recordingEnabled: Bool
    private(set) var retention: ClipboardRetention
    private(set) var isLoading = true
    private(set) var isCopying = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    var onChange: (() -> Void)?

    var selectedEntry: ClipboardEntry? { results.first { $0.id == selectedID } }

    private let defaults: UserDefaults
    private let store: ClipboardStore
    private let copier: @Sendable (String) async throws -> Void
    private var copyTask: Task<Void, Never>?
    private var monitor: ClipboardMonitor!
    private var maintenance: Timer?
    private var operations: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var captureGeneration = 0
    private var displayedQuery = ""
    private var hasLoaded = false
    private var isPresented = false
    private var presentationGeneration = 0
    private var copyGeneration = 0
    private var isStopping = false
    private var transientClipboardUses = 0

    private static let enabledKey = "clipboard.recordingEnabled"
    private static let retentionKey = "clipboard.retention"
    private static let storageError = L10n.string("error.storage", table: "Clipboard", value: "Couldn’t save clipboard history. Check available disk space and folder permissions.")
    private static let loadError = L10n.string("error.load", table: "Clipboard", value: "Couldn’t load clipboard history. The saved file has been left untouched.")
    private static let copyError = L10n.string("error.copy", table: "Clipboard", value: "Couldn’t copy this item. Please try again.")
    private static let deniedError = L10n.string("error.access", table: "Clipboard", value: "Clipboard access is blocked. Allow Cue in System Settings to record new copies.")

    init(defaults: UserDefaults = .standard, fileURL: URL? = nil,
         pasteboardName: NSPasteboard.Name = .general,
         copier: (@Sendable (String) async throws -> Void)? = nil) {
        self.defaults = defaults
        if let copier { self.copier = copier }
        else {
            let writer = ClipboardPasteboardWriter(name: pasteboardName)
            self.copier = { try await writer.copy($0) }
        }
        recordingEnabled = defaults.bool(forKey: Self.enabledKey)
        retention = defaults.string(forKey: Self.retentionKey).flatMap(ClipboardRetention.init(rawValue:)) ?? .week
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yyhsiu.cue", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
        store = ClipboardStore(fileURL: fileURL ?? directory.appendingPathComponent("history.json"))
        monitor = ClipboardMonitor(name: pasteboardName) { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        let initialRetention = retention
        enqueue { [weak self] store in
            do {
                _ = try await store.load(retention: initialRetention, now: Date())
                self?.hasLoaded = true
                self?.isLoading = false
                self?.refreshSearch()
            } catch {
                self?.isLoading = false
                self?.errorMessage = Self.loadError
                self?.onChange?()
            }
        }
        monitor.setEnabled(recordingEnabled, generation: captureGeneration)
        // Retention continues even while recording is paused. No payload polling when paused.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenance = timer
    }

    deinit {
        copyTask?.cancel()
        searchTask?.cancel()
    }

    func stop() {
        maintenance?.invalidate()
        maintenance = nil
        captureGeneration += 1
        monitor.setEnabled(false, generation: captureGeneration)
    }

    func prepareForTermination() async {
        isStopping = true
        close()
        stop()
        // Finish accepted mutations before an ordinary quit. A promised pasteboard
        // provider may stall, so only await disk operations, never the monitor queue.
        await operations?.value
    }

    func open() {
        guard !isStopping else { return }
        cancelPendingCopy()
        isPresented = true
        presentationGeneration += 1
        setQuery("")
        refreshSearch(preservingSelection: false)
        monitor.pollNow()
        prune()
    }

    func close() {
        cancelPendingCopy()
        isPresented = false
        presentationGeneration += 1
        searchGeneration += 1
        searchTask?.cancel()
    }

    func setQuery(_ value: String) {
        guard query != value else { return }
        cancelPendingCopy()
        query = value
        statusMessage = nil
        // Text stays synchronous. Search runs on the store actor without debounce.
        selectedID = nil
        refreshSearch(preservingSelection: false)
        onChange?()
    }

    func select(_ id: UUID?) {
        guard selectedID != id else { return }
        cancelPendingCopy()
        selectedID = id
        onChange?()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty, displayedQuery == query else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        select(results[min(max(current + offset, 0), results.count - 1)].id)
    }

    func setRecordingEnabled(_ value: Bool) {
        guard !isStopping, value != recordingEnabled else { return }
        recordingEnabled = value
        defaults.set(value, forKey: Self.enabledKey)
        captureGeneration += 1
        monitor.setEnabled(value && transientClipboardUses == 0, generation: captureGeneration)
        if errorMessage == Self.deniedError { errorMessage = nil }
        onChange?()
    }

    /// A text replacement temporarily owns the pasteboard without becoming history.
    /// Invalidate in-flight captures immediately instead of waiting on a promised
    /// payload from another app. Disable/resume are ordered on the monitor queue.
    func beginTransientClipboardUse() {
        cancelPendingCopy()
        transientClipboardUses += 1
        captureGeneration += 1
        monitor.setEnabled(false, generation: captureGeneration)
    }

    func endTransientClipboardUse() {
        guard transientClipboardUses > 0 else { return }
        transientClipboardUses -= 1
        guard transientClipboardUses == 0 else { return }
        captureGeneration += 1
        monitor.setEnabled(recordingEnabled && !isStopping, generation: captureGeneration)
    }

    func setRetention(_ value: ClipboardRetention) {
        guard !isStopping, value != retention else { return }
        retention = value
        defaults.set(value.rawValue, forKey: Self.retentionKey)
        prune()
        onChange?()
    }

    func removeSelected() {
        guard !isStopping, let id = selectedID, displayedQuery == query else { return }
        cancelPendingCopy()
        // Invalidate a promised read already in flight, so deletion cannot be undone by it.
        captureGeneration += 1
        monitor.resetBaseline(generation: captureGeneration)
        searchGeneration += 1
        searchTask?.cancel()
        let index = results.firstIndex { $0.id == id } ?? 0
        results.removeAll { $0.id == id }
        selectedID = results.isEmpty ? nil : results[min(index, results.count - 1)].id
        errorMessage = nil
        onChange?()
        enqueue { [weak self] store in
            do {
                _ = try await store.remove(id: id)
                self?.refreshSearch()
            } catch {
                self?.errorMessage = Self.storageError
                self?.refreshSearch()
            }
        }
    }

    /// Settings, preview, focus loss, and navigation revoke an unfinished copy.
    /// Cancellation also reaches a writer queued behind other background work.
    func cancelPendingCopy() {
        copyGeneration += 1
        copyTask?.cancel()
        copyTask = nil
        let wasCopying = isCopying
        isCopying = false
        if wasCopying { onChange?() }
    }

    func copySelected(at resultIndex: Int? = nil, onCopied: @escaping () -> Void) {
        guard !isStopping, isPresented else { return }
        if let resultIndex, !(0..<LauncherPreferences.maximumVisibleResults).contains(resultIndex) { return }
        cancelPendingCopy()
        let copyRequest = copyGeneration
        let requestedQuery = query
        let presentation = presentationGeneration
        let selected: UUID?
        if let resultIndex, displayedQuery == query {
            guard results.indices.contains(resultIndex) else { return }
            selected = results[resultIndex].id
        } else {
            selected = displayedQuery == query ? selectedID : nil
        }
        let pendingOperations = operations
        isCopying = true
        errorMessage = nil
        onChange?()
        copyTask = Task { [weak self, store, copier] in
            do {
                // Resolve the current query against committed history, even when
                // Return arrives before the corresponding rows have rendered.
                await pendingOperations?.value
                try Task.checkCancellation()
                let matches = await store.search(query: requestedQuery)
                try Task.checkCancellation()
                let entry: ClipboardEntry?
                if let selected { entry = matches.first { $0.id == selected } }
                else if let resultIndex { entry = matches.indices.contains(resultIndex) ? matches[resultIndex] : nil }
                else { entry = matches.first }
                guard let self, self.isPresented, self.presentationGeneration == presentation,
                      self.query == requestedQuery, self.copyGeneration == copyRequest else { return }
                guard let entry else {
                    self.finishCopy()
                    return
                }
                if let expiration = self.retention.expiration,
                   Date().timeIntervalSince(entry.copiedAt) >= expiration {
                    self.finishCopy()
                    self.prune()
                    return
                }
                try await copier(entry.text)
                try Task.checkCancellation()
                guard self.isPresented, self.presentationGeneration == presentation,
                      self.query == requestedQuery, self.copyGeneration == copyRequest else { return }
                self.finishCopy()
                // Copying a retained item works while recording is paused too.
                if self.recordingEnabled { self.record(entry.text) }
                onCopied()
            } catch {
                guard !Task.isCancelled, let self, self.isPresented,
                      self.presentationGeneration == presentation, self.copyGeneration == copyRequest else { return }
                self.errorMessage = Self.copyError
                self.finishCopy()
            }
        }
    }

    private func finishCopy() {
        copyTask = nil
        isCopying = false
        onChange?()
    }

    private func receive(_ event: ClipboardMonitor.Event) {
        guard !isStopping else { return }
        switch event {
        case .captured(let value, let generation):
            guard recordingEnabled, transientClipboardUses == 0, generation == captureGeneration else { return }
            if errorMessage == Self.deniedError { errorMessage = nil }
            record(value)
        case .accessDenied(let generation):
            guard recordingEnabled, transientClipboardUses == 0, generation == captureGeneration else { return }
            errorMessage = Self.deniedError
            onChange?()
        }
    }

    private func record(_ value: String) {
        let copiedAt = Date()
        let keep = retention
        enqueue { [weak self] store in
            guard self?.hasLoaded == true else { return }
            do {
                _ = try await store.record(text: value, retention: keep, now: copiedAt)
                self?.errorMessage = nil
                self?.refreshSearch()
            } catch {
                self?.errorMessage = Self.storageError
                self?.onChange?()
            }
        }
    }

    private func prune() {
        let keep = retention
        enqueue { [weak self] store in
            guard self?.hasLoaded == true else { return }
            do {
                _ = try await store.prune(retention: keep, now: Date())
                self?.refreshSearch()
            } catch {
                self?.errorMessage = Self.storageError
                self?.onChange?()
            }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor (ClipboardStore) async -> Void) {
        guard !isStopping else { return }
        let previous = operations
        let store = store
        operations = Task {
            await previous?.value
            await operation(store)
        }
    }

    private func refreshSearch(preservingSelection: Bool = true) {
        // Captures must not reload an invisible table while the user types in the launcher.
        guard isPresented else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let query = query
        let selected = preservingSelection ? selectedID : nil
        searchTask?.cancel()
        searchTask = Task { [weak self, store] in
            // Search all retained history first. The display cap must never make
            // older copies disappear from a later, more specific search.
            let matches = await store.search(query: query, limit: LauncherPreferences.maximumVisibleResults)
            guard !Task.isCancelled, let self, generation == self.searchGeneration else { return }
            self.results = matches
            self.displayedQuery = query
            self.selectedID = matches.contains { $0.id == selected } ? selected : matches.first?.id
            self.onChange?()
        }
    }
}
