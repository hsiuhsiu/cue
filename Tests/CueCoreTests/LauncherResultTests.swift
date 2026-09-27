import Foundation
import XCTest
import CueCore

final class LauncherResultTests: XCTestCase {
    private func app(_ name: String, id: String? = nil) -> IndexedApplication {
        IndexedApplication(
            id: id,
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    func testEnglishAliasesFindUpdateCommand() {
        for query in [
            "update app index", "update index", "refresh apps", "refresh index",
            "reindex", "rebuild index", "update", "refresh", "index",
        ] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.updateIndex], query)
        }
    }

    func testTraditionalChineseAliasesFindUpdateCommand() {
        for query in ["更新索引", "更新應用程式索引", "重新索引", "重建索引", "重新掃描", "更新", "索引"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.updateIndex], query)
        }
    }

    func testCaseAndWhitespaceAreNormalized() {
        for query in [" \tUPDATE   app\nINDEX  ", "  ReInDeX  ", "\n  更新索引 \t"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.updateIndex], query)
        }
    }

    func testUnrelatedAndSingleASCIICharacterQueriesExcludeCommand() {
        let applications = [app("Safari"), app("Terminal")]
        for query in ["saf", "term", "unrelated", "u", "r", "i", "a"] {
            XCTAssertFalse(LauncherResult.search(applications, query: query).contains(.updateIndex), query)
        }
        XCTAssertEqual(LauncherResult.search(applications, query: "saf"), [.application(applications[0])])
        XCTAssertEqual(LauncherResult.search(applications, query: "term"), [.application(applications[1])])
    }

    func testMatchingCommandPrecedesApplicationsWithoutChangingTheirRanking() {
        let applications = [app("My Index"), app("Index Pro"), app("Index")]
        let results = LauncherResult.search(applications, query: "index")
        XCTAssertEqual(results, [.updateIndex] + SearchEngine.search(applications, query: "index").map(LauncherResult.application))
        XCTAssertEqual(results.filter { $0 == .updateIndex }.count, 1)
        XCTAssertEqual(LauncherResult.search(applications.reversed(), query: "index"), results)
    }

    func testEmptyAndWhitespaceQueriesDoNotShowApplicationsOrCommands() {
        let applications = [app("Terminal"), app("Safari"), app("Clipboard")]
        for query in ["", " ", "\n \t\r", "\u{00A0}\u{2003}\u{3000}"] {
            XCTAssertTrue(LauncherResult.search(applications, query: query).isEmpty, query.debugDescription)
            XCTAssertTrue(LauncherResult.search([], query: query).isEmpty, query.debugDescription)
        }
    }

    func testTypingAfterEmptyQueryStillFindsApplicationsAndCommands() {
        let applications = [app("Terminal"), app("Safari"), app("Clipboard")]
        XCTAssertTrue(LauncherResult.search(applications, query: "").isEmpty)
        XCTAssertEqual(LauncherResult.search(applications, query: "saf"), [.application(applications[1])])
        XCTAssertEqual(LauncherResult.search(applications, query: "clipboard"), [
            .clipboardHistory, .application(applications[2]),
        ])
        XCTAssertTrue(LauncherResult.search(applications, query: "\n\t").isEmpty)
        XCTAssertEqual(LauncherResult.search(applications, query: "index"), [.updateIndex])
    }

    func testClipboardCommandIsDiscoverableInBothLanguages() {
        for query in ["clipboard", "CLIPBOARD", "clip", "clipboard history", "paste history", "剪貼簿", "剪貼簿歷史", "剪貼簿記錄", "剪貼簿紀錄", "複製紀錄"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.clipboardHistory], query)
        }
        let applications = [app("Clipboard")]
        XCTAssertEqual(LauncherResult.search(applications, query: "clipboard"), [
            .clipboardHistory, .application(applications[0]),
        ])
        XCTAssertFalse(LauncherResult.search([], query: "c").contains(.clipboardHistory))
        XCTAssertNotEqual(LauncherResult.clipboardHistory.id, LauncherResult.updateIndex.id)
    }

    func testSleepCommandIsDiscoverableInBothLanguages() {
        for query in ["sleep", "SLEEP", "sl", "sleep mac", "sleep computer", "睡眠", "讓電腦睡眠", "電腦睡眠", "睡"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.sleep], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: " \tSlEeP  \n COMPUTER "), [.sleep])
    }

    func testLockCommandIsDiscoverableInBothLanguages() {
        for query in ["lock", "LOCK", "lo", "lock screen", "lock mac", "lock computer", "鎖定", "鎖定螢幕", "鎖定畫面", "鎖定電腦", "鎖屏", "鎖"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.lockScreen], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: " \tLoCk  \n SCREEN "), [.lockScreen])
    }

    func testPowerCommandsDoNotCrowdSingleLetterOrUnrelatedSearches() {
        for query in ["s", "l", "m", "c", "sleep display", "sleepy", "unrelated"] {
            XCTAssertTrue(LauncherResult.search([], query: query).isEmpty, query)
        }
        let applications = [app("Safari"), app("Locksmith")]
        XCTAssertEqual(LauncherResult.search(applications, query: "l"),
                       SearchEngine.search(applications, query: "l").map(LauncherResult.application))
    }

    func testSystemCommandsPrecedeApplicationsAndAreNotDuplicatedByAliases() {
        let applications = [app("Sleep Monitor"), app("Sleep"), app("Locksmith"), app("Lock Screen")]
        for (query, command) in [("sleep", LauncherResult.sleep), ("lock", LauncherResult.lockScreen)] {
            let results = LauncherResult.search(applications, query: query)
            XCTAssertEqual(results, [command] + SearchEngine.search(applications, query: query).map(LauncherResult.application))
            XCTAssertEqual(results.filter { $0 == command }.count, 1, query)
        }
        // Shared aliases keep a stable command order regardless of app order.
        XCTAssertEqual(LauncherResult.search([], query: "computer"), [.sleep, .lockScreen])
        XCTAssertEqual(LauncherResult.search([], query: "電腦"), [.sleep, .lockScreen])
    }

    func testSystemCommandIdentitiesDoNotCollideWithApplicationsOrOtherCommands() {
        let commands: [LauncherResult] = [.updateIndex, .clipboardHistory, .sleep, .lockScreen]
        XCTAssertEqual(Set(commands.map(\.id)).count, commands.count)
        XCTAssertEqual(LauncherResult.sleep.id, "command:sleep")
        XCTAssertEqual(LauncherResult.sleep.name, "Sleep")
        XCTAssertEqual(LauncherResult.lockScreen.id, "command:lock-screen")
        XCTAssertEqual(LauncherResult.lockScreen.name, "Lock Screen")
        for command in [LauncherResult.sleep, .lockScreen] {
            XCTAssertNotEqual(LauncherResult.application(app(command.name, id: command.id)).id, command.id)
        }
    }

    func testIdentitiesSeparateCommandsFromApplicationsEvenForMatchingNamesOrIDs() {
        let application = app("Update App Index", id: "command:update-index")
        let result = LauncherResult.application(application)
        XCTAssertEqual(result.id, "app:command:update-index")
        XCTAssertEqual(result.name, application.name)
        XCTAssertEqual(LauncherResult.updateIndex.id, "command:update-index")
        XCTAssertEqual(LauncherResult.updateIndex.name, "Update App Index")
        XCTAssertNotEqual(result.id, LauncherResult.updateIndex.id)
        XCTAssertNotEqual(LauncherResult.application(app("command:update-index")).id, LauncherResult.updateIndex.id)
        XCTAssertEqual(Set(LauncherResult.search([application], query: "index")).count, 2)
    }
}
