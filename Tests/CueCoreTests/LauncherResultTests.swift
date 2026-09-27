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

    func testEmptyQueryAppendsCommandAfterAlphabeticalApplications() {
        let applications = [app("Terminal"), app("Safari")]
        XCTAssertEqual(LauncherResult.search(applications, query: "\n \t"), [
            .application(applications[1]), .application(applications[0]), .updateIndex,
        ])
        XCTAssertEqual(LauncherResult.search([], query: ""), [.updateIndex])
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
