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
    let googleSearch = L10n.string("search.google", table: "Launcher", value: "Search Google")
    let defaultBrowser = L10n.string("search.browser", table: "Launcher", value: "Default browser")
    let webSearchShortcut = L10n.string("search.google.shortcut", table: "Launcher", value: "Search this text in Google (⌘Return)")
    let webSearchOff = L10n.string("search.disabled", table: "Launcher", value: "Disabled")
    let webSearchDisabled = L10n.string("search.google.disabled", table: "Launcher", value: "Google search is off. Press ⌘, on a search option to enable it.")
    let webSearchError = L10n.string("search.google.error", table: "Launcher", value: "Couldn’t open Google in the selected browser. Please try again.")
    let webSearchSettings = L10n.string("search.settings", table: "Launcher", value: "Google Search Settings")
    let browserUnavailable = L10n.string("search.browserUnavailable", table: "Launcher", value: "%@ is unavailable. Install it again or choose another browser.")
    let openingBrowser = L10n.string("search.openingBrowser", table: "Launcher", value: "Opening browser…")
    let searchActions = L10n.string("search.actions", table: "Launcher", value: "Google search · Esc to return · ⌘, for search settings")
    let browserChoices = L10n.string("search.choices", table: "Launcher", value: "Choose a search browser (⌘K) · Search settings (⌘,)")
    let updateIndex = L10n.string("command.updateIndex", table: "Launcher", value: "Update App Index")
    let cleanLink = L10n.string("command.cleanLink", table: "Launcher", value: "Clean Link")
    let emojiSearch = L10n.string("command.emojiSearch", table: "Launcher", value: "Emoji Search")
    let calculationCopy = L10n.string("calculator.copy", table: "Launcher", value: "Copy result ↵")
    let calculationCopying = L10n.string("calculator.copying", table: "Launcher", value: "Copying result…")
    let calculationCopyError = L10n.string("calculator.copyError", table: "Launcher", value: "Couldn’t copy the result. Please try again.")
    let calculationAccessDenied = L10n.string("calculator.accessDenied", table: "Launcher", value: "Clipboard access is blocked. Allow Cue in System Settings, then try again.")
    let currencyNetworkRequired = L10n.string("currency.networkRequired", table: "Launcher", value: "Currency conversion needs Cue network access")
    let currencyLoading = L10n.string("currency.loading", table: "Launcher", value: "Fetching exchange rates…")
    let currencyUnavailable = L10n.string("currency.unavailable", table: "Launcher", value: "Couldn’t load exchange rates")
    let currencyUnsupported = L10n.string("currency.unsupported", table: "Launcher", value: "Currency is unavailable in this rate table")
    let currencyRetry = L10n.string("currency.retry", table: "Launcher", value: "Retry ↵")
    let currencyDisabled = L10n.string("currency.disabled", table: "Launcher", value: "Network off")
    let currencyDaily = L10n.string("currency.daily", table: "Launcher", value: "Daily rates · %@")
    let cleanLinkDetail = L10n.string("command.cleanLink.detail", table: "Launcher", value: "Clipboard")
    let cleaningLink = L10n.string("link.cleaning", table: "Launcher", value: "Cleaning clipboard link…")
    let linkCleaned = L10n.string("link.cleaned", table: "Launcher", value: "Removed %ld tracking parameters. Clean link copied.")
    let linkAlreadyClean = L10n.string("link.alreadyClean", table: "Launcher", value: "No removable tracking parameters. Clipboard unchanged.")
    let linkProtected = L10n.string("link.protected", table: "Launcher", value: "This link may be signed. Kept unchanged so it will still work.")
    let linkInvalid = L10n.string("link.invalid", table: "Launcher", value: "Copy a single HTTP or HTTPS link, then try again.")
    let linkTooLarge = L10n.string("link.tooLarge", table: "Launcher", value: "This link is too long to clean. Clipboard unchanged.")
    let linkClipboardChanged = L10n.string("link.clipboardChanged", table: "Launcher", value: "Clipboard changed while cleaning. Your newer copy was kept.")
    let linkAccessDenied = L10n.string("link.accessDenied", table: "Launcher", value: "Clipboard access is blocked. Allow Cue in System Settings, then try again.")
    let linkWriteFailed = L10n.string("link.writeFailed", table: "Launcher", value: "Couldn’t update the clipboard. Please try again.")
    let clipboardHistory = L10n.string("command.clipboardHistory", table: "Launcher", value: "Clipboard History")
    let sleep = L10n.string("command.sleep", table: "Launcher", value: "Sleep")
    let lockScreen = L10n.string("command.lockScreen", table: "Launcher", value: "Lock Screen")
    let screenOff = L10n.string("command.screenOff", table: "Launcher", value: "Screen Off")
    let convertToTraditional = L10n.string("command.convertToTraditional", table: "Launcher", value: "Convert to Traditional Chinese")
    let convertToSimplified = L10n.string("command.convertToSimplified", table: "Launcher", value: "Convert to Simplified Chinese")
    let traditionalRegion = L10n.string("command.convertToTraditional.detail", table: "Launcher", value: "Taiwan")
    let simplifiedRegion = L10n.string("command.convertToSimplified.detail", table: "Launcher", value: "Mainland China")
    let chineseConversionSettings = L10n.string("command.chineseConversionSettings", table: "Launcher", value: "Chinese Conversion Settings")
    let sleepError = L10n.string("command.sleep.error", table: "Launcher", value: "Couldn’t put this Mac to sleep. Please try Sleep in the Apple menu.")
    let lockError = L10n.string("command.lockScreen.error", table: "Launcher", value: "Couldn’t lock this Mac. Please try Lock Screen in the Apple menu.")
    let screenOffError = L10n.string("command.screenOff.error", table: "Launcher", value: "Couldn’t turn off the display. Please try again.")
    let command = L10n.string("command.detail", table: "Launcher", value: "Command")
    let launchError = L10n.string("launch.error", table: "Launcher", value: "Couldn’t open %@: %@")
}

