import Combine
import CoreFoundation
import Foundation

enum NetworkAccessError: Error {
    case disabled
}

/// The single runtime permission for Cue-owned networking. Keep it out of search state.
@MainActor
final class NetworkPolicy: @preconcurrency ObservableObject {
    static let preferenceKey = "networkAccessAllowed"
    static let defaultInfoKey = "CueNetworkAccessAllowedByDefault"

    let objectWillChange = ObservableObjectPublisher()
    /// Emitted after the authoritative value changes, so observers can safely recheck it.
    let changes = PassthroughSubject<Bool, Never>()
    private(set) var allowsNetwork: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, defaultAllowsNetwork: Bool? = nil) {
        self.defaults = defaults
        if let saved = defaults.object(forKey: Self.preferenceKey) {
            allowsNetwork = Self.strictBoolean(saved)
        } else {
            allowsNetwork = defaultAllowsNetwork ?? Self.buildDefault(in: Bundle.main.infoDictionary)
        }
    }

    static func buildDefault(in info: [String: Any]?) -> Bool {
        strictBoolean(info?[defaultInfoKey])
    }

    private static func strictBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    func setAllowsNetwork(_ allowed: Bool) {
        // Persist explicit choices even if they happen to equal this build's default.
        defaults.set(allowed, forKey: Self.preferenceKey)
        guard allowed != allowsNetwork else { return }
        objectWillChange.send()
        allowsNetwork = allowed
        changes.send(allowed)
    }

    func requireAccess() throws {
        guard allowsNetwork else { throw NetworkAccessError.disabled }
    }
}
