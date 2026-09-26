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
        let settings = CueSettings(defaults: defaults)
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

        let reloaded = CueSettings(defaults: UserDefaults(suiteName: domain)!)
        precondition(reloaded.preferences == settings.preferences, "Edited preferences must persist")

        settings.preferences.maxResults = -1
        precondition(settings.preferences.maxResults == 20)
        precondition(publications == 7, "An invalid edit must publish one bounded correction")
        let sanitizedReload = CueSettings(defaults: UserDefaults(suiteName: domain)!)
        precondition(sanitizedReload.preferences == settings.preferences, "Persist the corrected value")

        defaults.removePersistentDomain(forName: domain)
        precondition(defaults.persistentDomain(forName: domain)?.isEmpty ?? true)
        withExtendedLifetime(subscription) {}
        print("Settings persistence passed: bounded publication, edits, reload, sanitization, and isolated cleanup.")
    }
}
