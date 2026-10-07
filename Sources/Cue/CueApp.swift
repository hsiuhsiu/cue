import AppKit
import Combine
import CueCore

private enum MenuText {
    static let settings = L10n.string("menu.settings", table: "Menu", value: "Settings…")
    static let windowSettings = L10n.string("menu.windowSettings", table: "Menu", value: "Window Settings…")
    static let checkForUpdates = L10n.string("menu.checkForUpdates", table: "Menu", value: "Check for Updates…")
    static let networkOff = L10n.string("menu.networkOff", table: "Menu", value: "Updates Disabled (Network Off)")
    static let updateAvailable = L10n.string("menu.updateAvailable", table: "Menu", value: "Update Available (%@)…")
    static let updateAccessibility = L10n.string("menu.updateAccessibility", table: "Menu", value: "Cue — update available")
    static let about = L10n.string("menu.about", table: "Menu", value: "About Cue")
    static let show = L10n.string("menu.show", table: "Menu", value: "Show Cue")
    static let quit = L10n.string("menu.quit", table: "Menu", value: "Quit Cue")
    static let edit = L10n.string("menu.edit", table: "Menu", value: "Edit")
    static let undo = L10n.string("menu.undo", table: "Menu", value: "Undo")
    static let cut = L10n.string("menu.cut", table: "Menu", value: "Cut")
    static let copy = L10n.string("menu.copy", table: "Menu", value: "Copy")
    static let paste = L10n.string("menu.paste", table: "Menu", value: "Paste")
    static let selectAll = L10n.string("menu.selectAll", table: "Menu", value: "Select All")
    static let shortcutUnavailable = L10n.string(
        "menu.shortcutUnavailable", table: "Menu",
        value: "%1$@ is unavailable (%2$d). Change it in Settings."
    )
    static let shortcutConflict = L10n.string(
        "menu.shortcutConflict", table: "Menu",
        value: "%1$@ is unavailable (%2$d). Try another shortcut; your previous shortcut is unchanged."
    )
    static let appUnavailable = L10n.string("menu.appUnavailable", table: "Menu", value: "Cue is unavailable.")
}

