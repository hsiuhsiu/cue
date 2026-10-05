import CommonCrypto
import CryptoKit
import Foundation
import Security

/// CPU and JSON work belongs on a background actor/task. This type never reads
/// preferences, files, Keychain, clipboard, or the network. Passwords/API keys are
/// transient inputs; Swift cannot guarantee erasure of every copied String.
public enum SettingsBackupCodec {
    public static let maximumFileBytes = 1_048_576
    public static let minimumPasswordCharacters = 12
    public static let maximumPasswordBytes = 1_024
    public static let iterations: UInt32 = 600_000
    public static let maximumIterations: UInt32 = 1_200_000

    private struct Header: Codable {
        let cipher: String
        let kdf: String
        let iterations: UInt32
        let passwordEncoding: String
        let salt: String
        let nonce: String
    }

    private struct Envelope: Codable {
        let format: String
        let schemaVersion: Int
        let header: Header
        let ciphertext: String
        let tag: String

        var authenticatedData: Data {
            // The authenticated header has a fixed, unambiguous serialization,
            // independent of JSON key ordering/whitespace. All fields are bounded
            // and validated before KDF work, including canonical Base64.
            Data([format, String(schemaVersion), header.cipher, header.kdf, String(header.iterations),
                  header.passwordEncoding, header.salt, header.nonce].joined(separator: "\n").utf8)
        }
    }

    private struct Payload: Codable {
        let document: SettingsBackupDocument
        let apiKey: String?
    }

    public static func isEncrypted(_ data: Data) throws -> Bool {
        let object = try SettingsBackupJSON.object(data)
        guard let format = object["format"] as? String else { throw SettingsBackupError.invalidFile }
        switch format {
        case "cue-settings": return false
        case "cue-settings-encrypted": return true
        default: throw SettingsBackupError.invalidFile
        }
    }

