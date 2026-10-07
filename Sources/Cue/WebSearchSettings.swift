import AppKit
import Combine
import CoreFoundation
import CueCore
import SwiftUI

enum WebSearchSettingsText {
    static let title = L10n.string("settings.title", table: "WebSearch", value: "Google Search Settings")
    static let enabled = L10n.string("settings.enabled", table: "WebSearch", value: "Enable Google search")
    static let help = L10n.string("settings.help", table: "WebSearch", value: "Searches open in your browser, even when Cue’s network access is off. Nothing is sent until you run a search.")
    static let browsers = L10n.string("browsers.heading", table: "WebSearch", value: "Browser Options")
    static let systemDefault = L10n.string("browsers.systemDefault", table: "WebSearch", value: "System Default")
    static let systemHelp = L10n.string("browsers.systemHelp", table: "WebSearch", value: "Always available; follows your macOS default browser.")
    static let browserHelp = L10n.string("browsers.help", table: "WebSearch", value: "Add up to eight browser options for this Mac. Only browsers you add appear in Cue; this does not change your macOS default.")
    static let empty = L10n.string("browsers.empty", table: "WebSearch", value: "No additional browsers. Add only the ones you want to use.")
    static let unavailable = L10n.string("browsers.unavailable", table: "WebSearch", value: "Unavailable on this Mac")
    static let unavailableHelp = L10n.string("browsers.unavailableHelp", table: "WebSearch", value: "This browser is not currently available. Install it again or remove this option.")
    static let checking = L10n.string("browsers.checking", table: "WebSearch", value: "Checking installed browsers…")
    static let addBrowser = L10n.string("browsers.add", table: "WebSearch", value: "Add Browser…")
    static let remove = L10n.string("browsers.remove", table: "WebSearch", value: "Remove")
    static let removeAccessibility = L10n.string("browsers.removeAccessibility", table: "WebSearch", value: "Remove %@")
    static let browser = L10n.string("picker.browser", table: "WebSearch", value: "Browser")
    static let chooseBrowser = L10n.string("picker.choose", table: "WebSearch", value: "Choose a browser")
    static let pickerHelp = L10n.string("picker.help", table: "WebSearch", value: "Choose an installed browser to add as a Google search option.")
    static let noCandidates = L10n.string("picker.empty", table: "WebSearch", value: "No other installed browsers are available to add.")
    static let add = L10n.string("picker.add", table: "WebSearch", value: "Add")
    static let cancel = L10n.string("settings.cancel", table: "WebSearch", value: "Cancel")
    static let done = L10n.string("settings.done", table: "WebSearch", value: "Done")
    static let invalidBrowser = L10n.string("error.invalidBrowser", table: "WebSearch", value: "This browser’s information is invalid. Please choose another browser.")
    static let browserLimit = L10n.string("error.browserLimit", table: "WebSearch", value: "You can add up to eight browsers. Remove one before adding another.")
}

/// Feature-local choices: manual browser handoffs are independent of Cue networking.
@MainActor
final class WebSearchPreferences: ObservableObject {
    nonisolated static let enabledKey = "webSearch.enabled"
    nonisolated static let browsersKey = "webSearch.browsers"
    nonisolated static let maximumBrowsers = WebSearchBrowser.maximumAddedBrowsers

    enum ValidationError: Error, Equatable, Sendable {
        case invalidBrowser
        case browserLimit
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var browsers: [WebSearchBrowser]
    var onChange: (() -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let value = defaults.object(forKey: Self.enabledKey) as? NSNumber,
           CFGetTypeID(value) == CFBooleanGetTypeID() {
            isEnabled = value.boolValue
        } else {
            isEnabled = true
        }
        var loaded: [WebSearchBrowser] = []
        var identifiers = Set<String>()
        for value in defaults.array(forKey: Self.browsersKey) ?? [] {
            guard let fields = value as? [String: String],
                  let identifier = fields["bundleIdentifier"], let name = fields["name"],
                  let browser = try? Self.validated(WebSearchBrowser(bundleIdentifier: identifier, name: name)),
                  identifiers.insert(browser.id.lowercased()).inserted else { continue }
            loaded.append(browser)
            if loaded.count == Self.maximumBrowsers { break }
        }
        browsers = loaded
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        onChange?()
    }

