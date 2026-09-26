import Foundation
import XCTest
import CueCore

final class LauncherPreferencesTests: XCTestCase {
    func testDefaultsPreserveOriginalLauncherBehavior() {
        let preferences = LauncherPreferences()
        XCTAssertEqual(preferences.shortcut.keyCode, 49)
        XCTAssertEqual(preferences.shortcut.modifiers, .option)
        XCTAssertEqual(preferences.shortcut.displayName, "⌥Space")
        XCTAssertEqual(preferences.maxResults, 20)
        XCTAssertEqual(preferences.display, .pointer)
        XCTAssertTrue(preferences.dismissOnFocusLoss)
    }

    func testCustomPreferencesSurviveRoundTrip() throws {
        let preferences = LauncherPreferences(
            shortcut: LauncherShortcut(keyCode: 40, modifiers: [.control, .option], key: "K"),
            maxResults: 50, display: .main, dismissOnFocusLoss: false
        )
        let encoded = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(LauncherPreferences.self, from: encoded), preferences)
    }

    func testMissingOrUnknownValuesKeepValidSavedPreferences() throws {
        let data = Data(#"{"maxResults":50,"display":"removedDisplay","dismissOnFocusLoss":false}"#.utf8)
        let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: data)
        XCTAssertEqual(preferences.maxResults, 50)
        XCTAssertEqual(preferences.display, .pointer)
        XCTAssertFalse(preferences.dismissOnFocusLoss)
        XCTAssertEqual(preferences.shortcut, .default)
    }

    func testMalformedIndividualValuesFallBackWithoutDiscardingOtherSettings() throws {
        let data = Data(#"{"maxResults":-4,"display":"main","dismissOnFocusLoss":"invalid","shortcut":{"keyCode":49,"modifiers":0,"key":"Space"}}"#.utf8)
        let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: data)
        XCTAssertEqual(preferences.maxResults, 20)
        XCTAssertEqual(preferences.display, .main)
        XCTAssertTrue(preferences.dismissOnFocusLoss)
        XCTAssertEqual(preferences.shortcut, .default)
    }

    func testInvalidLimitsAndShortcutsAreSanitizedBeforeUse() {
        var preferences = LauncherPreferences()
        for limit in [-1, 0, 1, 21, Int.max] {
            preferences.maxResults = limit
            XCTAssertEqual(preferences.sanitized().maxResults, 20)
        }
        for limit in LauncherPreferences.resultLimits {
            preferences.maxResults = limit
            XCTAssertEqual(preferences.sanitized().maxResults, limit)
        }
        preferences.shortcut = LauncherShortcut(keyCode: 49, modifiers: .shift, key: "Space")
        XCTAssertEqual(preferences.sanitized().shortcut, .default)
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
}
