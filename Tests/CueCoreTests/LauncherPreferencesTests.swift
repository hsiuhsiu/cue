import Foundation
import XCTest
import CueCore

final class LauncherPreferencesTests: XCTestCase {
    func testDefaultsUseNineResultsAndPreserveShortcutAndDisplayBehavior() {
        let preferences = LauncherPreferences()
        XCTAssertEqual(preferences.shortcut.keyCode, 49)
        XCTAssertEqual(preferences.shortcut.modifiers, .option)
        XCTAssertEqual(preferences.shortcut.displayName, "⌥Space")
        XCTAssertEqual(preferences.maxResults, 9)
        XCTAssertEqual(preferences.display, .pointer)
        XCTAssertTrue(preferences.dismissOnFocusLoss)
    }

    func testCustomPreferencesSurviveRoundTrip() throws {
        let preferences = LauncherPreferences(
            shortcut: LauncherShortcut(keyCode: 40, modifiers: [.control, .option], key: "K"),
            maxResults: 9, display: .main, dismissOnFocusLoss: false
        )
        let encoded = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(LauncherPreferences.self, from: encoded), preferences)
    }

    func testMissingOrUnknownValuesKeepValidSavedPreferences() throws {
        let data = Data(#"{"maxResults":50,"display":"removedDisplay","dismissOnFocusLoss":false}"#.utf8)
        let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: data)
        XCTAssertEqual(preferences.maxResults, 9)
        XCTAssertEqual(preferences.display, .pointer)
        XCTAssertFalse(preferences.dismissOnFocusLoss)
        XCTAssertEqual(preferences.shortcut, .default)
    }

    func testMalformedIndividualValuesFallBackWithoutDiscardingOtherSettings() throws {
        let data = Data(#"{"maxResults":-4,"display":"main","dismissOnFocusLoss":"invalid","shortcut":{"keyCode":49,"modifiers":0,"key":"Space"}}"#.utf8)
        let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: data)
        XCTAssertEqual(preferences.maxResults, 9)
        XCTAssertEqual(preferences.display, .main)
        XCTAssertTrue(preferences.dismissOnFocusLoss)
        XCTAssertEqual(preferences.shortcut, .default)
    }

    func testInvalidLimitsAndShortcutsAreSanitizedBeforeUse() {
        var preferences = LauncherPreferences()
        for limit in [-1, 0, 1, 9, 10, 20, 50, 100, Int.max] {
            preferences.maxResults = limit
            XCTAssertEqual(preferences.sanitized().maxResults, 9)
        }
        preferences.shortcut = LauncherShortcut(keyCode: 49, modifiers: .shift, key: "Space")
        XCTAssertEqual(preferences.sanitized().shortcut, .default)
    }

    func testLegacyResultLimitsMigrateWithoutLosingOtherPreferences() throws {
        for limit in [10, 20, 50, 100] {
            let data = Data("""
                {"maxResults":\(limit),"display":"main","dismissOnFocusLoss":false,
                 "shortcut":{"keyCode":40,"modifiers":6,"key":"K"}}
                """.utf8)
            let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: data)
            XCTAssertEqual(preferences.maxResults, 9)
            XCTAssertEqual(preferences.display, .main)
            XCTAssertFalse(preferences.dismissOnFocusLoss)
            XCTAssertEqual(preferences.shortcut.displayName, "⌃⌥K")
        }
    }

    func testShortcutRequiresARealKeyAndModifierAndPreservesSettingsCommand() {
        XCTAssertFalse(LauncherShortcut(keyCode: 49, modifiers: [], key: "Space").isValid)
        XCTAssertFalse(LauncherShortcut(keyCode: 49, modifiers: .shift, key: "Space").isValid)
        XCTAssertFalse(LauncherShortcut(keyCode: 127, modifiers: .command, key: "Unknown").isValid)
        XCTAssertFalse(LauncherShortcut(keyCode: 55, modifiers: .command, key: "Command").isValid)
        XCTAssertFalse(LauncherShortcut(keyCode: 43, modifiers: .command, key: ",").isValid)
        XCTAssertFalse(LauncherShortcut(keyCode: 49, modifiers: .option, key: "  ").isValid)
        XCTAssertFalse(LauncherShortcut(keyCode: 49, modifiers: [.option, .init(rawValue: 1 << 8)], key: "Space").isValid)
        XCTAssertTrue(LauncherShortcut(keyCode: 43, modifiers: [.command, .shift], key: ",").isValid)
        XCTAssertEqual(
            LauncherShortcut(keyCode: 40, modifiers: [.command, .control, .option, .shift], key: "K").displayName,
            "⌃⌥⇧⌘K"
        )
    }

    func testQueryActionShortcutsAreReservedButExtraModifiersRemainAvailable() {
        let actionKeys: [(UInt32, String)] = [(36, "Return"), (76, "Enter"), (40, "K"), (14, "E")]
        let additionalModifiers: [LauncherShortcut.Modifiers] = [.shift, .option, .control]
        for (keyCode, key) in actionKeys {
            let reserved = LauncherShortcut(keyCode: keyCode, modifiers: .command, key: key)
            XCTAssertFalse(reserved.isValid)
            XCTAssertEqual(LauncherPreferences(shortcut: reserved).shortcut, .default)

            var edited = LauncherPreferences(display: .main, dismissOnFocusLoss: false)
            edited.shortcut = reserved
            let sanitized = edited.sanitized()
            XCTAssertEqual(sanitized.shortcut, .default)
            XCTAssertEqual(sanitized.display, .main)
            XCTAssertFalse(sanitized.dismissOnFocusLoss)

            for modifier in additionalModifiers {
                let shortcut = LauncherShortcut(keyCode: keyCode, modifiers: [.command, modifier], key: key)
                XCTAssertTrue(shortcut.isValid)
                XCTAssertEqual(LauncherPreferences(shortcut: shortcut).shortcut, shortcut)
            }
        }
    }

    func testLegacySavedQueryActionShortcutsAreSanitizedWithoutLosingOtherPreferences() throws {
        for (keyCode, key) in [(36, "Return"), (76, "Enter"), (40, "K"), (14, "E")] {
            let data = Data("""
                {"maxResults":9,"display":"main","dismissOnFocusLoss":false,
                 "shortcut":{"keyCode":\(keyCode),"modifiers":1,"key":"\(key)"}}
                """.utf8)
            let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: data)
            XCTAssertEqual(preferences.shortcut, .default)
            XCTAssertEqual(preferences.maxResults, 9)
            XCTAssertEqual(preferences.display, .main)
            XCTAssertFalse(preferences.dismissOnFocusLoss)
            XCTAssertEqual(try JSONDecoder().decode(LauncherPreferences.self, from: JSONEncoder().encode(preferences)),
                           preferences)
        }
    }
}