    func add(_ browser: WebSearchBrowser) throws {
        let browser = try Self.validated(browser)
        guard !browsers.contains(where: { $0.id.lowercased() == browser.id.lowercased() }) else { return }
        guard browsers.count < Self.maximumBrowsers else { throw ValidationError.browserLimit }
        browsers.append(browser)
        persistBrowsers()
        onChange?()
    }

    func remove(id: String) {
        let identifier = id.lowercased()
        guard browsers.contains(where: { $0.id.lowercased() == identifier }) else { return }
        browsers.removeAll { $0.id.lowercased() == identifier }
        persistBrowsers()
        onChange?()
    }

    /// Replace only explicit browser choices; the local feature switch is untouched.
    func replaceForBackup(_ values: [WebSearchBrowser]) throws {
        guard values.count <= Self.maximumBrowsers else { throw ValidationError.browserLimit }
        let validated = try values.map(Self.validated)
        guard Set(validated.map { $0.id.lowercased() }).count == validated.count else {
            throw ValidationError.invalidBrowser
        }
        guard validated != browsers else { return }
        browsers = validated
        persistBrowsers()
        onChange?()
    }

    private func persistBrowsers() {
        defaults.set(browsers.map { ["bundleIdentifier": $0.bundleIdentifier, "name": $0.name] },
                     forKey: Self.browsersKey)
    }

    nonisolated static func validated(_ browser: WebSearchBrowser) throws -> WebSearchBrowser {
        let identifier = browser.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = browser.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, identifier.utf8.count <= 255,
              identifier.unicodeScalars.allSatisfy({
                  $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-")
              }),
              !name.isEmpty, name.utf8.count <= 256,
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
              })
        else { throw ValidationError.invalidBrowser }
        return WebSearchBrowser(bundleIdentifier: identifier, name: name)
    }
}

/// Launch Services and bundle reads occur only while this feature's settings are open.
@MainActor
private final class WebSearchBrowserCatalog: ObservableObject {
    @Published private(set) var candidates: [WebSearchBrowser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    private var refreshTask: Task<Void, Never>?
    private var revision = 0

    func refresh() {
        guard !isLoading else { return }
        revision += 1
        let currentRevision = revision
        isLoading = true
        refreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.discover() }.value
            guard !Task.isCancelled, let self, self.revision == currentRevision else { return }
            self.candidates = result
            self.hasLoaded = true
            self.isLoading = false
            self.refreshTask = nil
        }
    }

    func cancelRefresh() {
        revision += 1
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
    }

    nonisolated private static func discover() -> [WebSearchBrowser] {
        guard let searchURL = URL(string: "https://www.google.com/") else { return [] }
        var identifiers = Set<String>()
        var browsers: [WebSearchBrowser] = []
        for url in NSWorkspace.shared.urlsForApplications(toOpen: searchURL) {
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path),
                  let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            guard let browser = try? WebSearchPreferences.validated(
                WebSearchBrowser(bundleIdentifier: identifier, name: name)
            ), identifiers.insert(browser.id.lowercased()).inserted else { continue }
            browsers.append(browser)
        }
        return browsers.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

@MainActor
final class WebSearchSettingsController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let catalog = WebSearchBrowserCatalog()

    init(preferences: WebSearchPreferences) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = WebSearchSettingsText.title
        window.contentMinSize = NSSize(width: 540, height: 500)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WebSearchSettingsView(
            preferences: preferences, catalog: catalog, close: { [weak self] in self?.window?.performClose(nil) }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func show() {
        catalog.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        catalog.cancelRefresh()
        window?.makeFirstResponder(nil)
        onClose?()
    }
}

private struct WebSearchSettingsView: View {
    @ObservedObject var preferences: WebSearchPreferences
    @ObservedObject var catalog: WebSearchBrowserCatalog
    let close: () -> Void
    @ViewState private var isAddingBrowser = false

