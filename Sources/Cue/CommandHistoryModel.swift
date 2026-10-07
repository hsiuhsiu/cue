import Foundation
import CueCore

@MainActor
final class CommandHistoryModel {
    private(set) var history = CommandHistory()
    private(set) var isEnabled: Bool
    private(set) var isLoading = false
    private(set) var saveFailed = false
    private let store: CommandHistoryStore?
    private let defaults: UserDefaults?
    private var operations: Task<Void, Never>?
    private var revision = 0
    private var started = false
    private var stopped = false
    var onChange: (() -> Void)?
    var onClear: (() -> Void)?

    // No store/defaults means fully isolated in-memory operation for tests.
    init(store: CommandHistoryStore? = nil, defaults: UserDefaults? = nil) {
        self.store = store
        self.defaults = defaults
        isEnabled = defaults?.object(forKey: "commandHistory.enabled") as? Bool ?? true
    }

    func start() {
        guard !started, !stopped else { return }
        started = true
        isLoading = store != nil
        enqueue { await $0.load() }
    }

    func refresh() {
        history.prune()
        enqueue { await $0.load() }
    }

    func record(_ result: LauncherResult, query: String, at date: Date = Date()) {
        guard isEnabled, !stopped else { return }
        switch result {
        case .commandHistory, .chooseSearchBrowser, .currencyStatus: return
        default: break
        }
        let title: String
        if case .googleSearchIn(let browser) = result { title = browser.name }
        else { title = result.name }
        let entry = CommandHistoryEntry(query: query, actionID: result.id, title: title, date: date)
        guard entry.isValid else { return }
        history.record(entry, now: date)
        enqueue { await $0.record(entry, now: date) }
        onChange?()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults?.set(enabled, forKey: "commandHistory.enabled")
        onChange?()
    }

    func remove(_ id: UUID) {
        history.remove(id)
        onClear?() // Do not retain a deleted entry in an Up/Down snapshot.
        enqueue { await $0.remove(id) }
        onChange?()
    }

    func clear() {
        history.clear()
        onClear?()
        enqueue { await $0.clear() }
        onChange?()
    }

    func finish() async {
        stopped = true
        await operations?.value
        if let store { try? await store.flush() }
    }

    private func enqueue(_ operation: @escaping @Sendable (CommandHistoryStore) async -> CommandHistory) {
        revision += 1
        guard let store else { return }
        let expected = revision
        let previous = operations
        operations = Task { [weak self] in
            await previous?.value
            let snapshot = await operation(store)
            // Flush away from input; errors are visible inside the history page.
            let failed: Bool
            do { try await store.flush(); failed = false } catch { failed = true }
            guard let self, self.revision == expected else { return }
            let changed = self.history != snapshot || self.isLoading || self.saveFailed != failed
            self.history = snapshot
            self.isLoading = false
            self.saveFailed = failed
            if changed { self.onChange?() }
        }
    }
}