    public static func encode(_ document: SettingsBackupDocument, password: String? = nil,
                              apiKey: String? = nil) throws -> Data {
        try Task.checkCancellation()
        try document.validated()
        guard apiKey == nil || password != nil else { throw SettingsBackupError.encryptionRequired }
        if let apiKey { guard validAPIKey(apiKey) else { throw SettingsBackupError.invalidSettings } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let password else { return try bounded(encoder.encode(document)) }
        let passwordBytes = try passwordData(password)
        let salt = try randomBytes(count: 16), nonce = try randomBytes(count: 12)
        let header = Header(cipher: "AES-256-GCM", kdf: "PBKDF2-HMAC-SHA256", iterations: iterations,
                            passwordEncoding: "UTF-8-NFC", salt: salt.base64EncodedString(), nonce: nonce.base64EncodedString())
        let template = Envelope(format: "cue-settings-encrypted", schemaVersion: 1, header: header, ciphertext: "", tag: "")
        let plaintext = try bounded(encoder.encode(Payload(document: document, apiKey: apiKey)))
        let key = SymmetricKey(data: try deriveKey(password: passwordBytes, salt: salt, rounds: iterations))
        try Task.checkCancellation()
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonce),
                                      authenticating: template.authenticatedData)
        } catch { throw SettingsBackupError.cryptographyFailure }
        let envelope = Envelope(format: template.format, schemaVersion: 1, header: header,
                                ciphertext: sealed.ciphertext.base64EncodedString(), tag: sealed.tag.base64EncodedString())
        try Task.checkCancellation()
        return try bounded(encoder.encode(envelope))
    }

    public static func decode(_ data: Data, password: String? = nil) throws -> SettingsBackupDecoded {
        try Task.checkCancellation()
        let object = try SettingsBackupJSON.object(data)
        guard let format = object["format"] as? String else { throw SettingsBackupError.invalidFile }
        if format == "cue-settings" {
            guard object["apiKey"] == nil, object["credentials"] == nil else { throw SettingsBackupError.encryptionRequired }
            return try document(from: data, object: object, apiKey: nil, encrypted: false)
        }
        guard format == "cue-settings-encrypted" else { throw SettingsBackupError.invalidFile }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw SettingsBackupError.invalidFile }
        guard envelope.schemaVersion == 1 else { throw SettingsBackupError.unsupportedVersion }
        guard Set(object.keys) == Set(["format", "schemaVersion", "header", "ciphertext", "tag"]),
              let headerObject = object["header"] as? [String: Any],
              Set(headerObject.keys) == Set(["cipher", "kdf", "iterations", "passwordEncoding", "salt", "nonce"]),
              envelope.header.cipher == "AES-256-GCM", envelope.header.kdf == "PBKDF2-HMAC-SHA256",
              envelope.header.passwordEncoding == "UTF-8-NFC",
              (iterations...maximumIterations).contains(envelope.header.iterations),
              let salt = canonicalBase64(envelope.header.salt), salt.count == 16,
              let nonce = canonicalBase64(envelope.header.nonce), nonce.count == 12,
              let tag = canonicalBase64(envelope.tag), tag.count == 16,
              let ciphertext = canonicalBase64(envelope.ciphertext), !ciphertext.isEmpty else {
            throw SettingsBackupError.invalidFile
        }
        guard let password else { throw SettingsBackupError.passwordRequired }
        let key = SymmetricKey(data: try deriveKey(password: passwordData(password), salt: salt, rounds: envelope.header.iterations))
        try Task.checkCancellation()
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            plaintext = try AES.GCM.open(box, using: key, authenticating: envelope.authenticatedData)
        } catch { throw SettingsBackupError.authenticationFailed }
        try Task.checkCancellation()
        let payloadObject = try SettingsBackupJSON.object(plaintext)
        guard Set(payloadObject.keys).isSubset(of: ["document", "apiKey"]),
              let documentObject = payloadObject["document"] as? [String: Any] else { throw SettingsBackupError.invalidFile }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: plaintext) }
        catch { throw SettingsBackupError.invalidFile }
        if let apiKey = payload.apiKey { guard validAPIKey(apiKey) else { throw SettingsBackupError.invalidSettings } }
        try payload.document.validated()
        return SettingsBackupDecoded(document: payload.document, apiKey: payload.apiKey, isEncrypted: true,
                                     warnings: ignoredFields(in: documentObject))
    }

    /// Exposed for the secure-field UI to reject weak/oversized input before
    /// asking Keychain for an explicitly selected credential. No trimming.
    public static func isValidPassword(_ password: String) -> Bool { (try? passwordData(password)) != nil }

    private static func document(from data: Data, object: [String: Any], apiKey: String?, encrypted: Bool) throws -> SettingsBackupDecoded {
        let decoded: SettingsBackupDocument
        do { decoded = try JSONDecoder().decode(SettingsBackupDocument.self, from: data) }
        catch { throw SettingsBackupError.invalidFile }
        try decoded.validated()
        return SettingsBackupDecoded(document: decoded, apiKey: apiKey, isEncrypted: encrypted, warnings: ignoredFields(in: object))
    }

    private static func bounded(_ data: Data) throws -> Data {
        guard data.count <= maximumFileBytes else { throw SettingsBackupError.tooLarge }
        return data
    }

    private static func passwordData(_ value: String) throws -> Data {
        // Bound work before normalization, then apply the public byte limit to
        // NFC. Canonically equivalent keyboard input must derive the same key,
        // including near the maximum password length.
        guard value.utf8.count <= maximumPasswordBytes * 4 else { throw SettingsBackupError.invalidPassword }
        let normalized = value.precomposedStringWithCanonicalMapping
        guard normalized.count >= minimumPasswordCharacters, normalized.utf8.count <= maximumPasswordBytes else {
            throw SettingsBackupError.invalidPassword
        }
        return Data(normalized.utf8)
    }

    private static func validAPIKey(_ value: String) -> Bool {
        (16...512).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    private static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw SettingsBackupError.cryptographyFailure }
        return data
    }

    private static func canonicalBase64(_ text: String) -> Data? {
        guard let data = Data(base64Encoded: text), data.base64EncodedString() == text else { return nil }
        return data
    }

    // Internal for RFC 7914 test vectors. Production entry points enforce the
    // 600,000…1,200,000 cost range before invoking CommonCrypto. The routine
    // itself also rejects unbounded parameters; no attacker-controlled key size.
    static func deriveKey(password: Data, salt: Data, rounds: UInt32, length: Int = 32) throws -> Data {
        guard rounds > 0, rounds <= maximumIterations, (1...64).contains(length),
              password.count <= maximumPasswordBytes, salt.count <= 64 else { throw SettingsBackupError.invalidFile }
        try Task.checkCancellation()
        var result = Data(count: length)
        let status = result.withUnsafeMutableBytes { output in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress, password.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        output.bindMemory(to: UInt8.self).baseAddress, length)
                }
            }
        }
        guard status == kCCSuccess else { throw SettingsBackupError.cryptographyFailure }
        try Task.checkCancellation()
        return result
    }

    private static func ignoredFields(in root: [String: Any]) -> [String] {
        var result: [String] = []
        func inspect(_ object: [String: Any], keys: Set<String>, prefix: String) {
            for key in object.keys.sorted() where !keys.contains(key) && result.count < 64 {
                let cleaned = String(key.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(64))
                result.append(prefix + cleaned)
            }
        }
        inspect(root, keys: ["format", "schemaVersion", "exportedByVersion", "sections"], prefix: "")
        guard let sections = root["sections"] as? [String: Any] else { return result }
        inspect(sections, keys: Set(SettingsBackupSection.allCases.map(\.rawValue)), prefix: "sections.")
        let fields: [String: Set<String>] = [
            "general": ["language", "shortcut", "display", "dismissOnFocusLoss"],
            "appAliases": ["bundleIdentifier", "alias"], "conversionAliases": ["traditional", "simplified"],
            "browsers": ["bundleIdentifier", "name"], "gpt": ["model", "translationTarget"],
            "clipboard": ["retention"], "windows": ["shortcut", "keepModeOpen", "presets"]
        ]
        for (name, keys) in fields {
            let entries = (sections[name] as? [[String: Any]]) ?? (sections[name] as? [String: Any]).map { [$0] } ?? []
            for entry in entries {
                inspect(entry, keys: keys, prefix: "sections.\(name).")
                if let shortcut = entry["shortcut"] as? [String: Any] {
                    inspect(shortcut, keys: ["keyCode", "modifiers", "key"], prefix: "sections.\(name).shortcut.")
                    if let modifiers = shortcut["modifiers"] as? [String: Any] {
                        inspect(modifiers, keys: ["rawValue"], prefix: "sections.\(name).shortcut.modifiers.")
                    }
                }
                if let presets = entry["presets"] as? [[String: Any]] {
                    for preset in presets { inspect(preset, keys: ["slot", "name", "x", "y", "width", "height"], prefix: "sections.windows.presets.") }
                }
            }
        }
        return Array(Set(result)).sorted()
    }
}

