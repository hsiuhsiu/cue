import Combine
import CueCore
import Foundation

@MainActor
final class CueSettings: ObservableObject {
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(LauncherPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = LauncherPreferences()
        }
    }
}
