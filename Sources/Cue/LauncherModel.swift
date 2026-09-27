import AppKit
import CueCore

/// Resolve every launcher label together before interaction, never on the typing path.
struct LauncherText {
    static let shared = LauncherText()

    let searchPlaceholder = L10n.string("search.placeholder", table: "Launcher", value: "Search apps and commands…")
    let searchAccessibility = L10n.string("search.accessibility", table: "Launcher", value: "Search apps and commands")
    let resultsAccessibility = L10n.string("results.accessibility", table: "Launcher", value: "Search results")
    let selectOpen = L10n.string("keyboard.selectOpen", table: "Launcher", value: "↑ ↓ Select   ↵ Open")
    let selectRun = L10n.string("keyboard.selectRun", table: "Launcher", value: "↑ ↓ Select   ↵ Run")
    let settings = L10n.string("settings.title", table: "Launcher", value: "Settings")
    let settingsTooltip = L10n.string("settings.tooltip", table: "Launcher", value: "Settings (⌘,)")
    let findingApplications = L10n.string("index.finding", table: "Launcher", value: "Finding applications…")
    let updatingIndex = L10n.string("index.updating", table: "Launcher", value: "Updating app index…")
    let indexUpdated = L10n.string("index.updated", table: "Launcher", value: "Index updated · %ld applications")
    let noResults = L10n.string("results.empty", table: "Launcher", value: "No results found")
    let updateIndex = L10n.string("command.updateIndex", table: "Launcher", value: "Update App Index")
    let clipboardHistory = L10n.string("command.clipboardHistory", table: "Launcher", value: "Clipboard History")
    let sleep = L10n.string("command.sleep", table: "Launcher", value: "Sleep")
    let lockScreen = L10n.string("command.lockScreen", table: "Launcher", value: "Lock Screen")
    let sleepError = L10n.string("command.sleep.error", table: "Launcher", value: "Couldn’t put this Mac to sleep. Please try Sleep in the Apple menu.")
    let lockError = L10n.string("command.lockScreen.error", table: "Launcher", value: "Couldn’t lock this Mac. Please try Lock Screen in the Apple menu.")
    let command = L10n.string("command.detail", table: "Launcher", value: "Command")
    let launchError = L10n.string("launch.error", table: "Launcher", value: "Couldn’t open %@: %@")
}

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

    private let text = LauncherText.shared
    private var applications: [IndexedApplication] = []
    private var cachedQueries: [String: [LauncherResult]] = [:]
    private var maxResults = LauncherPreferences.maximumVisibleResults

    init(applications: [IndexedApplication] = []) {
        self.applications = applications
    }

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
        let limit = min(max(value, 1), LauncherPreferences.maximumVisibleResults)
        guard limit != maxResults else { return }
        maxResults = limit
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
        cachedQueries.removeAll(keepingCapacity: true)
        icons.invalidate()
        isIndexing = false
        updateResults(preservingSelection: true)
        indexStatus = L10n.format(text.indexUpdated, applications.count)
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
            results = []
            selectedID = nil
            return
        }
        if let cached = cachedQueries[query] {
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
