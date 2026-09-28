import Combine
import Foundation

@main
struct NetworkPolicyChecks {
    @MainActor
    static func main() throws {
        let suite = "cue-network-policy-check-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(value(), message)
        }
        let key = NetworkPolicy.preferenceKey
        let infoKey = NetworkPolicy.defaultInfoKey
        expect(!NetworkPolicy.buildDefault(in: nil), "Missing metadata fails closed")
        for invalid: Any in ["true", 1, 0, NSNull(), [true]] {
            expect(!NetworkPolicy.buildDefault(in: [infoKey: invalid]), "Malformed metadata fails closed")
        }
        expect(NetworkPolicy.buildDefault(in: [infoKey: true]), "Official metadata can enable networking")
        expect(!NetworkPolicy.buildDefault(in: [infoKey: false]), "Source metadata disables networking")
        defaults.set(true, forKey: "SUEnableAutomaticChecks")
        defaults.set("unchanged", forKey: "launcherPreferences")
        defaults.set(["zh-Hant"], forKey: "AppleLanguages")
        let source = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        expect(!source.allowsNetwork, "Old update preference cannot grant network access")
        expect(defaults.object(forKey: key) == nil, "Reading a build default never persists a choice")
        expect(NetworkPolicy(defaults: defaults, defaultAllowsNetwork: true).allowsNetwork, "Release defaults on")
        var notifications: [Bool] = []
        let observation = source.changes.sink { allowed in
            notifications.append(allowed)
            expect(source.allowsNetwork == allowed, "Observers see the new authoritative state")
            expect(((try? source.requireAccess()) != nil) == allowed, "Observer gate agrees with emitted state")
        }
        source.setAllowsNetwork(false)
        expect(defaults.object(forKey: key) != nil, "An explicit default-equal choice is saved")
        expect(notifications.isEmpty, "Unchanged value does not notify")
        expect(!NetworkPolicy(defaults: defaults, defaultAllowsNetwork: true).allowsNetwork, "Explicit off survives official install")
        source.setAllowsNetwork(true)
        expect(NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false).allowsNetwork, "Explicit on survives source install")
        source.setAllowsNetwork(true)
        expect(notifications == [true], "No redundant publication")
        for i in 0..<100 {
            let value = i % 2 != 0
            source.setAllowsNetwork(value)
            expect(NetworkPolicy(defaults: defaults, defaultAllowsNetwork: !value).allowsNetwork == value,
                   "Repeated changes persist independently of distribution defaults")
        }
        observation.cancel()
        for invalid: Any in ["true", 1, 0, [true]] {
            defaults.set(invalid, forKey: key)
            expect(!NetworkPolicy(defaults: defaults, defaultAllowsNetwork: true).allowsNetwork,
                   "Malformed saved preferences fail closed")
        }
        expect(defaults.string(forKey: "launcherPreferences") == "unchanged", "Launcher settings are untouched")
        expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hant"], "Language preference is untouched")
        print("Network policy: \(checks) checks passed")
    }
}
