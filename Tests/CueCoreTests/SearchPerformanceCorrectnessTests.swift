import Foundation
import XCTest
import CueCore

final class SearchPerformanceCorrectnessTests: XCTestCase {
    private func app(_ name: String, path: String? = nil) -> IndexedApplication {
        IndexedApplication(name: name, url: URL(fileURLWithPath: path ?? "/Tests/\(name).app"))
    }

    func testLaterWordPrefixStillOutranksEarlierSubstring() {
        let applications = [app("Xcode"), app("Xcode Code"), app("Code"), app("Decoder")]
        XCTAssertEqual(SearchEngine.search(applications, query: "code").map(\.name),
                       ["Code", "Xcode Code", "Xcode", "Decoder"])
    }

    func testASCIIAndUnicodeNamesKeepTheSameRankingRules() {
        let applications = [app("我的音樂"), app("音樂播放器"), app("音樂"), app("我的 音樂")]
        XCTAssertEqual(SearchEngine.search(applications, query: "音樂").map(\.name),
                       ["音樂", "音樂播放器", "我的 音樂", "我的音樂"])
        XCTAssertEqual(SearchEngine.search([app("ＡＢＣ Editor"), app("ABC")], query: "ａｂｃ").map(\.name),
                       ["ABC", "ＡＢＣ Editor"])
    }

    func testCombiningCharactersAndEmojiRemainSearchable() {
        let applications = [app("Cafe\u{301} Pro"), app("Café"), app("😀 Tools")]
        XCTAssertEqual(SearchEngine.search(applications, query: "CAFÉ").map(\.name),
                       ["Café", "Cafe\u{301} Pro"])
        XCTAssertEqual(SearchEngine.search(applications, query: "😀").map(\.name), ["😀 Tools"])
    }

    func testPunctuationInitialsAndSpacedFuzzyQueries() {
        let applications = [app("Visual-Studio_Code"), app("Terminal"), app("A Visual Studio Code")]
        XCTAssertEqual(SearchEngine.search(applications, query: "v s c").map(\.name),
                       ["Visual-Studio_Code", "A Visual Studio Code"])
        XCTAssertEqual(SearchEngine.search(applications, query: "t r m").map(\.name), ["Terminal"])
        XCTAssertEqual(SearchEngine.search(applications, query: "studio_code").map(\.name),
                       ["Visual-Studio_Code"])
    }

    func testDenseTiesRemainDeterministicAcrossInputOrder() {
        let applications = (0..<64).map { index in
            app("Editor", path: String(format: "/Tests/%02d.app", index))
        }
        let expected = applications.map(\.id)
        for query in ["editor", "edi", "dit", "edr", ""] {
            XCTAssertEqual(SearchEngine.search(applications.reversed(), query: query).map(\.id), expected, query)
        }
    }

    func testEmptyApplicationNamesAndLongQueriesDoNotProduceMatches() {
        XCTAssertEqual(SearchEngine.search([app(""), app("a")], query: "a very long query"), [])
        XCTAssertEqual(SearchEngine.search([app(""), app("a")], query: "a").map(\.name), ["a"])
    }
}