/// One synchronous update per input event, with a bounded cache for backspacing/reopening.
@MainActor
final class LauncherModel {
    private(set) var query = ""
    private(set) var results: [LauncherResult] = []
    private(set) var selectedID: LauncherResult.ID?
    private(set) var conversionAliases: ChineseConversionAliases
    private(set) var isIndexing = false
    private(set) var indexStatus: String?
    private(set) var allowsWebSearch = true
    private(set) var searchBrowsers: [WebSearchBrowser] = []
    private(set) var isShowingSearchActions = false
    var launchError: String? { didSet { if launchError != oldValue { onChange?() } } }
    var shortcutError: String? { didSet { if shortcutError != oldValue { onChange?() } } }
    var actionStatus: String? { didSet { if actionStatus != oldValue { onChange?() } } }
    var onQueryChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onChange: (() -> Void)?
    let icons: AppIconCache

    private let text = LauncherText.shared
    private var applications: [IndexedApplication] = []
    private var cachedQueries: [String: [LauncherResult]] = [:]
    private var maxResults = LauncherPreferences.maximumVisibleResults
    private var usage: SearchUsageSnapshot
    private var pendingUsage: SearchUsageSnapshot?
    private let usageStore: SearchUsageStore?
    private var usageOperations: Task<Void, Never>?
    private var usageStarted = false
    private var isStopping = false
    private var hasLoadedApplications: Bool
    private let currencyRates: CurrencyRatesController?
    private var currencyQuery: ConversionQuery?
    private var changingCurrencyActivity = false
    private var displayedRateDate: Date?
    private(set) var currencyRateDate: String?