    private var availableIDs: Set<String> { Set(catalog.candidates.map { $0.id.lowercased() }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(WebSearchSettingsText.enabled, isOn: Binding(
                get: { preferences.isEnabled }, set: { preferences.setEnabled($0) }
            ))
            Text(WebSearchSettingsText.help)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(WebSearchSettingsText.browsers).font(.headline)
                Spacer()
                Button(WebSearchSettingsText.addBrowser) {
                    catalog.refresh()
                    isAddingBrowser = true
                }
                .disabled(preferences.browsers.count >= WebSearchPreferences.maximumBrowsers)
                .help(preferences.browsers.count >= WebSearchPreferences.maximumBrowsers
                      ? WebSearchSettingsText.browserLimit : WebSearchSettingsText.pickerHelp)
            }
            HStack(spacing: 10) {
                Image(systemName: "globe").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(WebSearchSettingsText.systemDefault)
                    Text(WebSearchSettingsText.systemHelp).font(.caption).foregroundStyle(.secondary)
                }
            }
            GroupBox {
                if preferences.browsers.isEmpty {
                    Text(WebSearchSettingsText.empty).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .multilineTextAlignment(.center).padding(12)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(preferences.browsers) { browser in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(browser.name).lineLimit(1)
                                        if catalog.hasLoaded && !availableIDs.contains(browser.id.lowercased()) {
                                            Text(WebSearchSettingsText.unavailable).font(.caption)
                                                .foregroundStyle(.secondary).help(WebSearchSettingsText.unavailableHelp)
                                        }
                                    }
                                    Spacer()
                                    Button(WebSearchSettingsText.remove) { preferences.remove(id: browser.id) }
                                        .accessibilityLabel(L10n.format(WebSearchSettingsText.removeAccessibility, browser.name))
                                }.padding(.vertical, 8).padding(.horizontal, 6)
                                if browser.id != preferences.browsers.last?.id { Divider() }
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(WebSearchSettingsText.browserHelp)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if catalog.isLoading {
                    ProgressView().controlSize(.small)
                    Text(WebSearchSettingsText.checking).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(WebSearchSettingsText.done, action: close).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 500)
        .sheet(isPresented: $isAddingBrowser) {
            WebSearchBrowserPicker(preferences: preferences, catalog: catalog, close: { isAddingBrowser = false })
        }
    }
}

private struct WebSearchBrowserPicker: View {
    @ObservedObject var preferences: WebSearchPreferences
    @ObservedObject var catalog: WebSearchBrowserCatalog
    let close: () -> Void
    @ViewState private var selectedID = ""
    @ViewState private var error: String?

    private var candidates: [WebSearchBrowser] {
        let added = Set(preferences.browsers.map { $0.id.lowercased() })
        return catalog.candidates.filter { !added.contains($0.id.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(WebSearchSettingsText.addBrowser).font(.headline)
            Text(WebSearchSettingsText.pickerHelp).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if catalog.isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(WebSearchSettingsText.checking)
                }
            } else if candidates.isEmpty {
                Text(WebSearchSettingsText.noCandidates).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(WebSearchSettingsText.browser, selection: $selectedID) {
                    Text(WebSearchSettingsText.chooseBrowser).tag("")
                    ForEach(candidates) { browser in Text(browser.name).tag(browser.id) }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(WebSearchSettingsText.cancel, action: close).keyboardShortcut(.cancelAction)
                Button(WebSearchSettingsText.add) {
                    guard let browser = candidates.first(where: { $0.id == selectedID }) else { return }
                    do {
                        try preferences.add(browser)
                        close()
                    } catch {
                        self.error = (error as? WebSearchPreferences.ValidationError) == .browserLimit
                            ? WebSearchSettingsText.browserLimit : WebSearchSettingsText.invalidBrowser
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(catalog.isLoading || !candidates.contains(where: { $0.id == selectedID }))
            }
        }.padding(20).frame(width: 460, height: 240)
    }
}
