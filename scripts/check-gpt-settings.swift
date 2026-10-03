import AppKit
import CueCore

private actor SyntheticKeyStore {
    var value: String?
    var reads = 0
    var saves = 0
    var deletes = 0
    var nextError: GPTKeychainError?
    var holdRead = false
    var heldRead: CheckedContinuation<Bool, any Error>?

    var store: GPTKeyStore {
        GPTKeyStore(contains: { try await self.contains() },
                    save: { try await self.save($0) }, delete: { try await self.delete() })
    }

    func counts() -> [Int] { [reads, saves, deletes] }
    func savedValue() -> String? { value }
    func failNext(_ error: GPTKeychainError) { nextError = error }
    func holdNextRead() { holdRead = true }
    func isReadWaiting() -> Bool { heldRead != nil }
    func resumeRead(_ value: Bool) {
        holdRead = false
        heldRead?.resume(returning: value)
        heldRead = nil
    }

    private func contains() async throws -> Bool {
        reads += 1
        try throwPendingError()
        if holdRead {
            return try await withCheckedThrowingContinuation { heldRead = $0 }
        }
        return value != nil
    }

    private func save(_ value: String) throws {
        saves += 1
        try throwPendingError()
        self.value = value
    }

    private func delete() throws {
        deletes += 1
        try throwPendingError()
        value = nil
    }

    private func throwPendingError() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}

/// Only isolated defaults and injected in-memory credentials are used. This check
/// does not read, save, remove, or even query a real Keychain item or network URL.
@main
struct CheckGPTSettings {
    @MainActor private static var checks = 0

    @MainActor private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let domain = "com.yyhsiu.cue.tests.gpt-settings.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = GPTPreferences(defaults: defaults)
        check(preferences.configuration == GPTConfiguration(), "Fresh preferences use GPT-6 Luna and automatic translation")
        var changes = 0
        preferences.onChange = { changes += 1 }
        try preferences.setConfiguration(GPTConfiguration())
        check(changes == 0, "Unchanged choices do not invalidate the answer or search")
        try preferences.setConfiguration(GPTConfiguration(model: "  gpt-6-sol  ", translationTarget: .english))
        check(preferences.configuration.model == "gpt-6-sol" && changes == 1,
              "A saved model trims surrounding whitespace and emits one change")
        check(GPTPreferences(defaults: defaults).configuration == preferences.configuration,
              "Both non-sensitive choices survive a preferences reload")
        let valid = preferences.configuration
        for invalid in ["", " ", "model\nname", "model name", "https://other.example/model", ".name", "模型", String(repeating: "a", count: 129)] {
            do {
                try preferences.setConfiguration(GPTConfiguration(model: invalid, translationTarget: .automatic))
                check(false, "An invalid model must throw")
            } catch {
                check(preferences.configuration == valid && changes == 1,
                      "Rejected configuration does not partially save translation or model")
            }
        }
        check(GPTPreferences(defaults: defaults).configuration == valid,
              "Invalid edits never overwrite persisted choices")
        defaults.set(42, forKey: GPTPreferences.modelKey)
        defaults.set("unknown", forKey: GPTPreferences.translationKey)
        check(GPTPreferences(defaults: defaults).configuration == GPTConfiguration(),
              "Wrong preference types and unknown translation values safely restore defaults")
        defaults.set("bad/model", forKey: GPTPreferences.modelKey)
        check(GPTPreferences(defaults: defaults).configuration.model == GPTConfiguration.defaultModel,
              "Invalid persisted model identifiers use the default model")
        try preferences.setConfiguration(GPTConfiguration(model: "gpt-6-luna", translationTarget: .traditionalChinese))
        let persisted = defaults.persistentDomain(forName: domain) ?? [:]
        check(Set(persisted.keys) == [GPTPreferences.modelKey, GPTPreferences.translationKey],
              "Preferences store only model and translation, never credentials or query text")

