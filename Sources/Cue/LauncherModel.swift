import AppKit
import CueCore

/// One synchronous update per input event, with a bounded cache for backspacing/reopening.
@MainActor
final class LauncherModel {
    private(set) var query = ""
    private(set) var results: [LauncherResult] = []
    private(set) var selectedID: LauncherResult.ID?
    private(set) var isIndexing = false
    private(set) var indexStatus: String?
    var launchError: String? { didSet { if launchError != oldValue { onChange?() } } }
    var shortcutError: String? { didSet { if shortcutError != oldValue { onChange?() } } }
    var onChange: (() -> Void)?
    let icons = AppIconCache()

    private var applications: [IndexedApplication] = []
    private var emptyResults: [LauncherResult] = [.updateIndex]
    private var cachedQueries: [String: [LauncherResult]] = [:]
    private var maxResults = 20

    var selectedResult: LauncherResult? { results.first { $0.id == selectedID } }

    func setQuery(_ value: String) {
        guard value != query else { return }
        query = value
        launchError = nil
        indexStatus = nil
        updateResults()
        onChange?()
    }

    func setResultLimit(_ value: Int) {
        guard value != maxResults else { return }
        maxResults = value
        cachedQueries.removeAll(keepingCapacity: true)
        updateResults(preservingSelection: true)
        onChange?()
    }

    func loadApplications() async {
        guard !isIndexing else { return }
        isIndexing = true
        indexStatus = nil
        launchError = nil
        onChange?()
        let discovered = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
        applications = discovered
        emptyResults = LauncherResult.search(discovered, query: "")
        cachedQueries.removeAll(keepingCapacity: true)
        icons.invalidate()
        // Warm the initial screen before the user asks to show it.
        icons.prepare(Array(emptyResults.prefix(maxResults).compactMap {
            if case .application(let application) = $0 { return application }
            return nil
        }))
        isIndexing = false
        updateResults(preservingSelection: true)
        indexStatus = "Index updated · \(applications.count) applications"
        onChange?()
    }

    func reset() {
        query = ""
        launchError = nil
        indexStatus = nil
        updateResults()
        onChange?()
    }

    func select(_ id: LauncherResult.ID?) {
        guard selectedID != id else { return }
        selectedID = id
        onChange?()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        select(results[min(max(current + offset, 0), results.count - 1)].id)
    }

    private func updateResults(preservingSelection: Bool = false) {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = Array(emptyResults.prefix(maxResults))
        } else if let cached = cachedQueries[query] {
            results = cached
        } else {
            results = Array(LauncherResult.search(applications, query: query).prefix(maxResults))
            if cachedQueries.count >= 64 { cachedQueries.removeAll(keepingCapacity: true) }
            cachedQueries[query] = results
        }
        if !preservingSelection || !results.contains(where: { $0.id == selectedID }) {
            selectedID = results.first?.id
        }
    }
}
