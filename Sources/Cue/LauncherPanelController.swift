import AppKit
import CueCore

private final class LauncherPanel: NSPanel {
    var onToggle: (() -> Void)?
    var shortcut = LauncherShortcut.default
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Keep the direct-event fallback on the same route as native key equivalents.
            if (contentView as? LauncherView)?.handleSettingsShortcut(event) == true { return }
            if (contentView as? LauncherView)?.handleAppAliasShortcut(event) == true { return }
            if (contentView as? LauncherView)?.handleSearchActionsShortcut(event) == true { return }
            if (contentView as? LauncherView)?.handleWebSearchShortcut(event) == true { return }
            if (contentView as? ClipboardView)?.handleSettingsShortcut(event) == true { return }
            if (contentView as? ClipboardView)?.handlePreviewShortcut(event) == true { return }
            if (contentView as? EmojiView)?.handleSettingsShortcut(event) == true { return }
            if (contentView as? GPTView)?.handleKeyEquivalent(event) == true { return }
            if (contentView as? LauncherView)?.handleNumberShortcut(event) == true { return }
            if (contentView as? ClipboardView)?.handleNumberShortcut(event) == true { return }
            if (contentView as? EmojiView)?.handleNumberShortcut(event) == true { return }
            if (contentView as? ClipboardView)?.handleDeleteShortcut(event) == true { return }
            if shortcut.matches(event: event) {
                if !event.isARepeat { onToggle?() }
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
    let model: LauncherModel
    private let panel: LauncherPanel
    private var launcherView: LauncherView!
    private let clipboard: ClipboardModel
    private let emoji: EmojiModel
    private let gpt: GPTModel?
    private let performSystemAction: @MainActor (SystemAction) async throws -> Void
    private let openApplication: @MainActor (IndexedApplication, @escaping @MainActor (Error?) -> Void) -> Void
    private let openFile: @MainActor (URL, @escaping @MainActor (Error?) -> Void) -> Void
    private let openWebURL: @MainActor (URL, URL?, @escaping @MainActor (Error?) -> Void) -> Void
    private let webSearchPreferences: WebSearchPreferences
    private let resolveBrowser: @Sendable (String) -> URL?
    private var webSearchTask: Task<Void, Never>?
    private var webSearchRequest = 0
    private let linkCleaner: any LinkCleaning
    private var linkCleaningTask: Task<Void, Never>?
    private var linkCleaningRequest = 0
    private var linkCleaningStatus: String?
    private let copyCalculatedValue: @Sendable (String) async throws -> Void
    private var calculationCopyTask: Task<Void, Never>?
    private var calculationCopyRequest = 0
    private let selectedText: any SelectedTextAccessing
    private let convertText: @Sendable (String, ChineseConversionTarget) async throws -> String
    private let frontmostProcess: @MainActor () -> Int32?
    private let restoreSource: @MainActor (Int32) -> Bool
    private var sourceProcessID: Int32?
    var windowControlSource: Int32? { panel.isVisible || isSuspendedForSettings ? sourceProcessID : nil }
    private var conversionTask: Task<Void, Never>?
    private var conversionRequest = 0
    private var showingClipboard = false
    private var showingEmoji = false
    private var showingGPT = false
    private var gptView: GPTView?
    private var isDismissing = false
    private(set) var isSuspendedForSettings = false
    private lazy var emojiView: EmojiView = {
        let view = EmojiView(model: emoji, onCopy: { [weak self] index in
            guard let self else { return }
            self.emoji.copySelected(at: index) { [weak self] in self?.dismiss() }
        }, onBack: { [weak self] in self?.showLauncher() })
        view.onSettings = { [weak self] in self?.onSettings?() }
        view.onPreferredHeightChange = { [weak self] height in
            guard let self, self.showingEmoji, self.panel.contentView === self.emojiView else { return }
            self.resizePanel(to: height)
        }
        return view
    }()
    private lazy var clipboardView: ClipboardView = {
        let view = ClipboardView(
            model: clipboard,
            onCopy: { [weak self] index in
                guard let self else { return }
                self.clipboard.copySelected(at: index) { [weak self] in self?.dismiss() }
            },
            onBack: { [weak self] in self?.showLauncher() }
        )
        view.onPreferredHeightChange = { [weak self] height in
            guard let self, self.showingClipboard, self.panel.contentView === self.clipboardView else { return }
            self.resizePanel(to: height)
        }
        return view
    }()
    private var preferences = LauncherPreferences()
    private var invocation = 0
    var onSettings: (() -> Void)?
    var onWindowControls: ((Int32?) -> Void)?
    var onWindowSettings: (() -> Void)?
    var onConversionSettings: (() -> Void)?
    var onWebSearchSettings: (() -> Void)?
    var onGPTSettings: (() -> Void)?
    var onAppAlias: ((IndexedApplication) -> Void)?

    init(clipboard: ClipboardModel,
         model: LauncherModel = LauncherModel(),
         emoji: EmojiModel? = nil,
         gpt: GPTModel? = nil,
         performSystemAction: @escaping @MainActor (SystemAction) async throws -> Void = SystemActions.perform,
         openApplication: @escaping @MainActor (IndexedApplication, @escaping @MainActor (Error?) -> Void) -> Void = LauncherPanelController.openSystemApplication,
         openFile: @escaping @MainActor (URL, @escaping @MainActor (Error?) -> Void) -> Void = LauncherPanelController.openSystemFile,
         webSearchPreferences: WebSearchPreferences? = nil,
         openWebURL: @escaping @MainActor (URL, URL?, @escaping @MainActor (Error?) -> Void) -> Void = LauncherPanelController.openSystemWebURL,
         resolveBrowser: @escaping @Sendable (String) -> URL? = {
             NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
         },
         linkCleaner: (any LinkCleaning)? = nil,
         copyCalculation: (@Sendable (String) async throws -> Void)? = nil,
         selectedText: (any SelectedTextAccessing)? = nil,
         convertText: @escaping @Sendable (String, ChineseConversionTarget) async throws -> String = { text, target in
             try await ChineseConversionEngine.shared.convert(text, to: target)
         },
         frontmostProcess: @escaping @MainActor () -> Int32? = {
             NSWorkspace.shared.frontmostApplication?.processIdentifier
         },
         restoreSource: @escaping @MainActor (Int32) -> Bool = LauncherPanelController.activateSource) {
        self.clipboard = clipboard
        self.emoji = emoji ?? EmojiModel()
        self.gpt = gpt
        self.model = model
        self.performSystemAction = performSystemAction
        self.openApplication = openApplication
        self.openFile = openFile
        self.openWebURL = openWebURL
        self.webSearchPreferences = webSearchPreferences ?? WebSearchPreferences()
        self.resolveBrowser = resolveBrowser
        self.linkCleaner = linkCleaner ?? LinkCleaningService()
        if let copyCalculation { self.copyCalculatedValue = copyCalculation }
        else {
            let writer = CalculatorCopyService()
            self.copyCalculatedValue = { try await writer.copy($0) }
        }
        self.selectedText = selectedText ?? SelectedTextService(
            beforePaste: { await clipboard.beginTransientClipboardUse() },
            afterPaste: { await clipboard.endTransientClipboardUse() }
        )
        self.convertText = convertText
        self.frontmostProcess = frontmostProcess
        self.restoreSource = restoreSource
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 56),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        super.init()
        panel.title = "Cue"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onToggle = { [weak self] in self?.toggle() }
        launcherView = LauncherView(
            model: model,
            onSubmit: { [weak self] in self?.runSelected() },
            onCancel: { [weak self] in
                guard let self else { return }
                if !self.model.closeSearchActions() { self.dismiss() }
            },
            onSettings: { [weak self] in self?.openContextSettings() },
            onWebSearch: { [weak self] in self?.searchGoogle() },
            onSearchActions: { [weak self] in self?.model.toggleSearchActions() },
            onAppAlias: { [weak self] application in self?.onAppAlias?(application) }
        )
        launcherView.onPreferredHeightChange = { [weak self] height in
            guard let self, !self.showingClipboard, self.panel.contentView === self.launcherView else { return }
            self.resizePanel(to: height)
        }
        panel.contentView = launcherView
        panel.initialFirstResponder = launcherView.searchField
        panel.contentView?.layoutSubtreeIfNeeded()
        model.onQueryChange = { [weak self] in
            self?.cancelConversion()
            self?.cancelWebSearch()
            self?.cancelLinkCleaning()
            self?.cancelCalculationCopy()
        }
        model.onSelectionChange = { [weak self] in self?.cancelCalculationCopy() }
        refreshWebSearchPreferences()
        self.webSearchPreferences.onChange = { [weak self] in
            self?.cancelWebSearch()
            self?.refreshWebSearchPreferences()
        }
    }

