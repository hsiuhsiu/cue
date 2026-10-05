import CueCore
import Foundation
import XCTest

final class FileSearchTests: XCTestCase {
    func testModeRequiresExplicitASCIIShortcut() {
        for input in ["", "f", "finder", "F", " f report", "f\treport", "f\u{3000}report", "ff report"] {
            XCTAssertNil(FileSearchQuery.parse(input), input)
        }
        XCTAssertEqual(FileSearchQuery.parse("f report")?.term, "report")
        XCTAssertEqual(FileSearchQuery.parse("F 報告")?.term, "報告")
        XCTAssertEqual(FileSearchQuery.parse("f   annual report  ")?.term, "annual report")
        XCTAssertEqual(FileSearchQuery.parse("f *?.txt")?.term, "*?.txt")
    }

    func testEmptyPrefixIsAFileModeWithoutAnIndexRequest() throws {
        for input in ["f ", "F   ", "f \n\t"] {
            let query = try XCTUnwrap(FileSearchQuery.parse(input))
            XCTAssertFalse(query.canSearch)
            XCTAssertFalse(query.isTooLong)
            XCTAssertEqual(query.term, "")
        }
    }

    func testOversizeInputIsRejectedBeforeCopyingOrTrimming() throws {
        let maximum = FileSearchQuery.maximumTermUTF8Count
        XCTAssertTrue(try XCTUnwrap(FileSearchQuery.parse("f " + String(repeating: "a", count: maximum))).canSearch)
        for suffix in [String(repeating: "a", count: maximum + 1),
                       String(repeating: " ", count: maximum + 1),
                       String(repeating: "🧑", count: maximum / 4 + 1),
                       String(repeating: "\u{0301}", count: 200_000)] {
            let query = try XCTUnwrap(FileSearchQuery.parse("f " + suffix))
            XCTAssertTrue(query.isTooLong)
            XCTAssertFalse(query.canSearch)
            XCTAssertTrue(query.term.isEmpty)
        }
    }

    func testRankingIsLiteralCaseInsensitiveAndStable() {
        let candidates = [file("a report.txt"), file("report-z.pdf"), file("Report"),
                          file("report-a.pdf"), file("irrelevant.txt"), file("Report")]
        let ranked = FileSearchRanking.results(from: candidates, term: "report", limit: 9)
        XCTAssertEqual(ranked.map(\.name), ["Report", "report-a.pdf", "report-z.pdf", "a report.txt"])
        XCTAssertEqual(ranked, FileSearchRanking.results(from: Array(candidates.reversed()), term: "REPORT", limit: 9))
        XCTAssertEqual(FileSearchRanking.results(from: [file("Café.txt")], term: "cafe", limit: 9).count, 1)
        XCTAssertEqual(FileSearchRanking.results(from: [file("a*b?.txt"), file("anything.txt")], term: "*b?", limit: 9).map(\.name), ["a*b?.txt"])
    }

    func testLimitAndPathIdentity() {
        let candidates = (0..<100).map { file("report-\($0).txt") }
        XCTAssertEqual(FileSearchRanking.results(from: candidates, term: "report", limit: 100).count, 9)
        XCTAssertEqual(FileSearchRanking.results(from: candidates, term: "report", limit: 2).count, 2)
        XCTAssertTrue(FileSearchRanking.results(from: candidates, term: "report", limit: 0).isEmpty)
        XCTAssertTrue(FileSearchRanking.results(from: candidates, term: "", limit: 9).isEmpty)
        let first = file("report.txt", folder: "/Users/fixture/Documents")
        let second = file("report.txt", folder: "/Users/fixture/Desktop")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(first.id.hasPrefix("file:"))
        XCTAssertEqual(first.parentPath, "/Users/fixture/Documents")
    }

    func testDataVolumeAliasesUseTheSameOpeningURLAndIdentity() {
        let ordinary = file("report.txt")
        let backing = file("report.txt", folder: "/System/Volumes/Data/Users/fixture/Documents")
        XCTAssertEqual(backing, ordinary)
        XCTAssertEqual(backing.url.path, "/Users/fixture/Documents/report.txt")
        XCTAssertEqual(backing.parentPath, "/Users/fixture/Documents")
        XCTAssertEqual(FileSearchRanking.results(from: [backing, ordinary], term: "report", limit: 9), [ordinary])
        XCTAssertEqual(FileSearchRanking.results(from: [ordinary, backing], term: "report", limit: 9), [ordinary])
        for path in ["/Users", "/Applications", "/Volumes",
                     "/Applications/Fixture.app", "/Volumes/External/report.txt",
                     "/Users/fixture/Library/Mobile Documents/com~apple~CloudDocs/report.txt",
                     "/Users/fixture/Library/CloudStorage/FixtureDrive/report.txt"] {
            XCTAssertEqual(FileSearchRanking.canonicalPath("/System/Volumes/Data" + path), path)
            XCTAssertTrue(FileSearchRanking.isUserFacingPath("/System/Volumes/Data" + path), path)
        }
    }

