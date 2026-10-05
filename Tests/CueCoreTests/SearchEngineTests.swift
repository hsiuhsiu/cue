import Foundation
import XCTest
import CueCore

final class SearchEngineTests: XCTestCase {
    func testQueryLimitCountsBytesBeforeUnicodeFoldingOrMatching() {
        let limit = SearchEngine.maximumQueryUTF8Length
        XCTAssertTrue(SearchEngine.acceptsQuery(String(repeating: "a", count: limit)))
        XCTAssertFalse(SearchEngine.acceptsQuery(String(repeating: "a", count: limit + 1)))
        XCTAssertTrue(SearchEngine.acceptsQuery(String(repeating: "文", count: limit / 3)))
        XCTAssertFalse(SearchEngine.acceptsQuery(String(repeating: "文", count: limit / 3 + 1)))
        let longCluster = "a" + String(repeating: "\u{301}", count: 10_000)
        XCTAssertFalse(SearchEngine.acceptsQuery(longCluster))
        XCTAssertTrue(SearchEngine.search([app("a")], query: longCluster).isEmpty,
                      "A huge cluster must not fold down to an app match on the input thread")
        XCTAssertTrue(SearchEngine.search([app("a")], query: String(repeating: " ", count: limit + 1)).isEmpty)
        XCTAssertEqual(names([app("Café")], query: "cafe"), ["Café"])
    }

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

    func testASCIISubstringsKeepLiteralPositionsAndOrdering() {
        // The leading digit prevents fuzzy word-initial matching, so every hit
        // must have exactly the same literal substring as Foundation finds.
        let spellings = ["0ababa", "0aab", "0babb", "0bbbb", "0abcabc", "0cab", "0aaab", "0ab"]
        let applications = spellings.map { app($0) }
        for query in ["a", "ab", "bab", "abc", "bb", "aaaa", "cabc", "ababa", "ababaX"] {
            let expected = spellings.compactMap { name -> (String, Int)? in
                guard let range = name.range(of: query.lowercased()) else { return nil }
                return (name, name.distance(from: name.startIndex, to: range.lowerBound))
            }.sorted { left, right in
                if left.1 != right.1 { return left.1 < right.1 }
                if left.0.count != right.0.count { return left.0.count < right.0.count }
                return left.0 < right.0
            }.map(\.0)
            XCTAssertEqual(names(applications, query: query), expected, query)
            XCTAssertEqual(names(applications.reversed(), query: query), expected, query)
        }
    }

    func testASCIIAccelerationPreservesUnicodeAndWidthFolding() {
        let applications = [app("工具 Café Editor"), app("０Ｃａｆｅ"), app("0café"), app("版本工具")]
        XCTAssertEqual(names(applications, query: "cafe"), ["工具 Café Editor", "0café", "０Ｃａｆｅ"])
        XCTAssertEqual(names(applications, query: "工具"), ["工具 Café Editor", "版本工具"])
        XCTAssertEqual(names(applications, query: "版本"), ["版本工具"])
        XCTAssertEqual(names([app("0한글工具")], query: "\u{1112}\u{1161}\u{11AB}글"), ["0한글工具"])
    }

    func testLongASCIISubstringsKeepGeneralMatchingSemantics() {
        let applications = [app("0" + String(repeating: "a", count: 700) + "bc")]
        XCTAssertEqual(names(applications, query: String(repeating: "a", count: 65) + "bc"),
                       applications.map(\.name))
        XCTAssertEqual(names(applications, query: "abc"), applications.map(\.name))
        XCTAssertEqual(names(applications, query: String(repeating: "a", count: 65) + "bd"), [])
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
