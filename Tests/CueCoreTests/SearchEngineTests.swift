import Foundation
import XCTest
import CueCore

final class SearchEngineTests: XCTestCase {
    private func app(_ name: String, path: String? = nil) -> IndexedApplication {
        IndexedApplication(
            name: name,
            url: URL(fileURLWithPath: path ?? "/Applications/\(name).app")
        )
    }

    private func names(_ applications: [IndexedApplication], query: String) -> [String] {
        SearchEngine.search(applications, query: query).map(\.name)
    }

    func testExactOutranksPrefix() {
        XCTAssertEqual(names([app("Terminal Pro"), app("Terminal")], query: "Terminal"),
                       ["Terminal", "Terminal Pro"])
    }

    func testPrefixOutranksWordPrefixAndSubstring() {
        XCTAssertEqual(names([app("Xcode"), app("Visual Studio Code"), app("Code Editor")], query: "code"),
                       ["Code Editor", "Visual Studio Code", "Xcode"])
    }

    func testTerminalRanksStronglyForTerm() {
        XCTAssertEqual(names([app("iTerm"), app("Terminal"), app("Other Terminal")], query: "term"),
                       ["Terminal", "Other Terminal", "iTerm"])
    }

    func testCaseAndWhitespaceAreNormalized() {
        let applications = [app("Visual Studio Code"), app("Visual Studio Code Insiders")]
        XCTAssertEqual(names(applications, query: " \tVISUAL   studio\nCODE  "),
                       ["Visual Studio Code", "Visual Studio Code Insiders"])
        XCTAssertEqual(names([app("Safari")], query: "SAF"), ["Safari"])
    }

    func testAccentedNamesAreSearchableWithoutDiacritics() {
        XCTAssertEqual(names([app("Café")], query: "cafe"), ["Café"])
    }

    func testReasonableSubsequenceAndInitials() {
        let applications = [app("Terminal"), app("Safari"), app("Visual Studio Code"), app("Calendar")]
        XCTAssertEqual(names(applications, query: "trm"), ["Terminal"])
        XCTAssertEqual(names(applications, query: "sfr"), ["Safari"])
        XCTAssertEqual(names(applications, query: "vsc"), ["Visual Studio Code"])
    }

    func testSubstringOutranksFuzzyMatch() {
        XCTAssertEqual(names([app("Terminal"), app("MyTRM")], query: "trm"),
                       ["MyTRM", "Terminal"])
    }

    func testUnrelatedAndExcessivelySparseMatchesAreExcluded() {
        let applications = [app("Calendar"), app("Safari"), app("SabcdefghijklmnopqrstuvwxyzZ")]
        XCTAssertEqual(names(applications, query: "trm"), [])
        XCTAssertEqual(names(applications, query: "sz"), [])
        XCTAssertEqual(names(applications, query: "sfrr"), [])
    }

    func testEmptyQueriesSortAlphabetically() {
        let applications = [app("Terminal"), app("safari"), app("Calendar")]
        XCTAssertEqual(names(applications, query: "\n \t"), ["Calendar", "safari", "Terminal"])
        XCTAssertEqual(names([], query: ""), [])
    }

    func testRankingDoesNotDependOnIndexOrder() {
        let applications = [app("Code Zebra"), app("Code Alpha"), app("Xcode"), app("Visual Studio Code")]
        let expected = names(applications, query: "code")
        XCTAssertEqual(names(applications.reversed(), query: "code"), expected)
        XCTAssertEqual(names([applications[2], applications[0], applications[3], applications[1]], query: "code"), expected)
    }

    func testIdenticalNamesUseStablePathTieBreak() {
        let first = app("Safari", path: "/Applications/Safari.app")
        let second = app("Safari", path: "/Users/test/Applications/Safari.app")
        XCTAssertEqual(SearchEngine.search([second, first], query: "saf").map(\.id), [first.id, second.id])
        XCTAssertEqual(SearchEngine.search([second, first], query: "").map(\.id), [first.id, second.id])
    }

    func testDefaultIdentityUsesStandardizedBundlePath() {
        XCTAssertEqual(app("Example", path: "/CueTestApplications/Utilities/../Example.app").id,
                       "/CueTestApplications/Example.app")
    }
}