    func testDataVolumeAliasesDoNotBypassVisibilityFilters() {
        for path in ["/System/Library/report.txt", "/Library/report.txt", "/private/report.txt",
                     "/Users/fixture/Library/report.txt", "/Users/fixture/.hidden/report.txt",
                     "/Users/fixture/Documents/.report.txt", "/Applications/Fixture.app/Contents/report.txt"] {
            let backingPath = "/System/Volumes/Data" + path
            XCTAssertFalse(FileSearchRanking.isUserFacingPath(backingPath), backingPath)
        }
        for path in ["/System/Volumes/Data", "/System/Volumes/Data/Custom/report.txt",
                     "/System/Volumes/DataOther/Users/fixture/report.txt",
                     "/System/Volumes/Data/UsersOther/report.txt",
                     "/Volumes/Other/System/Volumes/Data/Users/fixture/report.txt"] {
            XCTAssertEqual(FileSearchRanking.canonicalPath(path), path)
        }
        let external = "/Volumes/Other/System/Volumes/Data/Users/fixture/report.txt"
        XCTAssertTrue(FileSearchRanking.isUserFacingPath(external))
    }

    func testBoundedRankingMatchesFullSortForMetadataBatches() {
        // Cover the maximum three 128-item metadata batches, including many
        // overlapping results, case/diacritic ties, exact matches and paths.
        let names = ["report", "REPORT", "Report", "report.txt", "report-a.pdf",
                     "Report-é.pdf", "report-e.pdf", "a report.txt", "other.txt",
                     "報告.txt", "年度報告.txt", "Café.txt", "cafe.txt", "a*b?.txt"]
        var candidates = (0..<384).map { index in
            file(names[index % names.count], folder: "/Users/fixture/Documents/\(index % 17)")
        }
        candidates += [file("report", folder: "/System"), file("report", folder: "/Users/fixture/.hidden")]
        for term in ["report", "REPORT", "cafe", "報告", "*b?", "missing"] {
            for limit in [1, 2, 9, 99] {
                let expected = fullSortReference(candidates, term: term, limit: limit)
                for offset in [0, 1, 97, 230] {
                    let rotated = Array(candidates[offset...]) + Array(candidates[..<offset])
                    XCTAssertEqual(FileSearchRanking.results(from: rotated, term: term, limit: limit), expected,
                                   "\(term), \(limit) rows, rotation \(offset)")
                    XCTAssertEqual(FileSearchRanking.results(from: Array(rotated.reversed()), term: term, limit: limit), expected)
                }
            }
        }
    }

    private func fullSortReference(_ candidates: [FileSearchResult], term: String, limit: Int) -> [FileSearchResult] {
        let locale = Locale(identifier: "en_US_POSIX")
        func folded(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        }
        let needle = folded(term)
        var seen = Set<String>()
        return candidates.compactMap { result -> (FileSearchResult, Int, String)? in
            guard result.url.isFileURL, FileSearchRanking.isUserFacingPath(result.url.path),
                  seen.insert(result.id).inserted else { return nil }
            let name = folded(result.name)
            guard name.contains(needle) else { return nil }
            return (result, name == needle ? 0 : (name.hasPrefix(needle) ? 1 : 2), name)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            if lhs.0.name != rhs.0.name { return lhs.0.name < rhs.0.name }
            return lhs.0.url.path < rhs.0.url.path
        }.prefix(min(limit, 9)).map(\.0)
    }

    func testSystemHiddenAndBundleResourcesAreExcluded() {
        for path in ["/System/report.txt", "/Library/report.txt", "/usr/report.txt",
                     "/private/report.txt", "/Users/fixture/Library/report.txt",
                     "/Users/fixture/.secrets/report.txt", "/Users/fixture/.report.txt",
                     "/Applications/Fixture.app/Contents/report.txt", "report.txt"] {
            XCTAssertFalse(FileSearchRanking.isUserFacingPath(path), path)
        }
        for path in ["/Users/fixture/Documents/report.txt", "/Volumes/Data/report.txt",
                     "/Users/fixture/Documents/Library/report.txt", "/Applications/Fixture.app",
                     "/Users/fixture/Library/Mobile Documents/com~apple~CloudDocs/report.txt",
                     "/Users/fixture/Library/CloudStorage/FixtureDrive/report.txt"] {
            XCTAssertTrue(FileSearchRanking.isUserFacingPath(path), path)
        }
    }

    private func file(_ name: String, folder: String = "/Users/fixture/Documents") -> FileSearchResult {
        FileSearchResult(url: URL(fileURLWithPath: folder).appendingPathComponent(name), name: name, parentPath: folder)
    }
}
