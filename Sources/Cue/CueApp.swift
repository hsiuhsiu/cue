import AppKit
import Combine
import CueCore

private enum MenuText {
    static let settings = L10n.string("menu.settings", table: "Menu", value: "Settings…")
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
    private var statusItem: NSStatusItem!
    private let settings = CueSettings()
    private let networkPolicy = NetworkPolicy()
    private var settingsController: SettingsWindowController?
    private let webSearchPreferences = WebSearchPreferences()
    private var webSearchSettingsController: WebSearchSettingsController?
    private let gptPreferences = GPTPreferences()
    private var gptSettingsController: GPTSettingsController?
    private var gptNetworkSubscription: AnyCancellable?
    private let conversionPreferences = ChineseConversionPreferences()
    private var conversionSettingsController: ChineseConversionSettingsController?
    private let appAliasPreferences = AppAliasPreferences()
    private var appAliasSettingsController: AppAliasSettingsController?
    private lazy var loginItem = LoginItemController()
    private var preferencesSubscription: AnyCancellable?
    private var updates: UpdateController!
    private var updateSubscription: AnyCancellable?
    private var updateMenuItems: [NSMenuItem] = []
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
        launcher = LauncherPanelController(clipboard: clipboard, model: model, gpt: gpt,
                                           webSearchPreferences: webSearchPreferences)
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
            if self.settingsController?.finishRecordingCurrentShortcut() == true { return }
            self.launcher.toggle()
        }
        let status = hotKey.register(shortcut: settings.preferences.shortcut)
        if status != noErr {
            launcher.model.shortcutError = L10n.format(
                MenuText.shortcutUnavailable, settings.preferences.shortcut.localizedDisplayName, status
            )
            launcher.show()
        }
        preferencesSubscription = settings.$preferences.sink { [weak self] preferences in
            self?.launcher.apply(preferences)
            self?.statusItem.button?.toolTip = "Cue — \(preferences.shortcut.localizedDisplayName)"
        }
        Task { await launcher.model.loadApplications() }
        launcher.model.startUsageTracking()
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
        clipboard.stop()
        Task {
            async let clipboardFinished: Void = clipboard.prepareForTermination()
            async let usageFinished: Void = launcher.model.prepareForTermination()
            async let conversionFinished: Void = launcher.finishPendingTextConversion()
            _ = await (clipboardFinished, usageFinished, conversionFinished)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
        clipboard?.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        launcher?.focusIfPresented()
        // Reflect changes made in macOS Login Items when returning to Settings.
        // No service lookup is performed for ordinary launcher invocation.
        settingsController?.refreshLoginItemStatus()
        conversionSettingsController?.refreshAccess()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsController?.window?.isVisible != true,
           conversionSettingsController?.window?.isVisible != true,
           appAliasSettingsController?.window?.isVisible != true,
           gptSettingsController?.window?.isVisible != true,
           webSearchSettingsController?.window?.isVisible != true { launcher.show() }
        return false
    }

    @objc private func showCue() { launcher.show() }
    @objc private func quitCue() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updates.checkForUpdates() }

    @objc private func showAbout() {
        launcher.dismiss(returnFocus: false)
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            return networkPolicy.allowsNetwork && (updates?.canCheckForUpdates ?? false)
        }
        return true
    }

    @objc private func showSettings() {
        launcher.dismiss(returnFocus: false)
        if settingsController == nil {
            settingsController = SettingsWindowController(settings: settings, updates: updates, loginItem: loginItem,
                                                          networkPolicy: networkPolicy) { [weak self] shortcut in
                guard let self else { return MenuText.appUnavailable }
                let status = self.hotKey.register(shortcut: shortcut)
                guard status == noErr else {
                    return L10n.format(MenuText.shortcutConflict, shortcut.localizedDisplayName, status)
                }
                self.launcher.model.shortcutError = nil
                return nil
            }
        }
        settingsController?.show()
    }

    private func showWebSearchSettings() {
        launcher.dismiss(returnFocus: false)
        if webSearchSettingsController == nil {
            webSearchSettingsController = WebSearchSettingsController(preferences: webSearchPreferences)
        }
        webSearchSettingsController?.show()
    }

    private func showGPTSettings() {
        launcher.dismiss(returnFocus: false)
        if gptSettingsController == nil {
            let controller = GPTSettingsController(preferences: gptPreferences, policy: networkPolicy)
            controller.onOpenGeneralSettings = { [weak self] in self?.showSettings() }
            controller.onCredentialsChange = { [weak self] in self?.launcher.stopGPT() }
            gptSettingsController = controller
        }
        gptSettingsController?.show()
    }

    private func showConversionSettings() {
        launcher.dismiss(returnFocus: false)
        if conversionSettingsController == nil {
            conversionSettingsController = ChineseConversionSettingsController(preferences: conversionPreferences)
        }
        conversionSettingsController?.show()
    }

    private func showAppAliasSettings(for application: IndexedApplication) {
        launcher.dismiss(returnFocus: false)
        appAliasSettingsController?.close()
        appAliasSettingsController = AppAliasSettingsController(
            application: application, preferences: appAliasPreferences,
            conversionAliases: { [weak self] in self?.conversionPreferences.aliases ?? .defaults }
        )
        appAliasSettingsController?.show()
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
