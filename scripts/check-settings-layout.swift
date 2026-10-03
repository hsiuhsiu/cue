import AppKit
import Combine
import CueCore
import SwiftUI

@MainActor private protocol SettingsSnapshotProvider {
    func settingsSnapshot() -> NSImage?
}

extension NSHostingView: SettingsSnapshotProvider {
    fileprivate func settingsSnapshot() -> NSImage? {
        // A hidden AppKit window has no compositor surface. Render the same
        // SwiftUI tree directly, without ordering the window on any display.
        let renderer = ImageRenderer(content: rootView.background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: bounds.width, height: bounds.height)
        return renderer.nsImage
    }
}

private struct FakeLoginService: LoginItemService {
    let reportedStatus: LoginItemStatus
    let fails: Bool
    func status() async -> LoginItemStatus { reportedStatus }
    func setEnabled(_ enabled: Bool) async throws {
        if fails { throw NSError(domain: "CueSettingsTest", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Synthetic registration failure; no system settings were changed."]) }
    }
}

@MainActor private final class FakeUpdateEngine: UpdateEngine {
    var canCheckForUpdates = true
    var sessionInProgress = false
    let fails: Bool
    init(fails: Bool) { self.fails = fails }
    func start() throws {
        if fails { throw NSError(domain: "CueSettingsTest", code: 2,
                                 userInfo: [NSLocalizedDescriptionKey: "Synthetic updater initialization failure."]) }
    }
    func checkForUpdates(userInitiated: Bool) { fatalError("Layout checks must not request updates") }
    func cancelNetworkActivity() {}
}

/// Offscreen native layout only. The process cannot activate, windows are never
/// ordered front, and every service uses isolated defaults or synthetic state.
@main struct CheckSettingsLayout {
    @MainActor private static var checks = 0
    @MainActor private static var rendered: [NSWindowController] = []

    @MainActor private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor private static func render(_ controller: NSWindowController, name: String,
                                          normalGeneral: Bool = false) throws {
        guard let window = controller.window, let content = window.contentView else {
            check(false, "\(name): native content exists"); return
        }
        rendered.append(controller)
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        content.layoutSubtreeIfNeeded()
        let size = window.contentRect(forFrameRect: window.frame).size
        check(content.frame.width <= size.width && content.frame.height <= size.height,
              "\(name): content stays inside the window")
        check(content.fittingSize.width.isFinite && content.fittingSize.height.isFinite,
              "\(name): intrinsic size is bounded")
        check(!window.isVisible && !NSApp.isActive, "\(name): layout never steals focus or opens a window")
        if normalGeneral {
            let scrolls = descendants(content).compactMap { $0 as? NSScrollView }
            check(!scrolls.isEmpty, "\(name): the settings document is present")
            for scroll in scrolls {
                check((scroll.documentView?.frame.height ?? 0) <= scroll.contentSize.height + 1,
                      "\(name): ordinary settings, including updates, fit without scrolling")
            }
        }
        let snapshot: NSImage?
        if let general = content as? NSHostingView<CueSettingsView> {
            // ImageRenderer cannot render a native ScrollView. Render its exact
            // shared document instead; frame assertions above check its viewport.
            let renderer = ImageRenderer(content: general.rootView.settingsGroups
                .frame(width: 500).padding(20).background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            snapshot = renderer.nsImage
            if let image = snapshot {
                check(image.size.height > 350, "\(name): renderer includes the controls, not only section headings")
            } else {
                check(false, "\(name): shared settings document renders successfully")
            }
            if normalGeneral, let image = snapshot {
                let scroll = descendants(content).compactMap { $0 as? NSScrollView }.first!
                check(image.size.height - 40 <= scroll.contentSize.height + 1,
                      "\(name): rendered controls and help text fit in the actual scroll viewport")
            }
        } else {
            snapshot = (content as? any SettingsSnapshotProvider)?.settingsSnapshot()
        }
        if let directory = ProcessInfo.processInfo.environment["CUE_SETTINGS_PREVIEW_DIRECTORY"],
           let data = snapshot?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
            try bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["CUE_SETTINGS_DARK"] == "1" ? .darkAqua : .aqua)
        let domain = "com.yyhsiu.cue.tests.settings-layout.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = CueSettings(defaults: defaults, domainName: domain)
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let updates = UpdateController(networkPolicy: policy, defaults: defaults,
                                       makeEngine: { _ in FakeUpdateEngine(fails: false) },
                                       schedule: { _, _ in AnyCancellable {} })
        let login = LoginItemController(service: FakeLoginService(reportedStatus: .notRegistered, fails: false))
        await login.refresh()
        let general = SettingsWindowController(settings: settings, updates: updates, loginItem: login,
                                               networkPolicy: policy, applyShortcut: { _ in nil })
        var generalClosed = 0
        general.onClose = { generalClosed += 1 }
        try render(general, name: "general-offline", normalGeneral: true)
        policy.setAllowsNetwork(true)
        updates.start()
        try render(general, name: "general-online", normalGeneral: true)
        let badLogin = LoginItemController(service: FakeLoginService(reportedStatus: .notFound, fails: true))
        await badLogin.refresh()
        await badLogin.setEnabled(true)
        let badUpdates = UpdateController(networkPolicy: policy, defaults: defaults,
                                          makeEngine: { _ in FakeUpdateEngine(fails: true) },
                                          schedule: { _, _ in AnyCancellable {} })
        badUpdates.start()
        let errors = SettingsWindowController(settings: settings, updates: badUpdates, loginItem: badLogin,
                                              networkPolicy: policy, applyShortcut: { _ in "Synthetic shortcut conflict" })
        try render(errors, name: "general-errors")
        let fakeKeys = GPTKeyStore(contains: { false }, save: { _ in }, delete: {})
        let gptPreferences = GPTPreferences(defaults: defaults)
        let gpt = GPTSettingsController(preferences: gptPreferences, policy: policy, keyStore: fakeKeys)
        var gptClosed = 0
        gpt.onClose = { gptClosed += 1 }
        gpt.prepareContent()
        try render(gpt, name: "gpt-online")
        policy.setAllowsNetwork(false)
        try render(gpt, name: "gpt-offline")
        let credentials = GPTCredentialModel(store: fakeKeys)
        credentials.draftKey = "invalid"
        await credentials.save()
        let keyErrorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
        keyErrorWindow.isReleasedWhenClosed = false
        keyErrorWindow.contentView = NSHostingView(rootView: GPTSettingsView(
            preferences: gptPreferences, policy: policy, credentials: credentials,
            openGeneralSettings: {}, close: {}
        ))
        try render(NSWindowController(window: keyErrorWindow), name: "gpt-key-error")
        let browsers = WebSearchPreferences(defaults: defaults)
        let web = WebSearchSettingsController(preferences: browsers)
        var webClosed = 0
        web.onClose = { webClosed += 1 }
        try render(web, name: "web-empty")
        for number in 1...8 {
            try browsers.add(WebSearchBrowser(bundleIdentifier: "com.example.browser\(number)",
                                              name: "Example Browser \(number) — Local Test"))
        }
        try render(web, name: "web-eight-browsers")
        let conversionPreferences = ChineseConversionPreferences(defaults: defaults)
        let conversion = ChineseConversionSettingsController(preferences: conversionPreferences)
        var conversionClosed = 0
        conversion.onClose = { conversionClosed += 1 }
        conversion.prepareContent()
        try render(conversion, name: "conversion")
        let aliasPreferences = AppAliasPreferences(defaults: defaults)
        let app = IndexedApplication(name: "Example Application", url: URL(fileURLWithPath: "/Test/Example.app"))
        let alias = AppAliasSettingsController(application: app, preferences: aliasPreferences,
                                               conversionAliases: { .defaults })
        var aliasClosed = 0
        alias.onClose = { aliasClosed += 1 }
        alias.prepareContent()
        try render(alias, name: "app-alias")
        for controller in [general, gpt, web, conversion, alias] as [NSWindowController] {
            controller.window?.performClose(nil)
        }
        check([generalClosed, gptClosed, webClosed, conversionClosed, aliasClosed] == [1, 1, 1, 1, 1],
              "All settings close through exactly one return callback")
        check(!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible },
              "All cases finish without interfering with other apps")
        print("Settings layout passed: \(checks) offscreen layout, error-state and close-callback checks.")
    }
}
