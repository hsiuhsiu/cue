import Foundation
import LocalAuthentication
import Security

enum GPTKeychainError: Error, Equatable, Sendable {
    case invalidKey
    case accessDenied
    case unavailable
}

/// An actor keeps potentially blocking Security calls away from the main actor.
/// Only this app's explicitly saved OpenAI credential is ever queried.
actor GPTKeychain {
    static let shared = GPTKeychain()
    private let service = "com.yyhsiu.cue.openai"
    private let account = "api-key"

    nonisolated static func isValidKey(_ value: String) -> Bool {
        let bytes = value.utf8
        return (16...512).contains(bytes.count) && bytes.allSatisfy { (33...126).contains($0) }
    }

    func read() throws -> String? {
        try Task.checkCancellation()
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        try Task.checkCancellation()
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8),
              Self.isValidKey(value) else { throw GPTKeychainError.invalidKey }
        return value
    }

    /// Settings need presence, not the secret. Never prefill the secure field.
    func containsKey() throws -> Bool {
        try Task.checkCancellation()
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        try Task.checkCancellation()
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    func save(_ value: String) throws {
        guard Self.isValidKey(value) else { throw GPTKeychainError.invalidKey }
        try Task.checkCancellation()
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try Task.checkCancellation()
            var item = baseQuery
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrLabel as String] = "Cue OpenAI API Key"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func delete() throws {
        try Task.checkCancellation()
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        if [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled].contains(status) {
            throw GPTKeychainError.accessDenied
        }
        throw GPTKeychainError.unavailable
    }
}

/// Injection keeps settings tests independent of the user's real Keychain.
struct GPTKeyStore: Sendable {
    var contains: @Sendable () async throws -> Bool
    var save: @Sendable (String) async throws -> Void
    var delete: @Sendable () async throws -> Void

    static let keychain = GPTKeyStore(
        contains: { try await GPTKeychain.shared.containsKey() },
        save: { try await GPTKeychain.shared.save($0) },
        delete: { try await GPTKeychain.shared.delete() }
    )
}
