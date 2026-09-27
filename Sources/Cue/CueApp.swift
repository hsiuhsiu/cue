import AppKit
import Combine
import CueCore

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
    private var hotKey: HotKeyManager!
    private var statusItem: NSStatusItem!
    private let settings = CueSettings()
    private var settingsController: SettingsWindowController?
    private var preferencesSubscription: AnyCancellable?
    private var updates: UpdateController!
    private var updateSubscription: AnyCancellable?
    private var updateMenuItems: [NSMenuItem] = []
    private lazy var menuBarIcon = Self.menuBarImage(named: "MenuBarIconTemplate")
    private lazy var menuBarUpdateIcon = Self.menuBarImage(named: "MenuBarIconUpdateTemplate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launcher = LauncherPanelController()
        launcher.onSettings = { [weak self] in self?.showSettings() }
        configureMenuBar()
        configureEditingMenu()
        hotKey = HotKeyManager { [weak self] in
            guard let self else { return }
            if self.settingsController?.finishRecordingCurrentShortcut() == true { return }
            self.launcher.toggle()
        }
        let status = hotKey.register(shortcut: settings.preferences.shortcut)
        if status != noErr {
            launcher.model.shortcutError = "\(settings.preferences.shortcut.displayName) is unavailable (\(status)). Change it in Settings."
            launcher.show()
        }
        preferencesSubscription = settings.$preferences.sink { [weak self] preferences in
            self?.launcher.apply(preferences)
            self?.statusItem.button?.toolTip = "Cue — \(preferences.shortcut.displayName)"
        }
        Task { await launcher.model.loadApplications() }
        // Construct the launcher and register its hotkey before starting update work.
        updates = UpdateController()
        updates.onPresentUpdate = { [weak self] in
            self?.launcher.dismiss()
            NSApp.activate()
        }
        updateSubscription = updates.$availableVersion.combineLatest(updates.$canCheckForUpdates)
            .sink { [weak self] version, canCheck in
                guard let self else { return }
                self.updateMenuItems.forEach {
                    $0.title = version.map { "Update Available (\($0))…" } ?? "Check for Updates…"
                    $0.isEnabled = canCheck
                }
                self.statusItem.button?.image = version == nil ? self.menuBarIcon : self.menuBarUpdateIcon
                self.statusItem.button?.setAccessibilityLabel(version == nil ? "Cue" : "Cue — update available")
            }
        Task { @MainActor [weak self] in self?.updates.start() }
    }

    func applicationWillTerminate(_ notification: Notification) { hotKey?.unregister() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsController?.window?.isVisible != true { launcher.show() }
        return false
    }

    @objc private func showCue() { launcher.show() }
    @objc private func quitCue() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updates.checkForUpdates() }

    @objc private func showAbout() {
        launcher.dismiss()
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            return updates?.canCheckForUpdates ?? false
        }
        return true
    }

    @objc private func showSettings() {
        launcher.dismiss()
        if settingsController == nil {
            settingsController = SettingsWindowController(settings: settings, updates: updates) { [weak self] shortcut in
                guard let self else { return "Cue is unavailable." }
                let status = self.hotKey.register(shortcut: shortcut)
                guard status == noErr else {
                    return "\(shortcut.displayName) is unavailable (\(status)). Try another shortcut; your previous shortcut is unchanged."
                }
                self.launcher.model.shortcutError = nil
                return nil
            }
        }
        settingsController?.show()
    }

    private func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func updateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        item.target = self
        item.isEnabled = false
        updateMenuItems.append(item)
        return item
    }

    private func aboutMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "About Cue", action: #selector(showAbout), keyEquivalent: "")
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
        let show = NSMenuItem(title: "Show Cue", action: #selector(showCue), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(settingsMenuItem())
        menu.addItem(updateMenuItem())
        menu.addItem(.separator())
        menu.addItem(aboutMenuItem())
        let quit = NSMenuItem(title: "Quit Cue", action: #selector(quitCue), keyEquivalent: "q")
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
        let quit = NSMenuItem(title: "Quit Cue", action: #selector(quitCue), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
