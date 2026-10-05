import Foundation
import XCTest
@testable import CueCore

final class SettingsBackupTests: XCTestCase {
    private let password = "a-long-fake-test-passphrase"
    private let fakeKey = "sk-fake-backup-test-credential-0123456789"

    private var sample: SettingsBackupDocument {
        SettingsBackupDocument(exportedByVersion: "0.10.0", sections: SettingsBackupSections(
            general: SettingsBackupGeneral(language: "zh-Hant", shortcut: .default, display: .pointer, dismissOnFocusLoss: true),
            appAliases: [SettingsBackupAppAlias(bundleIdentifier: "com.microsoft.VSCode", alias: "vs")],
            conversionAliases: SettingsBackupConversion(traditional: "st", simplified: "ts"),
            browsers: [SettingsBackupBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")],
            gpt: SettingsBackupGPT(model: "gpt-6-luna", translationTarget: "automatic"),
            clipboard: SettingsBackupClipboard(retention: .week),
            windows: SettingsBackupWindows(shortcut: LauncherShortcut(keyCode: 46, modifiers: .option, key: "M"),
                keepModeOpen: true, presets: [WindowPreset(slot: 1, name: "左側六成", x: 0, y: 0, width: 0.6, height: 1)])))
    }

    func testPlainRoundTripOnlyContainsPortableWhitelist() throws {
        let encoded = try SettingsBackupCodec.encode(sample)
        let decoded = try SettingsBackupCodec.decode(encoded)
        XCTAssertEqual(decoded.document, sample)
        XCTAssertFalse(decoded.isEncrypted)
        XCTAssertNil(decoded.apiKey)
        XCTAssertTrue(decoded.warnings.isEmpty)
        XCTAssertEqual(decoded.document.sections.available, Set(SettingsBackupSection.allCases))
        XCTAssertFalse(try SettingsBackupCodec.isEncrypted(encoded))
        let text = String(decoding: encoded, as: UTF8.self)
        for excluded in ["apiKey", "credentials", "enabled", "allowsNetwork", "launchAtLogin", "history", "path", "processIdentifier", "screenID"] {
            XCTAssertFalse(text.contains("\"\(excluded)\""), excluded)
        }
        assertError(.encryptionRequired) { _ = try SettingsBackupCodec.encode(sample, apiKey: fakeKey) }
    }

    func testEqualShortcutPreferencesRemainPortableWhenFeatureMayBeDisabled() throws {
        var document = sample
        document.sections.general?.shortcut = document.sections.windows!.shortcut
        let data = try SettingsBackupCodec.encode(document)
        XCTAssertEqual(try SettingsBackupCodec.decode(data).document, document)
        // The runtime coordinator owns collision checks using local enablement.
    }

    func testEncryptedRoundTripRandomSaltNonceAndAuthenticatedCredential() throws {
        let first = try SettingsBackupCodec.encode(sample, password: password, apiKey: fakeKey)
        let second = try SettingsBackupCodec.encode(sample, password: password, apiKey: fakeKey)
        XCTAssertTrue(try SettingsBackupCodec.isEncrypted(first))
        XCTAssertNotEqual(first, second)
        let a = try json(first), b = try json(second)
        let headerA = try XCTUnwrap(a["header"] as? [String: Any]), headerB = try XCTUnwrap(b["header"] as? [String: Any])
        XCTAssertNotEqual(headerA["salt"] as? String, headerB["salt"] as? String)
        XCTAssertNotEqual(headerA["nonce"] as? String, headerB["nonce"] as? String)
        let text = String(decoding: first, as: UTF8.self)
        XCTAssertFalse(text.contains(fakeKey))
        XCTAssertFalse(text.contains(password))
        XCTAssertFalse(text.contains("左側六成"))
        let decoded = try SettingsBackupCodec.decode(first, password: password)
        XCTAssertEqual(decoded.document, sample)
        XCTAssertEqual(decoded.apiKey, fakeKey)
        XCTAssertTrue(decoded.isEncrypted)
    }

    func testWrongPasswordMissingPasswordAndWeakPasswordNeverProducePayload() throws {
        let encoded = try SettingsBackupCodec.encode(sample, password: password, apiKey: fakeKey)
        assertError(.passwordRequired) { _ = try SettingsBackupCodec.decode(encoded) }
        assertError(.authenticationFailed) { _ = try SettingsBackupCodec.decode(encoded, password: "different-valid-passphrase") }
        assertError(.invalidPassword) { _ = try SettingsBackupCodec.encode(sample, password: "short", apiKey: fakeKey) }
        assertError(.invalidPassword) { _ = try SettingsBackupCodec.encode(sample, password: String(repeating: "a", count: 1_025)) }
        XCTAssertFalse(SettingsBackupCodec.isValidPassword("a"))
        XCTAssertTrue(SettingsBackupCodec.isValidPassword(password))
        assertError(.invalidSettings) { _ = try SettingsBackupCodec.encode(sample, password: password, apiKey: "bad key") }
    }

    func testTamperedCiphertextNonceSaltTagAndCostAreRejected() throws {
        let encoded = try SettingsBackupCodec.encode(sample, password: password)
        for field in ["ciphertext", "tag"] {
            let changed = try mutate(encoded) { root in
                var bytes = Data(base64Encoded: root[field] as! String)!
                bytes[bytes.startIndex] ^= 1
                root[field] = bytes.base64EncodedString()
            }
            assertError(.authenticationFailed) { _ = try SettingsBackupCodec.decode(changed, password: password) }
        }
        for field in ["salt", "nonce"] {
            let changed = try mutate(encoded) { root in
                var header = root["header"] as! [String: Any]
                var bytes = Data(base64Encoded: header[field] as! String)!
                bytes[bytes.startIndex] ^= 1
                header[field] = bytes.base64EncodedString(); root["header"] = header
            }
            assertError(.authenticationFailed) { _ = try SettingsBackupCodec.decode(changed, password: password) }
        }
        let cost = try mutate(encoded) { root in
            var header = root["header"] as! [String: Any]
            header["iterations"] = Int(SettingsBackupCodec.iterations) + 1; root["header"] = header
        }
        assertError(.authenticationFailed) { _ = try SettingsBackupCodec.decode(cost, password: password) }
    }

    func testEnvelopeParametersAreBoundedBeforePasswordWork() throws {
        let encoded = try SettingsBackupCodec.encode(sample, password: password)
        for (field, value) in [("iterations", 0 as Any), ("iterations", 599_999), ("iterations", 1_200_001),
                               ("iterations", UInt64.max), ("salt", Data(repeating: 0, count: 15).base64EncodedString()),
                               ("nonce", Data(repeating: 0, count: 13).base64EncodedString()),
                               ("cipher", "AES-128-GCM"), ("kdf", "SHA256"), ("passwordEncoding", "UTF-16"),
                               ("untrustedHeader", "ignored? no")] {
            let changed = try mutate(encoded) { root in
                var header = root["header"] as! [String: Any]; header[field] = value; root["header"] = header
            }
            assertError(.invalidFile) { _ = try SettingsBackupCodec.decode(changed) }
        }
        let future = try mutate(encoded) { $0["schemaVersion"] = 2 }
        assertError(.unsupportedVersion) { _ = try SettingsBackupCodec.decode(future) }
        let unexpected = try mutate(encoded) { $0["untrustedHeader"] = "anything" }
        assertError(.invalidFile) { _ = try SettingsBackupCodec.decode(unexpected) }
    }

    func testUnicodePasswordCanonicalEquivalenceAndSignificantWhitespace() throws {
        let composed = "Café-測試-密碼-long-passphrase"
        let decomposed = "Cafe\u{301}-測試-密碼-long-passphrase"
        XCTAssertTrue(SettingsBackupCodec.isValidPassword(String(repeating: "é", count: 512)))
        XCTAssertTrue(SettingsBackupCodec.isValidPassword(String(repeating: "e\u{301}", count: 512)))
        let encoded = try SettingsBackupCodec.encode(sample, password: composed)
        XCTAssertEqual(try SettingsBackupCodec.decode(encoded, password: decomposed).document, sample)
        assertError(.authenticationFailed) { _ = try SettingsBackupCodec.decode(encoded, password: composed + " ") }
        let nullPassword = "long-\0-test-passphrase"
        let nullEncoded = try SettingsBackupCodec.encode(sample, password: nullPassword)
        XCTAssertEqual(try SettingsBackupCodec.decode(nullEncoded, password: nullPassword).document, sample)
    }

    func testRFC7914Section11PBKDF2HMACSHA256KnownAnswers() throws {
        // Published primary test vectors: https://www.rfc-editor.org/rfc/rfc7914.html#section-11
        // The small iteration counts are solely vector inputs; backup files reject them.
        let first = try SettingsBackupCodec.deriveKey(password: Data("passwd".utf8), salt: Data("salt".utf8), rounds: 1, length: 64)
        XCTAssertEqual(hex(first), "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
        let second = try SettingsBackupCodec.deriveKey(password: Data("Password".utf8), salt: Data("NaCl".utf8), rounds: 80_000, length: 64)
        XCTAssertEqual(hex(second), "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d")
    }

    func testUnknownFieldsAreReportedAndNeverReencodedOrApplied() throws {
        let plain = try SettingsBackupCodec.encode(sample)
        let changed = try mutate(plain) { root in
            root["allowsNetwork"] = true
            var sections = root["sections"] as! [String: Any]
            sections["loginItem"] = ["enabled": true]
            var windows = sections["windows"] as! [String: Any]
            windows["enabled"] = true; windows["path"] = "/Users/someone/private"; sections["windows"] = windows
            root["sections"] = sections
        }
        let result = try SettingsBackupCodec.decode(changed)
        XCTAssertEqual(result.document, sample)
        XCTAssertEqual(Set(result.warnings), ["allowsNetwork", "sections.loginItem", "sections.windows.enabled", "sections.windows.path"])
        let roundTrip = String(decoding: try SettingsBackupCodec.encode(result.document), as: UTF8.self)
        XCTAssertFalse(roundTrip.contains("private")); XCTAssertFalse(roundTrip.contains("allowsNetwork"))
        let unencryptedCredential = try mutate(plain) { $0["apiKey"] = fakeKey }
        assertError(.encryptionRequired) { _ = try SettingsBackupCodec.decode(unencryptedCredential) }
    }

    func testUntrustedFilesRejectDuplicateKeysDepthSizeInvalidUTF8AndVersions() throws {
        let plain = try SettingsBackupCodec.encode(sample)
        let duplicate = Data("{\"format\":\"cue-settings\",\"f\\u006frmat\":\"cue-settings\",\"schemaVersion\":1,\"exportedByVersion\":\"1.0\",\"sections\":{}}".utf8)
        assertError(.invalidFile) { _ = try SettingsBackupCodec.decode(duplicate) }
        let deep = Data((String(repeating: "[", count: 20) + "0" + String(repeating: "]", count: 20)).utf8)
        assertError(.invalidFile) { _ = try SettingsBackupCodec.decode(deep) }
        assertError(.tooLarge) { _ = try SettingsBackupCodec.decode(Data(repeating: 32, count: SettingsBackupCodec.maximumFileBytes + 1)) }
        for invalid in [Data(), Data([0xff, 0xfe]), Data("[]".utf8), Data("{}garbage".utf8), Data("{\"format\":false}".utf8)] {
            assertError(.invalidFile) { _ = try SettingsBackupCodec.decode(invalid) }
        }
        let future = try mutate(plain) { $0["schemaVersion"] = 20 }
        assertError(.unsupportedVersion) { _ = try SettingsBackupCodec.decode(future) }
    }

    func testSchemaRejectsInvalidAliasesPathsBoundsAndCrossFeatureConflicts() throws {
        var document = sample
        document.sections.appAliases = [SettingsBackupAppAlias(bundleIdentifier: "path:/Applications/Secret.app", alias: "secret")]
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        document.sections.appAliases?.append(SettingsBackupAppAlias(bundleIdentifier: "com.other.Editor", alias: "VS"))
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        document.sections.appAliases?[0].alias = "st"
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        document.sections.appAliases = (0..<257).map { SettingsBackupAppAlias(bundleIdentifier: "com.example.App\($0)", alias: "a\($0)") }
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        document.sections.browsers = (0..<9).map { SettingsBackupBrowser(bundleIdentifier: "org.browser.App\($0)", name: "Browser") }
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        let duplicatePreset = document.sections.windows!.presets[0]
        document.sections.windows?.presets.append(duplicatePreset)
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        document.sections.windows?.presets = [WindowPreset(slot: 1, name: "Bad", x: 0, y: 0, width: .infinity, height: 1)]
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        document.sections.general?.language = "not-a-supported-language"
        assertError(.invalidSettings) { try document.validated() }
        document = sample
        document.sections.gpt?.model = "model;open -a Anything"
        assertError(.invalidSettings) { try document.validated() }
    }

    private func json(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
    private func mutate(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try json(data); edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    private func assertError<T>(_ expected: SettingsBackupError, file: StaticString = #filePath, line: UInt = #line,
                                _ operation: () throws -> T) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? SettingsBackupError, expected, "Unexpected error type", file: file, line: line)
        }
    }
}