@main
struct CueApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var launcher: LauncherPanelController!
    private var clipboard: ClipboardModel!
    private var isTerminating = false
    private var hotKey: HotKeyManager!
    private var windowHotKey: HotKeyManager!
    private let windowPreferences = WindowControlPreferences()
    private var windowMode: WindowModeController!
    private var windowSettingsController: WindowControlSettingsController?
    private var statusItem: NSStatusItem!
    private let settings = CueSettings()
    private let networkPolicy = NetworkPolicy()
    private var settingsController: SettingsWindowController?
    private var backupController: BackupSettingsController?
    private var backupCoordinator: SettingsBackupCoordinator?
    private let webSearchPreferences = WebSearchPreferences()
    private var webSearchSettingsController: WebSearchSettingsController?
    private let gptPreferences = GPTPreferences()
    private var gptSettingsController: GPTSettingsController?
    private var gptNetworkSubscription: AnyCancellable?
    private let conversionPreferences = ChineseConversionPreferences()
    private var conversionSettingsController: ChineseConversionSettingsController?
    private let appAliasPreferences = AppAliasPreferences()
    private var appAliasSettingsController: AppAliasSettingsController?
    private enum SettingsPage { case general, webSearch, gpt, conversion, appAlias, window }
    private var settingsOwner: SettingsPage?
    private var returnToGPTSettings = false
    private lazy var loginItem = LoginItemController()
    private var preferencesSubscription: AnyCancellable?
    private var updates: UpdateController!
    private var updateSubscription: AnyCancellable?
    private var updateMenuItems: [NSMenuItem] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private lazy var menuBarIcon = Self.menuBarImage(named: "MenuBarIconTemplate")
    private lazy var menuBarUpdateIcon = Self.menuBarImage(named: "MenuBarIconUpdateTemplate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        clipboard = ClipboardModel()
        let usageURL = URL.homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yyhsiu.cue", isDirectory: true)
            .appendingPathComponent("Search/usage.json")
        let model = LauncherModel(usageStore: SearchUsageStore(fileURL: usageURL),
                                  conversionAliases: conversionPreferences.aliases,
                                  applicationAliases: appAliasPreferences.aliases,
                                  awaitingInitialIndex: true,
                                  currencyRates: CurrencyRatesController(policy: networkPolicy))
        let gpt = GPTModel(client: GPTClient(policy: networkPolicy), preferences: gptPreferences)
        let historyURL = usageURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CommandHistory/history.json")
        let commandHistory = CommandHistoryModel(
            store: CommandHistoryStore(fileURL: historyURL), defaults: .standard)
        launcher = LauncherPanelController(clipboard: clipboard, model: model, gpt: gpt,
                                           commandHistory: commandHistory,
                                           webSearchPreferences: webSearchPreferences)
        windowMode = WindowModeController(preferences: windowPreferences)
        windowMode.onSettings = { [weak self] in self?.showWindowSettings() }
        launcher.onWindowControls = { [weak self] source in self?.showWindowControls(source: source) }
        launcher.onWindowSettings = { [weak self] in self?.showWindowSettings() }
        launcher.onSettings = { [weak self] in self?.showSettings() }
        launcher.onWebSearchSettings = { [weak self] in self?.showWebSearchSettings() }
        launcher.onGPTSettings = { [weak self] in self?.showGPTSettings() }
        gptPreferences.onChange = { [weak self] in self?.launcher.stopGPT() }
        gptNetworkSubscription = networkPolicy.changes.prepend(networkPolicy.allowsNetwork)
            .sink { [weak model] allowed in model?.setAllowsGPTNetwork(allowed) }
        launcher.onConversionSettings = { [weak self] in self?.showConversionSettings() }
        launcher.onAppAlias = { [weak self] application in self?.showAppAliasSettings(for: application) }
        appAliasPreferences.onChange = { [weak model] aliases in model?.setApplicationAliases(aliases) }
        conversionPreferences.validateAliases = { [weak self] aliases in
            self?.appAliasPreferences.conflict(with: aliases)
        }
        conversionPreferences.onChange = { [weak model] aliases in model?.setConversionAliases(aliases) }
        configureMenuBar()
        configureEditingMenu()
        hotKey = HotKeyManager { [weak self] in
            guard let self else { return }
            guard self.backupController?.window?.isVisible != true else { return }
            if self.settingsController?.finishRecordingCurrentShortcut() == true
                || self.windowSettingsController?.finishRecordingCurrentShortcut() == true { return }
            if self.windowSettingsController?.window?.attachedSheet != nil { return }
            if self.windowMode.isVisible || self.windowMode.suspendedForSettings {
                let source = self.windowMode.targetProcessIdentifier
                self.windowSettingsController?.hide()
                self.settingsOwner = nil
                self.returnToGPTSettings = false
                self.windowMode.dismiss(returnFocus: false)
                self.launcher.show(sourceProcessIdentifier: source)
            } else { self.launcher.toggle() }
        }
        let status = hotKey.register(shortcut: settings.preferences.shortcut)
        if status != noErr {
            launcher.model.shortcutError = L10n.format(
                MenuText.shortcutUnavailable, settings.preferences.shortcut.localizedDisplayName, status
            )
            launcher.show()
        }
        windowHotKey = HotKeyManager { [weak self] in
            guard let self else { return }
            guard self.backupController?.window?.isVisible != true else { return }
            if self.windowSettingsController?.finishRecordingCurrentShortcut() == true
                || self.settingsController?.finishRecordingCurrentShortcut() == true { return }
            if self.windowSettingsController?.window?.attachedSheet != nil { return }
            if self.windowMode.isVisible { self.windowMode.dismiss(returnFocus: true) }
            else { self.showWindowControls(source: self.launcher.windowControlSource) }
        }
        windowPreferences.applyConfiguration = { [weak self] proposed in
            guard let self else { return MenuText.appUnavailable }
            guard proposed.enabled else { self.windowHotKey.unregister(); return nil }
            guard WindowControlConfiguration.isValidShortcut(self.settings.preferences.shortcut) else {
                return L10n.string("shortcut.launcherActionConflict", table: "WindowSettings",
                    value: "The Open Cue shortcut uses a window action key. Change it in Cue Settings first.")
            }
            if proposed.shortcut.keyCode == self.settings.preferences.shortcut.keyCode,
               proposed.shortcut.modifiers == self.settings.preferences.shortcut.modifiers {
                return L10n.string("shortcut.launcherConflict", table: "WindowSettings", value: "This shortcut is already used to open Cue.")
            }
            let status = self.windowHotKey.register(shortcut: proposed.shortcut)
            return status == noErr ? nil : L10n.format(MenuText.shortcutConflict, proposed.shortcut.localizedDisplayName, status)
        }
        windowPreferences.onChange = { [weak self] _ in self?.windowMode.settingsDidChange() }
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hotKey.resetPressedState()
                self?.windowHotKey.resetPressedState()
            }
        })
        Task { await windowPreferences.load() }
        preferencesSubscription = settings.$preferences.sink { [weak self] preferences in
            self?.launcher.apply(preferences)
            self?.statusItem.button?.toolTip = "Cue — \(preferences.shortcut.localizedDisplayName)"
        }
        Task { await launcher.model.loadApplications() }
        launcher.model.startUsageTracking()
        launcher.commandHistory.start()
        launcher.prepareEmojiSearch()
        // Construct the launcher and register its hotkey before starting update work.
        updates = UpdateController(networkPolicy: networkPolicy)
        updates.onPresentUpdate = { [weak self] in
            self?.launcher.dismiss(returnFocus: false)
            NSApp.activate()
        }
        updateSubscription = updates.$availableVersion.combineLatest(
            updates.$canCheckForUpdates, networkPolicy.changes.prepend(networkPolicy.allowsNetwork)
        )
            .sink { [weak self] version, canCheck, allowsNetwork in
                guard let self else { return }
                self.updateMenuItems.forEach {
                    $0.title = allowsNetwork
                        ? (version.map { L10n.format(MenuText.updateAvailable, $0) } ?? MenuText.checkForUpdates)
                        : MenuText.networkOff
                    $0.isEnabled = allowsNetwork && canCheck
                }
                let hasUpdate = allowsNetwork && version != nil
                self.statusItem.button?.image = hasUpdate ? self.menuBarUpdateIcon : self.menuBarIcon
                self.statusItem.button?.setAccessibilityLabel(hasUpdate ? MenuText.updateAccessibility : "Cue")
            }
        Task { @MainActor [weak self] in self?.updates.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let clipboard else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        launcher.dismiss(returnFocus: false)
        windowMode.dismiss(returnFocus: false)
        clipboard.stop()
        Task {
            await backupController?.prepareForTermination()
            async let clipboardFinished: Void = clipboard.prepareForTermination()
            async let usageFinished: Void = launcher.model.prepareForTermination()
            async let historyFinished: Void = launcher.commandHistory.finish()
            async let conversionFinished: Void = launcher.finishPendingTextConversion()
            async let windowSettingsFinished: Void = windowPreferences.flush()
            _ = await (clipboardFinished, usageFinished, historyFinished, conversionFinished, windowSettingsFinished)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
        windowHotKey?.unregister()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        clipboard?.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        launcher?.focusIfPresented()
        windowMode?.focusIfPresented()
        // Reflect changes made in macOS Login Items when returning to Settings.
        // No service lookup is performed for ordinary launcher invocation.
        settingsController?.refreshLoginItemStatus()
        conversionSettingsController?.refreshAccess()
        windowSettingsController?.refreshAccess()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsController?.window?.isVisible != true,
           conversionSettingsController?.window?.isVisible != true,
           appAliasSettingsController?.window?.isVisible != true,
           gptSettingsController?.window?.isVisible != true,
           webSearchSettingsController?.window?.isVisible != true,
           backupController?.window?.isVisible != true,
           windowSettingsController?.window?.isVisible != true,
           windowMode?.isVisible != true { launcher.show() }
        return false
    }

    @objc private func showCue() {
        guard backupController?.window?.isVisible != true else { return }
        let source = windowMode.isVisible ? windowMode.targetProcessIdentifier : nil
        windowMode.dismiss(returnFocus: false)
        launcher.show(sourceProcessIdentifier: source)
    }
    @objc private func quitCue() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updates.checkForUpdates() }

    @objc private func showAbout() {
        launcher.dismiss(returnFocus: false)
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: AppVersion().displayVersion
                ?? L10n.string("updates.development_build", table: "Settings", value: "Development build"),
            // Keep the internal Sparkle build counter out of the public label.
            .version: ""
        ])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showWindowSettings) {
            // Do not bypass another editor or an import preview from the menu.
            // Its in-progress values and return-to-launcher context stay intact.
            return ![backupController?.window, settingsController?.window,
                     conversionSettingsController?.window, appAliasSettingsController?.window,
                     gptSettingsController?.window, webSearchSettingsController?.window]
                .contains { $0?.isVisible == true }
        }
        if menuItem.action == #selector(checkForUpdates) {
            return networkPolicy.allowsNetwork && (updates?.canCheckForUpdates ?? false)
        }
        return true
    }

    private func showWindowControls(source: Int32?) {
        guard windowPreferences.hasLoaded, windowPreferences.loadError == nil,
              windowPreferences.snapshot.enabled else { showWindowSettings(); return }
        let target = (windowMode.suspendedForSettings ? windowMode.targetProcessIdentifier : nil)
            ?? source ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        settingsOwner = nil
        returnToGPTSettings = false
        launcher.dismiss(returnFocus: false)
        windowSettingsController?.hide()
        windowMode.show(sourceProcessIdentifier: target)
    }

    @objc private func showWindowSettings() {
        // The import preview remains the sole settings editor until it is closed.
        if backupController?.window?.isVisible == true {
            backupController?.window?.makeKeyAndOrderFront(nil)
            return
        }
        prepareSettings(.window)
        if windowSettingsController == nil {
            windowSettingsController = WindowControlSettingsController(preferences: windowPreferences)
            windowSettingsController?.capturedPreset = { [weak self] in self?.windowMode.presetForCurrentWindow() }
            windowSettingsController?.onClose = { [weak self] in self?.finishSettings(.window) }
        }
        windowSettingsController?.show()
    }

    @objc private func showSettings() {
        if backupController?.window?.isVisible == true {
            backupController?.window?.makeKeyAndOrderFront(nil)
            return
        }
        if windowMode.isVisible { showWindowSettings(); return }
        prepareSettings(.general)
        if settingsController == nil {
            settingsController = SettingsWindowController(settings: settings, updates: updates, loginItem: loginItem,
                                                          networkPolicy: networkPolicy) { [weak self] shortcut in
                guard let self else { return MenuText.appUnavailable }
                if self.windowPreferences.snapshot.enabled,
                   !WindowControlConfiguration.isValidShortcut(shortcut) {
                    return L10n.string("shortcut.windowConflict", table: "WindowSettings", value: "This shortcut is already used for Window Controls.")
                }
                if self.windowPreferences.snapshot.enabled,
                   shortcut.keyCode == self.windowPreferences.snapshot.shortcut.keyCode,
                   shortcut.modifiers == self.windowPreferences.snapshot.shortcut.modifiers {
                    return L10n.string("shortcut.windowConflict", table: "WindowSettings", value: "This shortcut is already used for Window Controls.")
                }
                let status = self.hotKey.register(shortcut: shortcut)
                guard status == noErr else {
                    return L10n.format(MenuText.shortcutConflict, shortcut.localizedDisplayName, status)
                }
                self.launcher.model.shortcutError = nil
                return nil
            }
            settingsController?.onClose = { [weak self] in self?.finishSettings(.general) }
            settingsController?.onExportSettings = { [weak self] in self?.showBackup(mode: .export) }
            settingsController?.onImportSettings = { [weak self] in self?.showBackup(mode: .import) }
        }
        settingsController?.show()
    }

    private func showBackup(mode: BackupSettingsModel.Mode) {
        if backupController == nil {
            let coordinator = SettingsBackupCoordinator(
                settings: settings, aliases: appAliasPreferences, conversion: conversionPreferences,
                browsers: webSearchPreferences, gpt: gptPreferences, clipboard: clipboard,
                windows: windowPreferences,
                applyShortcuts: { [weak self] shortcut, windows in
                    guard let self else { return MenuText.appUnavailable }
                    if windows.enabled && !WindowControlConfiguration.isValidShortcut(shortcut) {
                        return L10n.string("shortcut.windowConflict", table: "WindowSettings",
                                           value: "This shortcut is already used for Window Controls.")
                    }
                    let status = HotKeyManager.replacePair(
                        launcher: self.hotKey, launcherShortcut: shortcut,
                        window: self.windowHotKey, windowShortcut: windows.enabled ? windows.shortcut : nil)
                    guard status == noErr else {
                        let names = windows.enabled
                            ? "\(shortcut.localizedDisplayName) / \(windows.shortcut.localizedDisplayName)"
                            : shortcut.localizedDisplayName
                        return L10n.format(MenuText.shortcutConflict, names, status)
                    }
                    self.launcher.model.shortcutError = nil
                    return nil
                }, onCredentialsChange: { [weak self] in self?.launcher.stopGPT() }
            )
            backupCoordinator = coordinator
            let service = BackupSettingsService(
                exportDocument: { try await coordinator.exportDocument() },
                readAPIKeyForExport: { try await coordinator.readAPIKeyForExport() },
                preview: { try await coordinator.preview($0) },
                apply: { try await coordinator.apply($0, sections: $1, restoreAPIKey: $2, applyRetention: $3) }
            )
            backupController = BackupSettingsController(model: BackupSettingsModel(service: service))
            backupController?.onClose = { [weak self] in
                guard let self, !self.isTerminating else { return }
                self.settingsController?.show()
            }
        }
        // The import preview is the only settings editor while a transaction is
        // in progress. Keep suspended source-window context for the return path.
        settingsController?.window?.orderOut(nil)
        webSearchSettingsController?.window?.orderOut(nil)
        gptSettingsController?.window?.orderOut(nil)
        conversionSettingsController?.window?.orderOut(nil)
        appAliasSettingsController?.window?.orderOut(nil)
        windowSettingsController?.hide()
        backupController?.show(mode: mode)
    }

    private func showWebSearchSettings() {
        prepareSettings(.webSearch)
        if webSearchSettingsController == nil {
            webSearchSettingsController = WebSearchSettingsController(preferences: webSearchPreferences)
            webSearchSettingsController?.onClose = { [weak self] in self?.finishSettings(.webSearch) }
        }
        webSearchSettingsController?.show()
    }

    private func showGPTSettings() {
        prepareSettings(.gpt)
        if gptSettingsController == nil {
            let controller = GPTSettingsController(preferences: gptPreferences, policy: networkPolicy)
            controller.onOpenGeneralSettings = { [weak self] in
                guard let self else { return }
                self.showSettings()
                self.returnToGPTSettings = true
            }
            controller.onCredentialsChange = { [weak self] in self?.launcher.stopGPT() }
            controller.onClose = { [weak self] in self?.finishSettings(.gpt) }
            gptSettingsController = controller
        }
        gptSettingsController?.show()
    }

    private func showConversionSettings() {
        prepareSettings(.conversion)
        if conversionSettingsController == nil {
            conversionSettingsController = ChineseConversionSettingsController(preferences: conversionPreferences)
            conversionSettingsController?.onClose = { [weak self] in self?.finishSettings(.conversion) }
        }
        conversionSettingsController?.show()
    }

    private func showAppAliasSettings(for application: IndexedApplication) {
        prepareSettings(.appAlias)
        appAliasSettingsController?.onClose = nil
        appAliasSettingsController?.close()
        appAliasSettingsController = AppAliasSettingsController(
            application: application, preferences: appAliasPreferences,
            conversionAliases: { [weak self] in self?.conversionPreferences.aliases ?? .defaults }
        )
        appAliasSettingsController?.onClose = { [weak self] in self?.finishSettings(.appAlias) }
        appAliasSettingsController?.show()
    }

    private func prepareSettings(_ page: SettingsPage) {
        windowMode.suspendForSettings()
        _ = launcher.suspendForSettings()
        settingsOwner = page
        returnToGPTSettings = false
    }

    private func finishSettings(_ page: SettingsPage) {
        guard !isTerminating, settingsOwner == page else { return }
        if page == .general, returnToGPTSettings, gptSettingsController?.window?.isVisible == true {
            returnToGPTSettings = false
            settingsOwner = .gpt
            gptSettingsController?.show()
            return
        }
        settingsOwner = nil
        returnToGPTSettings = false
        if windowMode.suspendedForSettings { windowMode.resumeAfterSettings() }
        else { launcher.resumeAfterSettings() }
    }

    private func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: MenuText.settings, action: #selector(showSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func updateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: MenuText.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        item.target = self
        item.isEnabled = false
        updateMenuItems.append(item)
        return item
    }

    private func aboutMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: MenuText.about, action: #selector(showAbout), keyEquivalent: "")
        item.target = self
        return item
    }

    private static func menuBarImage(named name: String) -> NSImage {
        let image = NSImage(named: NSImage.Name(name))
            ?? NSImage(systemSymbolName: "command.square", accessibilityDescription: "Cue")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = menuBarIcon
        // Load both tiny template assets once, before any user interaction.
        _ = menuBarUpdateIcon
        statusItem.button?.setAccessibilityLabel("Cue")
        let menu = NSMenu()
        let show = NSMenuItem(title: MenuText.show, action: #selector(showCue), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(settingsMenuItem())
        let windows = NSMenuItem(title: MenuText.windowSettings, action: #selector(showWindowSettings), keyEquivalent: "")
        windows.target = self
        menu.addItem(windows)
        menu.addItem(updateMenuItem())
        menu.addItem(.separator())
        menu.addItem(aboutMenuItem())
        let quit = NSMenuItem(title: MenuText.quit, action: #selector(quitCue), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func configureEditingMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(aboutMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(settingsMenuItem())
        appMenu.addItem(updateMenuItem())
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: MenuText.quit, action: #selector(quitCue), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editMenu = NSMenu(title: MenuText.edit)
        for (title, action, key) in [
            (MenuText.undo, "undo:", "z"), (MenuText.cut, "cut:", "x"),
            (MenuText.copy, "copy:", "c"), (MenuText.paste, "paste:", "v"), (MenuText.selectAll, "selectAll:", "a")
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