/// Reject oversized/deep/ambiguous JSON before Foundation allocates its object
/// graph. Lexical scanning limits nesting and duplicate object keys, then the
/// system parser performs complete UTF-8 and JSON grammar validation.
private enum SettingsBackupJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= SettingsBackupCodec.maximumFileBytes else { throw SettingsBackupError.tooLarge }
        var scanner = Scanner(bytes: Array(data))
        try scanner.value(depth: 0)
        scanner.whitespace()
        guard scanner.index == scanner.bytes.count else { throw SettingsBackupError.invalidFile }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SettingsBackupError.invalidFile }
            return object
        } catch { throw SettingsBackupError.invalidFile }
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var tokens = 0
        mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func value(depth: Int) throws {
            whitespace(); tokens += 1
            guard depth <= 16, tokens <= 16_384, index < bytes.count else { throw SettingsBackupError.invalidFile }
            switch bytes[index] {
            case 123:
                index += 1; whitespace()
                if consume(125) { return }
                var keys = Set<String>()
                repeat {
                    whitespace()
                    let keyData = try string()
                    guard keyData.count <= 1_024, let key = try? JSONDecoder().decode(String.self, from: keyData),
                          keys.insert(key).inserted else { throw SettingsBackupError.invalidFile }
                    whitespace(); guard consume(58) else { throw SettingsBackupError.invalidFile }
                    try value(depth: depth + 1); whitespace()
                    if consume(125) { return }
                    guard consume(44) else { throw SettingsBackupError.invalidFile }
                } while true
            case 91:
                index += 1; whitespace()
                if consume(93) { return }
                repeat {
                    try value(depth: depth + 1); whitespace()
                    if consume(93) { return }
                    guard consume(44) else { throw SettingsBackupError.invalidFile }
                } while true
            case 34: _ = try string()
            default:
                let start = index
                while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw SettingsBackupError.invalidFile }
            }
        }
        mutating func string() throws -> Data {
            let start = index
            guard consume(34) else { throw SettingsBackupError.invalidFile }
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 34 { return Data(bytes[start..<index]) }
                if byte == 92 { index += 1 }
            }
            throw SettingsBackupError.invalidFile
        }
        mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1; return true
        }
    }
}