    init(applications: [IndexedApplication] = [], usage: SearchUsageSnapshot = .empty,
         usageStore: SearchUsageStore? = nil,
         conversionAliases: ChineseConversionAliases = .defaults,
         awaitingInitialIndex: Bool = false,
         currencyRates: CurrencyRatesController? = nil,
         icons: AppIconCache = AppIconCache()) {
        self.icons = icons
        self.applications = applications
        self.usage = usage
        self.usageStore = usageStore
        self.conversionAliases = conversionAliases
        self.hasLoadedApplications = !awaitingInitialIndex
        self.currencyRates = currencyRates
        currencyRates?.onChange = { [weak self] in
            guard let self, !self.changingCurrencyActivity else { return }
            self.onQueryChange?() // A revoked rate/permission also cancels a pending copy.
            self.updateRateDate()
            self.cachedQueries.removeAll(keepingCapacity: true)
            self.updateResults(preservingSelection: true)
            self.onChange?()
        }
    }

    var selectedResult: LauncherResult? { results.first { $0.id == selectedID } }

    /// Start after the launcher and hotkey are ready. Tests without a store never touch disk.
    func startUsageTracking() {
        guard !usageStarted, !isStopping else { return }
        usageStarted = true
        enqueueUsage { store in await store.load() }
    }

    /// Accept background updates without moving the currently visible rows or their shortcuts.
    /// A fresh query or invocation adopts the newest snapshot and invalidates cached rankings.
    func updateUsage(_ snapshot: SearchUsageSnapshot) {
        pendingUsage = snapshot
    }

    func recordSuccessfulAction(resultID: String, query: String, at date: Date = Date()) {
        // Expressions stay private even when the user chooses a matching app or
        // command below the answer. This check runs only after an explicit action.
        guard !isStopping, !resultID.hasPrefix(LauncherResult.googleSearch.id),
              resultID != LauncherResult.calculationID,
              !resultID.hasPrefix(LauncherResult.conversionIDPrefix),
              resultID != LauncherResult.currencyStatusID,
              Calculator.evaluate(query) == nil,
              ConversionQuery.parse(query) == nil else { return }
        enqueueUsage { store in await store.record(resultID: resultID, query: query, at: date) }
    }

    func prepareForTermination() async {
        isStopping = true
        currencyRates?.stop()
        await usageOperations?.value
        if let usageStore { try? await usageStore.flush() }
    }

