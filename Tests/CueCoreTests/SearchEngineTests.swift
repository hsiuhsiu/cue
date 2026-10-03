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

    func testAlternateNamesFindCodeWithoutChangingNameIdentityOrReturningDuplicates() {
        let code = IndexedApplication(name: "Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                                      searchNames: ["Visual Studio Code", " CODE ", "Ｖｉｓｕａｌ　Ｓｔｕｄｉｏ　Ｃｏｄｅ", ""])
        for query in ["v", "vs", "vsc", "visual", "studio", "code", "Visual Studio Code"] {
            XCTAssertEqual(SearchEngine.search([code], query: query), [code], query)
        }
        XCTAssertEqual(code.name, "Code")
        XCTAssertEqual(code.id, "/Applications/Visual Studio Code.app")
    }

    func testBestAutomaticNameDeterminesRankIndependentlyOfNameOrder() {
        let code = IndexedApplication(name: "Code", url: URL(fileURLWithPath: "/Applications/Code.app"),
                                      searchNames: ["Visual Studio Code", "VS"])
        let reordered = IndexedApplication(name: "Code", url: code.url, searchNames: ["VS", "Visual Studio Code"])
        let prefix = app("VS Preview")
        XCTAssertEqual(names([prefix, code], query: "vs"), ["Code", "VS Preview"])
        XCTAssertEqual(names([prefix, reordered], query: "vs"), ["Code", "VS Preview"])
    }

    func testExactCustomAliasOverridesNamesAndUsageButPrefixUsesOrdinaryRanking() {
        let aliased = app("Code").withSearchAlias("Ｔｅｒｍ")
        let exact = app("Term")
        var usage = SearchUsage()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<100 {
            usage.record(resultID: LauncherResult.application(exact).id, query: "term", at: now)
        }
        XCTAssertEqual(SearchEngine.search([exact, aliased], query: "term", usage: usage.snapshot(at: now)),
                       [aliased, exact])
        XCTAssertEqual(names([aliased, app("Ter")], query: "ter"), ["Ter", "Code"])
        XCTAssertEqual(names([aliased], query: "erm"), [])
    }

    func testChangingAndRemovingAliasPreservesAutomaticNamesAndUsageIdentity() {
        let original = IndexedApplication(name: "Code", url: URL(fileURLWithPath: "/Applications/Code.app"),
                                          bundleIdentifier: "Com.Microsoft.VSCode", searchNames: ["Visual Studio Code"])
        let aliased = original.withSearchAlias("editor")
        XCTAssertEqual(aliased.searchAlias, "editor")
        XCTAssertEqual(aliased.aliasPreferenceID, "bundle:com.microsoft.vscode")
        XCTAssertEqual(aliased.id, original.id)
        XCTAssertEqual(LauncherResult.application(aliased).id, LauncherResult.application(original).id)
        XCTAssertEqual(SearchEngine.search([aliased], query: "editor"), [aliased])
        XCTAssertEqual(SearchEngine.search([aliased], query: "vsc"), [aliased])
        let changed = aliased.withSearchAlias("coding")
        XCTAssertEqual(SearchEngine.search([changed], query: "editor"), [])
        XCTAssertEqual(SearchEngine.search([changed], query: "coding"), [changed])
        XCTAssertEqual(aliased.withSearchAlias(nil), original)
        XCTAssertEqual(aliased.withSearchAlias("  \n  "), original)
        let unnamed = IndexedApplication(id: "custom-id", name: "Example",
                                         url: URL(fileURLWithPath: "/Applications/Utilities/../Example.app"))
        XCTAssertEqual(unnamed.aliasPreferenceID, "path:/Applications/Example.app")
    }
}
