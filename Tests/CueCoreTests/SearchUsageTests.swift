import Foundation
import XCTest
import CueCore

final class SearchUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func app(_ name: String) -> IndexedApplication {
        IndexedApplication(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    private func record(_ application: IndexedApplication, query: String, count: Int = 1,
                        at date: Date, in usage: inout SearchUsage) {
        for _ in 0..<count {
            usage.record(resultID: LauncherResult.application(application).id, query: query, at: date)
        }
    }

    func testNoHistoryPreservesEveryExistingRankingAndEmptyQueryBehavior() {
        let applications = [app("Code Zebra"), app("Code"), app("Code Alpha"), app("Xcode"), app("Visual Studio Code")]
        let usage = SearchUsage().snapshot(at: now)
        for query in ["code", "co", "vsc", "computer", "電腦", "", " \n\t "] {
            XCTAssertEqual(LauncherResult.search(applications, query: query, usage: usage),
                           LauncherResult.search(applications, query: query))
        }
        var learned = SearchUsage()
        record(applications[0], query: "code", at: now, in: &learned)
        XCTAssertTrue(LauncherResult.search(applications, query: "", usage: learned.snapshot(at: now)).isEmpty)
    }

    func testRememberedChoiceWinsWithinItsCategoryRegardlessOfIndexOrder() {
        let applications = [app("Code A"), app("Code Z Longer")]
        var usage = SearchUsage()
        record(applications[1], query: "code", at: now, in: &usage)
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(SearchEngine.search(applications, query: "code", usage: snapshot), applications.reversed())
        XCTAssertEqual(SearchEngine.search(applications.reversed(), query: "code", usage: snapshot), applications.reversed())
    }

    func testQueryPreferenceOutranksGeneralPopularityAndNormalizesTheQuery() {
        let applications = [app("Code A"), app("Code Z Longer")]
        var usage = SearchUsage()
        record(applications[0], query: "code", count: 20, at: now, in: &usage)
        record(applications[1], query: " \tＣＯ\n ", at: now, in: &usage)
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(SearchEngine.search(applications, query: "co", usage: snapshot).first, applications[1])
        XCTAssertEqual(SearchEngine.search(applications, query: "CODE", usage: snapshot).first, applications[0])
        XCTAssertEqual(usage.queryCount, 2)
    }

    func testFrequencyHelpsForAQueryWithoutItsOwnHistory() {
        let applications = [app("Code A"), app("Code Z Longer")]
        var usage = SearchUsage()
        record(applications[0], query: "code a", at: now, in: &usage)
        record(applications[1], query: "code z", count: 3, at: now, in: &usage)
        XCTAssertEqual(SearchEngine.search(applications, query: "co", usage: usage.snapshot(at: now)).first, applications[1])
    }

    func testRecentUseCanOvertakeOlderFrequentUse() {
        let applications = [app("Code A"), app("Code Z Longer")]
        var usage = SearchUsage()
        record(applications[0], query: "code a", count: 4, at: now.addingTimeInterval(-70 * 86_400), in: &usage)
        record(applications[1], query: "code z", at: now, in: &usage)
        XCTAssertEqual(SearchEngine.search(applications, query: "co", usage: usage.snapshot(at: now)).first, applications[1])
    }

    func testExactAndStrongerTextMatchesRemainAheadOfFrequentWeakerMatches() {
        let applications = [app("Code"), app("Code Pro"), app("Visual Studio Code"), app("Xcode")]
        var usage = SearchUsage()
        record(applications[3], query: "code", count: 100, at: now, in: &usage)
        record(applications[2], query: "code", count: 50, at: now, in: &usage)
        record(applications[1], query: "code", count: 20, at: now, in: &usage)
        XCTAssertEqual(SearchEngine.search(applications.reversed(), query: "code", usage: usage.snapshot(at: now)), applications)
    }

    func testHistoryCannotIntroduceUnmatchedApplicationsOrCommands() {
        let applications = [app("Safari"), app("Terminal")]
        var usage = SearchUsage()
        record(applications[1], query: "saf", count: 100, at: now, in: &usage)
        usage.record(resultID: LauncherResult.lockScreen.id, query: "saf", at: now)
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(LauncherResult.search(applications, query: "saf", usage: snapshot), [.application(applications[0])])
        XCTAssertTrue(LauncherResult.search(applications, query: "unrelated", usage: snapshot).isEmpty)
    }

    func testCommandsLearnWithinTheirExistingGroupWithoutCrowdingSingleLetters() {
        let application = app("Computer")
        var usage = SearchUsage()
        usage.record(resultID: LauncherResult.lockScreen.id, query: "computer", at: now)
        record(application, query: "computer", count: 100, at: now, in: &usage)
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(LauncherResult.search([application], query: "computer", usage: snapshot),
                       [.lockScreen, .sleep, .application(application)])
        XCTAssertEqual(LauncherResult.search([], query: "l", usage: snapshot), [])
    }

    func testIdenticalScoresKeepOriginalStableTies() {
        let applications = [app("Code Zebra"), app("Code Alpha")]
        var usage = SearchUsage()
        for application in applications { record(application, query: "code", at: now, in: &usage) }
        XCTAssertEqual(SearchEngine.search(applications, query: "code", usage: usage.snapshot(at: now)),
                       SearchEngine.search(applications, query: "code"))
    }

    func testSnapshotsRemainImmutableWhenNewChoicesAreRecorded() {
        let applications = [app("Code A"), app("Code Z Longer")]
        var usage = SearchUsage()
        let before = usage.snapshot(at: now)
        record(applications[1], query: "code", at: now, in: &usage)
        XCTAssertEqual(SearchEngine.search(applications, query: "code", usage: before).first, applications[0])
        XCTAssertEqual(SearchEngine.search(applications, query: "code", usage: usage.snapshot(at: now)).first, applications[1])
    }

    func testVeryOldPreferencesFadeBackToTextRanking() {
        let applications = [app("Code A"), app("Code Z Longer")]
        var usage = SearchUsage()
        record(applications[1], query: "code", at: now.addingTimeInterval(-365 * 86_400), in: &usage)
        XCTAssertEqual(usage.snapshot(at: now), .empty)
        XCTAssertEqual(SearchEngine.search(applications, query: "code", usage: usage.snapshot(at: now)), applications)
    }

    func testInvalidOrOversizedInputsDoNotConsumeStorage() {
        var usage = SearchUsage()
        for query in ["", " \n\t", String(repeating: "a", count: SearchUsage.maximumQueryBytes + 1),
                      String(repeating: "字", count: SearchUsage.maximumQueryBytes)] {
            usage.record(resultID: "app:valid", query: query, at: now)
        }
        for id in ["", String(repeating: "a", count: SearchUsage.maximumResultIDBytes + 1)] {
            usage.record(resultID: id, query: "valid", at: now)
        }
        usage.record(resultID: "app:valid", query: "valid", at: Date(timeIntervalSince1970: .nan))
        XCTAssertEqual(usage.resultCount, 0)
        XCTAssertEqual(usage.queryCount, 0)
    }

    func testBoundedHistoryKeepsRecentChoicesAndRoundTrips() throws {
        var usage = SearchUsage()
        for index in 0..<(SearchUsage.maximumResults + 64) {
            usage.record(resultID: "app:\(index)", query: "query \(index)", at: now.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(usage.resultCount, SearchUsage.maximumResults)
        XCTAssertEqual(usage.queryCount, SearchUsage.maximumQueries)
        let encoded = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(SearchUsage.self, from: encoded)
        XCTAssertEqual(decoded, usage)
        XCTAssertEqual(decoded.snapshot(at: now), usage.snapshot(at: now))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let results = try XCTUnwrap(payload["results"] as? [[String: Any]])
        XCTAssertFalse(results.contains { ($0["id"] as? String) == "app:0" })
        XCTAssertTrue(results.contains { ($0["id"] as? String) == "app:\(SearchUsage.maximumResults + 63)" })
    }

    func testPerQueryChoicesAreBoundedAndNewestChoiceSurvives() throws {
        var usage = SearchUsage()
        for index in 0..<(SearchUsage.maximumResultsPerQuery + 10) {
            usage.record(resultID: "app:\(index)", query: "shared", at: now.addingTimeInterval(Double(index)))
        }
        let encoded = try JSONEncoder().encode(usage)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let queries = try XCTUnwrap(payload["queries"] as? [[String: Any]])
        XCTAssertEqual((queries.first?["selections"] as? [Any])?.count, SearchUsage.maximumResultsPerQuery)
        XCTAssertEqual(try JSONDecoder().decode(SearchUsage.self, from: encoded), usage)
    }

    func testDecodeDiscardsInvalidReferencesAndScores() throws {
        let payload: [String: Any] = [
            "results": [
                ["id": "app:valid", "usage": ["score": 1, "lastUsed": 0]],
                ["id": "app:invalid", "usage": ["score": -1, "lastUsed": 0]],
                ["id": "", "usage": ["score": 1, "lastUsed": 0]],
            ],
            "queries": [
                ["query": "  VALID  ", "selections": [
                    ["result": 0, "usage": ["score": 1, "lastUsed": 0]],
                    ["result": -1, "usage": ["score": 1, "lastUsed": 0]],
                    ["result": 999, "usage": ["score": 1, "lastUsed": 0]],
                    ["result": 1, "usage": ["score": 1, "lastUsed": 0]],
                ]],
                ["query": " ", "selections": [["result": 0, "usage": ["score": 1, "lastUsed": 0]]]],
            ],
        ]
        let decoded = try JSONDecoder().decode(SearchUsage.self, from: JSONSerialization.data(withJSONObject: payload))
        var expected = SearchUsage()
        expected.record(resultID: "app:valid", query: "valid", at: Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(decoded, expected)
    }

    func testMaximumLengthEscapedHistoryStaysWithinStorageBudget() throws {
        var usage = SearchUsage()
        let ids = (0..<SearchUsage.maximumResults).map { index in
            "app:\(index):" + String(repeating: "\u{01}", count: SearchUsage.maximumResultIDBytes - 12)
        }
        for id in ids { usage.record(resultID: id, query: "initial", at: now) }
        for index in 0..<SearchUsage.maximumQueries {
            let query = "q\(index)" + String(repeating: "\u{01}", count: SearchUsage.maximumQueryBytes - 8)
            for selection in 0..<SearchUsage.maximumResultsPerQuery {
                usage.record(resultID: ids[(index + selection) % ids.count], query: query, at: now)
            }
        }
        let encoded = try JSONEncoder().encode(usage)
        XCTAssertLessThan(encoded.count, 4 * 1_024 * 1_024)
        XCTAssertEqual(try JSONDecoder().decode(SearchUsage.self, from: encoded), usage)
    }
}
