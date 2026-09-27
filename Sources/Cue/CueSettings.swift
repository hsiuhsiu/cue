import Combine
import CueCore
import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"

    init(override identifier: String?) {
        guard let identifier else { self = .system; return }
        let language = Locale.Language(identifier: identifier)
        if language.languageCode?.identifier == "en" {
            self = .english
        } else if language.languageCode?.identifier == "zh", language.script?.identifier == "Hant" {
            self = .traditionalChinese
        } else {
            self = .system
        }
    }
}

@MainActor
final class CueSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            // Use macOS's per-app preference so AppKit and Sparkle share Cue's language.
            // Bundle localization is cached by the OS; apply the change on the next launch.
            if language == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([language.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    var languageChangeRequiresRestart: Bool { language != languageAtLaunch }

    @Published var preferences: LauncherPreferences {
        didSet {
            let sanitized = preferences.sanitized()
            if sanitized != preferences {
                preferences = sanitized
                return
            }
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    private static let storageKey = "launcherPreferences"
    private let defaults: UserDefaults
    private let languageAtLaunch: AppLanguage

    init(defaults: UserDefaults = .standard,
         domainName: String = Bundle.main.bundleIdentifier ?? "com.yyhsiu.cue") {
        self.defaults = defaults
        // Read only this app's override, not the inherited global AppleLanguages value.
        let languages = defaults.persistentDomain(forName: domainName)?["AppleLanguages"] as? [String]
        let initialLanguage = AppLanguage(override: languages?.first)
        language = initialLanguage
        languageAtLaunch = initialLanguage
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(LauncherPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = LauncherPreferences()
        }
    }
}