    func apply(_ preferences: LauncherPreferences) {
        let preferences = preferences.sanitized()
        self.preferences = preferences
        panel.shortcut = preferences.shortcut
        model.setResultLimit(preferences.maxResults)
    }

    func toggle() {
        if panel.isVisible { dismiss() } else { show() }
    }

    func show(resetQuery: Bool = true, sourceProcessIdentifier: Int32? = nil) {
        if isSuspendedForSettings {
            resumeAfterSettings()
            return
        }
        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            focusIfPresented()
            return
        }
        prepareInvocation(resetQuery: resetQuery)
        if let sourceProcessIdentifier { sourceProcessID = sourceProcessIdentifier }
        launcherView.scrollToSelection()
        let screen: NSScreen?
        switch preferences.display {
        case .pointer:
            screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main
        case .main:
            screen = NSScreen.screens.first
        }
        if let frame = screen?.visibleFrame {
            let size = NSSize(width: min(640, frame.width - 24), height: min(launcherView.preferredHeight, frame.height - 24))
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + (frame.height - size.height) * 0.65
            )
            let targetFrame = NSRect(origin: origin, size: size)
            if panel.frame != targetFrame { panel.setFrame(targetFrame, display: false) }
        }
        // Capture the source before activation. A regular key panel routes real
        // keyboard input to Cue without relying on nonactivating focus stealing.
        // The native field already exists; no delayed handoff enters typing.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(launcherView.searchField)
    }

    /// Activation can complete after the show call. Reassert only a presented
    /// launcher, without activating, reopening, or resetting a newer invocation.
    func focusIfPresented() {
        guard panel.isVisible, !isDismissing else { return }
        panel.makeKeyAndOrderFront(nil)
        // Feature settings own their focus; never target the hidden history field.
        if showingGPT {
            gptView?.focusInput()
        } else if showingEmoji {
            panel.makeFirstResponder(emojiView.searchField)
        } else if showingClipboard {
            clipboardView.focusInput()
        } else {
            panel.makeFirstResponder(launcherView.searchField)
        }
    }

    /// Warm the local catalog after the launcher and global hotkey are ready.
    func prepareEmojiSearch() { emoji.prepare() }

    /// Establish an invocation independently of window presentation. This only
    /// samples the source PID; accessibility and conversion stay deferred.
    func prepareInvocation(resetQuery: Bool = true) {
        if isSuspendedForSettings { dismiss(returnFocus: false) }
        cancelCalculationCopy()
        emoji.cancelPendingCopy()
        cancelLinkCleaning()
        model.icons.refreshBrowserIcons()
        cancelWebSearch()
        cancelConversion()
        let frontmost = frontmostProcess()
        sourceProcessID = frontmost == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        invocation += 1
        if resetQuery { model.reset() }
    }

    private func resizePanel(to preferredHeight: CGFloat) {
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let height = min(preferredHeight, (visibleFrame?.height ?? preferredHeight + 24) - 24)
        guard panel.frame.height != height else { return }
        var frame = panel.frame
        // Keep the search field anchored while results grow below it. No animation,
        // focus handoff, or deferred resize enters the typing path.
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        if let visibleFrame { frame.origin.y = max(frame.origin.y, visibleFrame.minY + 12) }
        panel.setFrame(frame, display: panel.isVisible, animate: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func dismiss(cancelConversion shouldCancel: Bool = true, returnFocus: Bool = true) {
        guard !isDismissing else { return }
        isDismissing = true
        isSuspendedForSettings = false
        defer { isDismissing = false }
        let returnToSource = returnFocus && panel.isVisible
            && frontmostProcess() == ProcessInfo.processInfo.processIdentifier
        let source = sourceProcessID
        cancelCalculationCopy()
        clipboard.cancelPendingCopy()
        cancelWebSearch()
        cancelLinkCleaning()
        if shouldCancel { cancelConversion() }
        invocation += 1
        panel.orderOut(nil)
        if showingClipboard {
            clipboard.close()
            clipboardView.closeSettings()
            clipboardView.closePreview()
            showingClipboard = false
            panel.contentView = launcherView
            panel.initialFirstResponder = launcherView.searchField
        }
        if showingEmoji {
            emoji.close()
            showingEmoji = false
            panel.contentView = launcherView
            panel.initialFirstResponder = launcherView.searchField
        }
        if showingGPT {
            gpt?.close()
            showingGPT = false
            panel.contentView = launcherView
            panel.initialFirstResponder = launcherView.searchField
        }
        model.reset()
        resizePanel(to: launcherView.preferredHeight)
        if returnToSource, let source { _ = restoreSource(source) }
    }

    /// Hide without discarding the current page. No task is allowed to finish an
    /// earlier action while the user is editing settings in another window.
    @discardableResult
    func suspendForSettings() -> Bool {
        // Settings is a new interaction even when there is no launcher to retain.
        // Ignore late app/browser/system-action failures from a dismissed panel.
        invocation += 1
        if isSuspendedForSettings { return true }
        guard panel.isVisible || showingGPT || showingClipboard || showingEmoji || !model.query.isEmpty else { return false }
        isSuspendedForSettings = true
        isDismissing = true
        defer { isDismissing = false }
        cancelCalculationCopy()
        cancelWebSearch()
        cancelLinkCleaning()
        cancelConversion()
        clipboard.cancelPendingCopy()
        emoji.cancelPendingCopy()
        model.suspendFileSearch()
        model.icons.prepare([])
        if showingGPT { gpt?.suspendForSettings() }
        panel.orderOut(nil)
        return true
    }

    /// Restore state separately from window presentation so native integration
    /// checks can verify this transition without activating or showing a window.
    @discardableResult
    func restoreSettingsContext() -> Bool {
        guard isSuspendedForSettings else { return false }
        isSuspendedForSettings = false
        model.resumeFileSearch()
        model.icons.prepare(model.results.compactMap {
            if case .application(let application) = $0 { return application }
            return nil
        })
        if showingGPT { gpt?.resumeAfterSettings() }
        return true
    }

    func resumeAfterSettings() {
        guard restoreSettingsContext() else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusIfPresented()
    }

    private func showClipboard() {
        showingClipboard = true
        clipboard.open()
        panel.contentView = clipboardView
        panel.initialFirstResponder = clipboardView.searchField
        resizePanel(to: clipboardView.preferredHeight)
        panel.makeFirstResponder(clipboardView.searchField)
    }

    private func showLauncher() {
        let returningFromGPT = showingGPT
        if showingGPT {
            gpt?.close()
            showingGPT = false
        }
        if showingClipboard {
            clipboard.close()
            clipboardView.closeSettings()
            clipboardView.closePreview()
            showingClipboard = false
        }
        if showingEmoji {
            emoji.close()
            showingEmoji = false
        }
        // Back from a reply keeps the original input for a different action.
        if !returningFromGPT { model.reset() }
        panel.contentView = launcherView
        panel.initialFirstResponder = launcherView.searchField
        resizePanel(to: launcherView.preferredHeight)
        panel.makeFirstResponder(launcherView.searchField)
    }

    private func showEmoji() {
        showingEmoji = true
        emoji.open()
        panel.contentView = emojiView
        panel.initialFirstResponder = emojiView.searchField
        resizePanel(to: emojiView.preferredHeight)
        panel.makeFirstResponder(emojiView.searchField)
    }

    private func showGPT(_ mode: GPTMode) {
        guard let gpt else { onGPTSettings?(); return }
        if gptView == nil {
            let view = GPTView(model: gpt)
            view.onBack = { [weak self] in self?.showLauncher() }
            view.onSettings = { [weak self] in self?.onGPTSettings?() }
            view.onPreferredHeightChange = { [weak self] height in
                guard let self, self.showingGPT else { return }
                self.resizePanel(to: height)
            }
            gptView = view
        }
        guard let view = gptView else { return }
        showingGPT = true
        panel.contentView = view
        panel.initialFirstResponder = view
        resizePanel(to: view.preferredHeight)
        view.focusInput()
        gpt.open(input: model.query, mode: mode)
    }

    func stopGPT() {
        gpt?.stop()
        gpt?.cancelPendingCopy()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isDismissing, panel.isVisible else { return }
        cancelCalculationCopy()
        clipboard.cancelPendingCopy()
        cancelLinkCleaning()
        cancelWebSearch()
        cancelConversion()
        emoji.cancelPendingCopy()
        if showingGPT { stopGPT() }
        // The user chose another window; do not reactivate the invocation source.
        if preferences.dismissOnFocusLoss { dismiss(returnFocus: false) }
    }

    private func runSelected() {
        guard let result = model.selectedResult else { return }
        if result.numericCopyValue == nil { cancelCalculationCopy() }
        if result != .cleanLink { cancelLinkCleaning() }
        if !result.isWebSearch { cancelWebSearch() }
        if result != .convertToTraditional && result != .convertToSimplified { cancelConversion() }
        switch result {
        case .calculation, .conversion:
            copyNumericResult(result)
        case .currencyStatus(let state):
            if state == .unavailable { model.retryCurrencyRates() }
        case .googleSearch:
            searchGoogle()
        case .googleSearchIn(let browser):
            searchGoogle(in: browser)
        case .webSearchSettings:
            onWebSearchSettings?()
        case .chooseSearchBrowser:
            model.showSearchBrowsers()
        case .askGPT:
            showGPT(.answer)
        case .translateGPT:
            showGPT(.translate)
        case .gptSettings:
            onGPTSettings?()
        case .convertToTraditional:
            runConversion(.traditionalTaiwan, resultID: result.id)
        case .convertToSimplified:
            runConversion(.simplifiedChina, resultID: result.id)
        case .chineseConversionSettings:
            onConversionSettings?()
        case .updateIndex:
            guard !model.isIndexing else { return }
            let query = model.query
            Task {
                if await model.loadApplications() {
                    model.recordSuccessfulAction(resultID: result.id, query: query)
                }
            }
        case .cleanLink:
            cleanClipboardLink()
        case .emojiSearch:
            let query = model.query
            showEmoji()
            model.recordSuccessfulAction(resultID: result.id, query: query)
        case .clipboardHistory:
            let query = model.query
            showClipboard()
            model.recordSuccessfulAction(resultID: result.id, query: query)
        case .sleep:
            runSystemAction(.sleep)
        case .lockScreen:
            runSystemAction(.lockScreen)
        case .screenOff:
            runSystemAction(.screenOff)
        case .windowControls:
            onWindowControls?(sourceProcessID)
        case .windowSettings:
            onWindowSettings?()
        case .application(let application):
            launch(application)
        case .file(let file):
            launchFile(file)
        }
    }

    private func cancelLinkCleaning() {
        linkCleaningRequest += 1
        linkCleaningTask?.cancel()
        linkCleaningTask = nil
        if let linkCleaningStatus, model.actionStatus == linkCleaningStatus { model.actionStatus = nil }
        linkCleaningStatus = nil
    }

    private func cancelCalculationCopy() {
        calculationCopyRequest += 1
        calculationCopyTask?.cancel()
        calculationCopyTask = nil
        if model.actionStatus == LauncherText.shared.calculationCopying { model.actionStatus = nil }
    }

    private func copyNumericResult(_ result: LauncherResult) {
        guard calculationCopyTask == nil, let value = result.numericCopyValue,
              model.canCopyNumericResult(result) else { return }
        calculationCopyRequest += 1
        let request = calculationCopyRequest
        let requestInvocation = invocation
        let query = model.query
        model.launchError = nil
        model.actionStatus = LauncherText.shared.calculationCopying
        calculationCopyTask = Task { [weak self, copyCalculatedValue] in
            do {
                try Task.checkCancellation()
                try await copyCalculatedValue(value)
                try Task.checkCancellation()
                guard let self, self.calculationCopyRequest == request,
                      self.invocation == requestInvocation, self.model.query == query,
                      self.model.selectedResult == result else { return }
                self.calculationCopyTask = nil
                self.model.actionStatus = nil
                // Neither the expression nor its result is a learnable command.
                self.dismiss()
            } catch {
                guard !Task.isCancelled, let self, self.calculationCopyRequest == request,
                      self.invocation == requestInvocation else { return }
                self.calculationCopyTask = nil
                self.model.actionStatus = nil
                self.model.launchError = (error as? CalculatorCopyService.Failure) == .denied
                    ? LauncherText.shared.calculationAccessDenied : LauncherText.shared.calculationCopyError
            }
        }
    }

    private func setLinkCleaningStatus(_ status: String?) {
        linkCleaningStatus = status
        model.actionStatus = status
    }

    private func cleanClipboardLink() {
        guard linkCleaningTask == nil else { return }
        let requestInvocation = invocation
        linkCleaningRequest += 1
        let request = linkCleaningRequest
        model.launchError = nil
        setLinkCleaningStatus(LauncherText.shared.cleaningLink)
        linkCleaningTask = Task { [weak self, linkCleaner] in
            do {
                let preparation = try await linkCleaner.prepare()
                try Task.checkCancellation()
                guard let self, self.invocation == requestInvocation, self.linkCleaningRequest == request else { return }
                if preparation.result.removedParameterCount > 0 { try await linkCleaner.commit(preparation) }
                try Task.checkCancellation()
                guard self.invocation == requestInvocation, self.linkCleaningRequest == request else { return }
                let result = preparation.result
                self.setLinkCleaningStatus(result.isProtected ? LauncherText.shared.linkProtected
                    : result.removedParameterCount == 0 ? LauncherText.shared.linkAlreadyClean
                    : L10n.format(LauncherText.shared.linkCleaned, result.removedParameterCount))
                // Clipboard payloads never enter command usage learning or logs.
            } catch {
                guard let self, !Task.isCancelled, self.invocation == requestInvocation,
                      self.linkCleaningRequest == request else { return }
                self.setLinkCleaningStatus(nil)
                switch error {
                case LinkCleaner.Error.inputTooLarge: self.model.launchError = LauncherText.shared.linkTooLarge
                case LinkCleaningError.clipboardChanged: self.model.launchError = LauncherText.shared.linkClipboardChanged
                case LinkCleaningError.accessDenied: self.model.launchError = LauncherText.shared.linkAccessDenied
                case LinkCleaningError.writeFailed: self.model.launchError = LauncherText.shared.linkWriteFailed
                default: self.model.launchError = LauncherText.shared.linkInvalid
                }
            }
            if let self, self.linkCleaningRequest == request { self.linkCleaningTask = nil }
        }
    }

    private func refreshWebSearchPreferences() {
        model.icons.prepareBrowserIcons(webSearchPreferences.browsers)
        model.setWebSearchPreferences(enabled: webSearchPreferences.isEnabled,
                                      browsers: webSearchPreferences.browsers)
    }

    private func cancelWebSearch() {
        webSearchRequest += 1
        webSearchTask?.cancel()
        webSearchTask = nil
        if model.actionStatus == LauncherText.shared.openingBrowser { model.actionStatus = nil }
    }

    private func searchGoogle(in browser: WebSearchBrowser? = nil) {
        cancelCalculationCopy()
        cancelLinkCleaning()
        let query = model.query
        guard !model.isQueryEmpty, !model.isFileSearch, webSearchTask == nil else { return }
        // Explicit browser handoffs have their own feature switch. Cue makes no
        // HTTP request, suggestion lookup, DNS lookup, or query-history write.
        guard webSearchPreferences.isEnabled else {
            model.launchError = LauncherText.shared.webSearchDisabled
            return
        }
        guard let url = WebSearch.googleURL(for: query) else { return }
        guard let browser else {
            handOffSearch(url, query: query, applicationURL: nil)
            return
        }
        guard webSearchPreferences.browsers.contains(where: { $0.id == browser.id }) else { return }
        model.launchError = nil
        model.actionStatus = LauncherText.shared.openingBrowser
        webSearchRequest += 1
        let request = webSearchRequest
        let requestInvocation = invocation
        // Resolve the saved bundle ID only on execution, off the input thread.
        // Do not cache machine-specific paths or silently use another browser.
        webSearchTask = Task { [weak self, resolveBrowser] in
            let applicationURL = await Task.detached(priority: .userInitiated) {
                resolveBrowser(browser.bundleIdentifier)
            }.value
            guard let self, !Task.isCancelled, self.webSearchRequest == request,
                  self.invocation == requestInvocation,
                  self.webSearchPreferences.isEnabled,
                  self.webSearchPreferences.browsers.contains(where: { $0.id == browser.id }) else { return }
            self.webSearchTask = nil
            self.model.actionStatus = nil
            guard let applicationURL else {
                self.model.launchError = L10n.format(LauncherText.shared.browserUnavailable, browser.name)
                return
            }
            self.handOffSearch(url, query: query, applicationURL: applicationURL)
        }
    }

    private func handOffSearch(_ url: URL, query: String, applicationURL: URL?) {
        dismiss(returnFocus: false)
        let searchInvocation = invocation
        let searchRequest = webSearchRequest
        openWebURL(url, applicationURL) { [weak self] error in
            guard let self, error != nil, self.invocation == searchInvocation,
                  self.webSearchRequest == searchRequest else { return }
            self.model.setQuery(query)
            self.model.launchError = LauncherText.shared.webSearchError
            self.show(resetQuery: false)
        }
    }

    private func openContextSettings() {
        cancelCalculationCopy()
        switch model.selectedResult {
        case .googleSearch, .googleSearchIn, .webSearchSettings, .chooseSearchBrowser:
            onWebSearchSettings?()
        case .askGPT, .translateGPT, .gptSettings:
            onGPTSettings?()
        case .convertToTraditional, .convertToSimplified, .chineseConversionSettings:
            onConversionSettings?()
        case .windowControls, .windowSettings:
            onWindowSettings?()
        default:
            onSettings?()
        }
    }

    private func cancelConversion() {
        conversionTask?.cancel()
        if model.actionStatus == ChineseConversionText.converting { model.actionStatus = nil }
    }

    /// Conversion keeps the original invocation target while Cue owns keyboard
    /// input. Any other foreground app invalidates the pending action.
    static func acceptsConversionContext(source: Int32, frontmost: Int32?, launcherHasFocus: Bool) -> Bool {
        frontmost == source || (frontmost == ProcessInfo.processInfo.processIdentifier && launcherHasFocus)
    }

    private func ownsConversionContext(_ source: Int32) -> Bool {
        Self.acceptsConversionContext(source: source, frontmost: frontmostProcess(),
                                      launcherHasFocus: panel.isVisible && panel.isKeyWindow)
    }

    /// Drain bounded paste acknowledgement/clipboard restoration before quitting.
    func finishPendingTextConversion() async {
        cancelConversion()
        await conversionTask?.value
    }

    private func runConversion(_ target: ChineseConversionTarget, resultID: String) {
        // Suppress repeated Return/number events while this request is pending.
        guard model.actionStatus == nil else { return }
        guard let sourceProcessID else {
            model.launchError = ChineseConversionText.noSelection
            return
        }
        let query = model.query
        let requestInvocation = invocation
        let previous = conversionTask
        previous?.cancel()
        conversionRequest += 1
        let request = conversionRequest
        model.launchError = nil
        model.actionStatus = ChineseConversionText.converting
        conversionTask = Task { [weak self, selectedText, convertText] in
            // A cancelled paste may still need acknowledgement before restoring
            // the clipboard. Serialize a later request behind that cleanup.
            await previous?.value
            guard let self else { return }
            var session: SelectedTextSession?
            var completionInvocation = requestInvocation
            do {
                try Task.checkCancellation()
                guard self.invocation == requestInvocation, self.ownsConversionContext(sourceProcessID) else {
                    throw SelectedTextError.selectionChanged
                }
                let captured = try await selectedText.capture(processID: sourceProcessID)
                session = captured
                let converted = try await convertText(captured.text, target)
                try Task.checkCancellation()
                guard self.invocation == requestInvocation,
                      self.ownsConversionContext(sourceProcessID) else {
                    throw SelectedTextError.selectionChanged
                }
                self.dismiss(cancelConversion: false, returnFocus: false)
                completionInvocation = self.invocation
                guard self.restoreSource(sourceProcessID) else {
                    throw SelectedTextError.applicationUnavailable
                }
                try await selectedText.replace(captured, with: converted)
                self.model.recordSuccessfulAction(resultID: resultID, query: query)
            } catch {
                if !(error is CancellationError), !Task.isCancelled,
                   self.invocation == completionInvocation, self.conversionRequest == request,
                   self.ownsConversionContext(sourceProcessID) {
                    self.model.actionStatus = nil
                    if (error as? SelectedTextError) == .permissionRequired {
                        self.onConversionSettings?()
                    } else {
                        self.model.setQuery(query)
                        self.model.launchError = ChineseConversionText.message(for: error)
                        self.show(resetQuery: false)
                    }
                }
            }
            if let session { await selectedText.discard(session) }
            if self.conversionRequest == request {
                self.model.actionStatus = nil
                self.conversionTask = nil
            }
        }
    }

    private static func activateSource(_ processID: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated else {
            return false
        }
        if application.isActive { return true }
        return application.activate(options: [])
    }

    private func runSystemAction(_ action: SystemAction) {
        let query = model.query
        let resultID: String
        let failureMessage: String
        switch action {
        case .sleep:
            resultID = LauncherResult.sleep.id
            failureMessage = LauncherText.shared.sleepError
        case .lockScreen:
            resultID = LauncherResult.lockScreen.id
            failureMessage = LauncherText.shared.lockError
        case .screenOff:
            resultID = LauncherResult.screenOff.id
            failureMessage = LauncherText.shared.screenOffError
        }
        // Close immediately; system calls and framework loading stay off typing's
        // event path. Tests inject actions to avoid changing the Mac's state.
        dismiss()
        let actionInvocation = invocation
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performSystemAction(action)
                self.model.recordSuccessfulAction(resultID: resultID, query: query)
            } catch {
                // Never steal focus back for an old failed request after reopening.
                guard self.invocation == actionInvocation else { return }
                self.model.setQuery(query)
                self.model.launchError = failureMessage
                self.show(resetQuery: false)
            }
        }
    }

    private func launch(_ application: IndexedApplication) {
        let query = model.query
        // Acknowledge Enter immediately, independent of another app's startup time.
        dismiss(returnFocus: false)
        let launchInvocation = invocation
        let resultID = LauncherResult.application(application).id
        openApplication(application) { [weak self] error in
            guard let self else { return }
            if let error {
                guard self.invocation == launchInvocation else { return }
                self.model.setQuery(query)
                self.show(resetQuery: false)
                self.model.launchError = L10n.format(
                    LauncherText.shared.launchError, application.name, error.localizedDescription
                )
            } else {
                // A completed launch still counts if the user has already begun another search.
                self.model.recordSuccessfulAction(resultID: resultID, query: query)
            }
        }
    }

    private static func openSystemApplication(
        _ application: IndexedApplication, completion: @escaping @MainActor (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) { _, error in
            Task { @MainActor in completion(error) }
        }
    }

    private func launchFile(_ file: FileSearchResult) {
        let query = model.query
        // Finder/default app owns opening. Never read contents, resolve aliases,
        // or fetch cloud placeholders on the search or selection path.
        dismiss(returnFocus: false)
        let launchInvocation = invocation
        openFile(file.url) { [weak self] error in
            guard let self, let error, self.invocation == launchInvocation else { return }
            self.model.setQuery(query)
            self.show(resetQuery: false)
            self.model.launchError = L10n.format(
                LauncherText.shared.launchError, file.name, error.localizedDescription
            )
        }
    }

    private static func openSystemFile(_ url: URL, completion: @escaping @MainActor (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            Task { @MainActor in completion(error) }
        }
    }

    private static func openSystemWebURL(_ url: URL, applicationURL: URL?, completion: @escaping @MainActor (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let applicationURL {
            NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
                Task { @MainActor in completion(error) }
            }
        } else {
            NSWorkspace.shared.open(url, configuration: configuration) { _, error in
                Task { @MainActor in completion(error) }
            }
        }
    }
}
