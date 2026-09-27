import Combine
import CueCore
import Foundation

/// Exercise the real observable settings store without opening the app or touching its preferences.
@main
struct CheckSettings {
    @MainActor
    static func main() {
        let domain = "com.cue.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        // Inherited language preferences must not be mistaken for a per-app override.
        defaults.register(defaults: ["AppleLanguages": ["zh-Hant-US"]])
        let inheritedLanguages = defaults.stringArray(forKey: "AppleLanguages")
        let settings = CueSettings(defaults: defaults, domainName: domain)
        precondition(settings.language == .system)
        precondition(!settings.languageChangeRequiresRestart)
        var publications = 0
        let subscription = settings.$preferences.sink { _ in
            publications += 1
            // Catch recursive @Published didSet writes before overflowing the stack.
            precondition(publications <= 10, "Recursive preference publication")
        }
        precondition(publications == 1)

        settings.preferences.maxResults = 10
        settings.preferences.shortcut = LauncherShortcut(
            keyCode: 40, modifiers: [.control, .option], key: "K"
        )
        settings.preferences.display = .main
        settings.preferences.dismissOnFocusLoss = false
        precondition(publications == 5, "Each valid edit must publish exactly once")
        precondition(settings.preferences.maxResults == 10)
        precondition(settings.preferences.shortcut.displayName == "⌃⌥K")
        precondition(defaults.data(forKey: "launcherPreferences") != nil)

        let reloaded = CueSettings(defaults: UserDefaults(suiteName: domain)!, domainName: domain)
        precondition(reloaded.preferences == settings.preferences, "Edited preferences must persist")

        settings.preferences.maxResults = -1
        precondition(settings.preferences.maxResults == 20)
        precondition(publications == 7, "An invalid edit must publish one bounded correction")
        let sanitizedReload = CueSettings(defaults: UserDefaults(suiteName: domain)!, domainName: domain)
        precondition(sanitizedReload.preferences == settings.preferences, "Persist the corrected value")

        let savedPreferences = defaults.data(forKey: "launcherPreferences")
        settings.language = .traditionalChinese
        precondition(settings.languageChangeRequiresRestart)
        precondition(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == ["zh-Hant"])
        let chineseReload = CueSettings(defaults: UserDefaults(suiteName: domain)!, domainName: domain)
        precondition(chineseReload.language == .traditionalChinese)
        precondition(!chineseReload.languageChangeRequiresRestart)
        settings.language = .english
        precondition(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == ["en"])
        precondition(CueSettings(defaults: defaults, domainName: domain).language == .english)
        settings.language = .system
        precondition(!settings.languageChangeRequiresRestart)
        precondition(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil,
                     "Follow System must remove only Cue's language override")
        precondition(defaults.stringArray(forKey: "AppleLanguages") == inheritedLanguages,
                     "Inherited language preference must remain intact")
        precondition(defaults.data(forKey: "launcherPreferences") == savedPreferences,
                     "Changing languages must preserve shortcuts and other settings")
        precondition(publications == 7, "Language changes must not publish launcher preferences")
        for identifier in ["zh-Hant", "zh-Hant-US", "zh-TW", "zh_HK"] {
            precondition(AppLanguage(override: identifier) == .traditionalChinese, identifier)
        }
        precondition(AppLanguage(override: "en-US") == .english)
        precondition(AppLanguage(override: "zh-Hans") == .system)
        precondition(AppLanguage(override: nil) == .system)

        defaults.removePersistentDomain(forName: domain)
        precondition(defaults.persistentDomain(forName: domain)?.isEmpty ?? true)
        withExtendedLifetime(subscription) {}
        print("Settings persistence passed: bounded publication, edits, reload, sanitization, language overrides, system fallback, and isolated cleanup.")
    }
}