    func setQuery(_ value: String) {
        guard value != query else { return }
        onQueryChange?()
        adoptPendingUsage()
        query = value
        if value.allSatisfy(\.isWhitespace) { isShowingSearchActions = false }
        updateCurrencyActivity()
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

    func setAllowsWebSearch(_ allowed: Bool) {
        setWebSearchPreferences(enabled: allowed, browsers: searchBrowsers)
    }

    func setWebSearchPreferences(enabled: Bool, browsers: [WebSearchBrowser]) {
        let browsers = Array(browsers.prefix(WebSearchBrowser.maximumAddedBrowsers))
        guard allowsWebSearch != enabled || searchBrowsers != browsers else { return }
        allowsWebSearch = enabled
        searchBrowsers = browsers
        cachedQueries.removeAll(keepingCapacity: true)
        if enabled && launchError == text.webSearchDisabled { launchError = nil }
        updateResults(preservingSelection: true)
        onChange?()
    }

    func toggleSearchActions() {
        guard !query.allSatisfy(\.isWhitespace) else { return }
        onQueryChange?() // Cancel a pending handoff before changing the available actions.
        isShowingSearchActions.toggle()
        updateCurrencyActivity()
        launchError = nil
        updateResults()
        onChange?()
    }

    @discardableResult
    func closeSearchActions() -> Bool {
        guard isShowingSearchActions else { return false }
        toggleSearchActions()
        return true
    }

    private var webSearchResults: [LauncherResult] {
        [.googleSearch] + searchBrowsers.map { .googleSearchIn($0) }
    }

    func setConversionAliases(_ aliases: ChineseConversionAliases) {
        guard aliases != conversionAliases else { return }
        conversionAliases = aliases
        cachedQueries.removeAll(keepingCapacity: true)
        updateResults(preservingSelection: true)
        onChange?()
    }

    @discardableResult
    func loadApplications() async -> Bool {
        guard !isIndexing else { return false }
        isIndexing = true
        indexStatus = nil
        launchError = nil
        onChange?()
        let discovered = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
        applications = discovered
        hasLoadedApplications = true
        cachedQueries.removeAll(keepingCapacity: true)
        icons.invalidate()
        isIndexing = false
        updateResults(preservingSelection: true)
        indexStatus = L10n.format(text.indexUpdated, applications.count)
        onChange?()
        return true
    }

    func reset() {
        adoptPendingUsage()
        query = ""
        isShowingSearchActions = false
        updateCurrencyActivity()
        launchError = nil
        indexStatus = nil
        updateResults()
        onChange?()
    }

    func select(_ id: LauncherResult.ID?) {
        guard selectedID != id else { return }
        onSelectionChange?()
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
        if isShowingSearchActions {
            results = webSearchResults
        } else if currencyQuery == nil, let cached = cachedQueries[query] {
            results = cached
        } else {
            let converted: [ConversionResult]?
            let currencyStatus: CurrencyConversionStatus?
            if let currencyQuery {
                if currencyRates?.allowsNetwork != true {
                    converted = []; currencyStatus = .networkRequired
                } else if case .ready(let snapshot) = currencyRates?.state {
                    converted = UnitConversion.convertCurrency(currencyQuery, rates: snapshot)
                    currencyStatus = converted?.isEmpty == true ? .unsupported : nil
                } else {
                    converted = []
                    currencyStatus = currencyRates?.state == .failed ? .unavailable : .loading
                }
            } else { converted = nil; currencyStatus = nil }
            results = Array(LauncherResult.search(
                applications, query: query, usage: usage, conversionAliases: conversionAliases,
                includeGoogleFallback: hasLoadedApplications,
                conversionResults: converted, currencyStatus: currencyStatus
            ).prefix(maxResults))
            if results == [.googleSearch] { results = Array(webSearchResults.prefix(maxResults)) }
            if cachedQueries.count >= 64 { cachedQueries.removeAll(keepingCapacity: true) }
            if currencyQuery == nil { cachedQueries[query] = results }
        }
        if !preservingSelection || !results.contains(where: { $0.id == selectedID }) {
            selectedID = results.first?.id
        }
    }

    func retryCurrencyRates() { currencyRates?.retry() }

    func canCopyNumericResult(_ result: LauncherResult) -> Bool {
        guard case .conversion(let converted) = result, converted.isCurrency else { return true }
        // Recheck time/permission at the action boundary, including immediately
        // after wake when the expiry callback has not yet run.
        updateCurrencyActivity()
        updateResults(preservingSelection: true)
        onChange?()
        guard currencyRates?.allowsNetwork == true, case .ready = currencyRates?.state else { return false }
        return selectedResult == result
    }

    private func updateCurrencyActivity() {
        let parsed = ConversionQuery.parse(query)
        currencyQuery = parsed?.source.isCurrency == true ? parsed : nil
        changingCurrencyActivity = true
        currencyRates?.setActive(currencyQuery != nil && !isShowingSearchActions)
        changingCurrencyActivity = false
        updateRateDate()
    }

    private func updateRateDate() {
        guard case .ready(let snapshot) = currencyRates?.state else {
            currencyRateDate = nil; displayedRateDate = nil; return
        }
        guard displayedRateDate != snapshot.updatedAt else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        currencyRateDate = L10n.format(text.currencyDaily, formatter.string(from: snapshot.updatedAt))
        displayedRateDate = snapshot.updatedAt
    }

    private func adoptPendingUsage() {
        guard let pendingUsage else { return }
        usage = pendingUsage
        self.pendingUsage = nil
        cachedQueries.removeAll(keepingCapacity: true)
    }

    private func enqueueUsage(_ operation: @escaping @Sendable (SearchUsageStore) async -> SearchUsageSnapshot) {
        guard let usageStore else { return }
        let previous = usageOperations
        usageOperations = Task { [weak self] in
            // Preserve event order even if a launch completes while the first disk load is pending.
            await previous?.value
            let snapshot = await operation(usageStore)
            self?.updateUsage(snapshot)
        }
    }
}