        for invalid in ["", "short", "sk-synthetic key-with-space", "sk-synthetic\nkey-newline", "sk-synthetic\tkey-tab", "sk-synthetic-金鑰", String(repeating: "a", count: 513)] {
            check(!GPTKeychain.isValidKey(invalid), "Malformed credentials are rejected before Keychain access")
        }
        let syntheticKey = "sk-synthetic-test-value-never-a-real-secret"
        check(GPTKeychain.isValidKey(syntheticKey), "A complete printable synthetic key is accepted")
        let fake = SyntheticKeyStore()
        let keyStore = await fake.store
        let model = GPTCredentialModel(store: keyStore)
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let controller = GPTSettingsController(preferences: preferences, policy: policy, keyStore: keyStore)
        let initialCounts = await fake.counts()
        check(initialCounts == [0, 0, 0] && model.hasSavedKey == nil,
              "Constructing preferences, credential state and settings performs no Keychain access")
        check(controller.window != nil && !policy.allowsNetwork,
              "Settings can be prepared while the global network policy stays off")
        await model.refresh()
        let refreshedCounts = await fake.counts()
        check(refreshedCounts == [1, 0, 0] && model.hasSavedKey == false && model.draftKey.isEmpty,
              "Explicit status refresh checks presence without populating the secret field")
        var credentialChanges = 0
        model.onCredentialsChange = { credentialChanges += 1 }
        model.draftKey = "bad"
        await model.save()
        let rejectedCounts = await fake.counts()
        check(rejectedCounts == refreshedCounts && credentialChanges == 0 && model.isError,
              "Invalid credentials trigger neither mutation nor request cancellation")
        model.draftKey = syntheticKey
        await model.save()
        let saved = await fake.savedValue()
        check(saved == syntheticKey && model.hasSavedKey == true && model.draftKey.isEmpty,
              "Saving passes the key only to the injected store and clears transient input")
        check(credentialChanges == 1 && !model.isBusy && !model.isError,
              "Saving signals cancellation of active requests and finishes without stale busy state")
        await model.refresh()
        check(model.hasSavedKey == true && model.draftKey.isEmpty,
              "Refreshing a saved key never reveals the key")
        await model.remove()
        let removed = await fake.savedValue()
        check(removed == nil && model.hasSavedKey == false && credentialChanges == 2,
              "Removing a key clears only the injected credential and cancels existing requests")
        await fake.failNext(.accessDenied)
        model.draftKey = syntheticKey
        await model.save()
        check(model.isError && model.notice == GPTSettingsText.keyDenied && model.draftKey.isEmpty && !model.isBusy,
              "Denied Keychain access uses a sanitized error and retains no draft secret")
        await fake.failNext(.unavailable)
        await model.refresh()
        check(model.isError && model.notice == GPTSettingsText.keyUnavailable && !model.isBusy,
              "Unexpected store failure exposes no underlying error or secret")
        model.draftKey = syntheticKey
        model.close()
        check(model.draftKey.isEmpty && model.hasSavedKey == nil && model.notice == nil,
              "Closing settings clears all transient credential presentation")

        await fake.holdNextRead()
        let refresh = Task { await model.refresh() }
        for _ in 0..<10_000 {
            if await fake.isReadWaiting() { break }
            await Task.yield()
        }
        let waiting = await fake.isReadWaiting()
        check(waiting && model.isBusy, "Status lookup can run asynchronously without blocking the main actor")
        let countsWhileBusy = await fake.counts()
        await model.remove()
        let countsAfterBusyAttempt = await fake.counts()
        check(countsWhileBusy == countsAfterBusyAttempt,
              "A second credential operation does not overlap an active lookup")
        model.close()
        await fake.resumeRead(true)
        await refresh.value
        check(model.hasSavedKey == nil && !model.isBusy && model.draftKey.isEmpty,
              "A completed lookup cannot repopulate a closed settings window")

        await fake.holdNextRead()
        let cancelled = Task { await model.refresh() }
        for _ in 0..<10_000 {
            if await fake.isReadWaiting() { break }
            await Task.yield()
        }
        cancelled.cancel()
        await fake.resumeRead(true)
        await cancelled.value
        check(!model.isBusy && model.hasSavedKey == nil,
              "Cancellation alone clears busy state and discards a late lookup result")
        await model.refresh()
        check(!model.isBusy && model.hasSavedKey == false,
              "A new explicit lookup works after cancellation")
        check(!policy.allowsNetwork, "Credential and preference editing never enables the global network policy")
        print("GPT settings passed: \(checks) preference, secure-state, cancellation and offline checks; no real Keychain access.")
    }
}
