import Foundation
import XCTest
import CueCore

final class EmojiCatalogTests: XCTestCase {
    private static let loaded = Result { try EmojiCatalog(data: Data(contentsOf: resourceURL)) }
    private static var resourceURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Cue/Resources/EmojiCatalog.json")
    }

    func testBundledRepertoireHasUniqueLocalizedFullyQualifiedEntries() throws {
        let catalog = try Self.loaded.get()
        let entries = catalog.search("", limit: Int.max)
        XCTAssertEqual(catalog.count, 3_655)
        XCTAssertEqual(entries.count, catalog.count)
        XCTAssertEqual(Set(entries.map(\.id)).count, catalog.count)
        XCTAssertTrue(entries.allSatisfy { !$0.name.isEmpty && !$0.traditionalName.isEmpty && $0.emoji.count == 1 })
        XCTAssertTrue(entries.allSatisfy { $0.name != $0.traditionalName })
        XCTAssertEqual(catalog.search("🐦‍⬛").first?.traditionalName, "黑鳥")
        XCTAssertEqual(catalog.search("🫨").first?.emoji, "🫨") // Added in Emoji 15.0.
        XCTAssertTrue(catalog.search("🙂‍↔️").isEmpty) // Emoji 15.1 is intentionally excluded.
    }

    func testEmptyQueryHasDeterministicCommonEmojiAndRespectsLimit() throws {
        let catalog = try Self.loaded.get()
        let expected = ["😀", "😂", "❤️", "👍", "🎉", "🙏", "🔥", "✅", "😊"]
        XCTAssertEqual(catalog.search("").map(\.emoji), expected)
        XCTAssertEqual(catalog.search(" \n\t").map(\.emoji), expected)
        XCTAssertEqual(catalog.search("", limit: 3).map(\.emoji), Array(expected.prefix(3)))
        XCTAssertTrue(catalog.search("", limit: 0).isEmpty)
        XCTAssertTrue(catalog.search("smile", limit: -1).isEmpty)
    }

    func testPracticalEnglishAndTraditionalChineseSearches() throws {
        let catalog = try Self.loaded.get()
        let cases: [(String, String)] = [
            ("smile", "😊"), ("happy", "😀"), ("笑", "😀"), ("開心", "😀"),
            ("heart", "❤️"), ("愛心", "❤️"), ("thumbs up", "👍"), ("讚", "👍"),
            ("party", "🎉"), ("慶祝", "🎉"), ("coffee", "☕"), ("咖啡", "☕"),
            ("Taiwan", "🇹🇼"), ("台灣", "🇹🇼"), ("臺灣", "🇹🇼"),
        ]
        for (query, emoji) in cases {
            XCTAssertTrue(catalog.search(query).contains { $0.emoji == emoji }, "Missing \(emoji) for \(query)")
        }
    }

    func testAliasesCaseWidthAndWhitespaceNormalizeWithoutChangingCopiedEmoji() throws {
        let catalog = try Self.loaded.get()
        XCTAssertEqual(catalog.search(":smile:"), catalog.search("smile"))
        XCTAssertEqual(catalog.search("  :THUMBS_UP: \n"), catalog.search("thumbs up"))
        XCTAssertEqual(catalog.search("thumbs-up"), catalog.search("thumbs up"))
        XCTAssertEqual(catalog.search("ＣＯＦＦＥＥ"), catalog.search("coffee"))
        XCTAssertEqual(catalog.search("party   popper").first?.emoji, "🎉")
        XCTAssertTrue(catalog.search(":__-").isEmpty)
    }

    func testExactEmojiReturnsItsOriginalFullyQualifiedSequence() throws {
        let catalog = try Self.loaded.get()
        for emoji in ["👍🏽", "👩🏿‍💻", "👨‍👩‍👧‍👦", "🇹🇼", "❤️", "1️⃣"] {
            let results = catalog.search(" \(emoji)\n")
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.emoji.unicodeScalars.map(\.value), emoji.unicodeScalars.map(\.value))
            XCTAssertEqual(results.first?.id, emoji)
        }
        XCTAssertEqual(catalog.search("❤").first?.emoji, "❤️")
        XCTAssertEqual(catalog.search("☕️").first?.emoji, "☕")
    }

    func testTextPresentationVariantsFindTheSameFullyQualifiedEmoji() throws {
        let catalog = try Self.loaded.get()
        for (query, expected) in [("❤︎", "❤️"), ("☕︎", "☕"), ("❤︎‍🔥", "❤️‍🔥"),
                                  ("1\u{FE0E}\u{20E3}", "1️⃣"), ("☝︎🏽", "☝🏽")] {
            let results = catalog.search(query)
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.emoji.unicodeScalars.map(\.value),
                           expected.unicodeScalars.map(\.value), query)
        }
        XCTAssertTrue(catalog.search("\u{FE0E}").isEmpty)
        XCTAssertThrowsError(try fixture([
            EmojiEntry(emoji: "❤︎", name: "heart", traditionalName: "心"),
            EmojiEntry(emoji: "❤️", name: "red heart", traditionalName: "愛心"),
        ]))
    }

    func testCommonFormsPrecedeSkinToneVariantsAndTonesRemainSearchable() throws {
        let catalog = try Self.loaded.get()
        XCTAssertEqual(catalog.search("thumbs up").first?.emoji, "👍")
        for query in ["hand", "person", "woman", "man"] {
            XCTAssertTrue(catalog.search(query).allSatisfy { entry in
                !entry.emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
            }, "Tone variants crowded out base emoji for \(query)")
        }
        XCTAssertEqual(catalog.search("thumbs up medium skin tone").first?.emoji, "👍🏽")
        XCTAssertEqual(catalog.search("讚 白皮膚").first?.emoji, "👍🏻")
        XCTAssertTrue(catalog.search("light skin tone").allSatisfy { $0.emoji.unicodeScalars.contains("🏻") })
    }

    func testTaiwanHeartAliasIncludesColoredAndDecoratedHeartsBeforeToneVariants() throws {
        let catalog = try Self.loaded.get()
        let all = Set(catalog.search("愛心", limit: Int.max).map(\.emoji))
        for emoji in ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "🩷", "🩵", "🩶", "💝", "❤️‍🔥", "❤️‍🩹"] {
            XCTAssertTrue(all.contains(emoji), "Missing heart: \(emoji)")
        }
        XCTAssertTrue(catalog.search("愛心").allSatisfy { entry in
            !entry.emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
        })
    }

    func testAllTermsCanMatchAcrossNamesAndKeywords() throws {
        let catalog = try Self.loaded.get()
        XCTAssertEqual(catalog.search("coffee 熱飲").first?.emoji, "☕")
        XCTAssertEqual(catalog.search("Taiwan 旗子").first?.emoji, "🇹🇼")
        XCTAssertTrue(catalog.search("coffee taiwan").isEmpty)
        XCTAssertTrue(catalog.search("noSuchEmoji_347194").isEmpty)
        XCTAssertTrue(catalog.search(String(repeating: "a", count: 1_025)).isEmpty)
    }

    func testExactNamesThenKeywordsRankFirstAndCommonFormsBreakEqualRanks() throws {
        let catalog = try fixture([
            EmojiEntry(emoji: "😀", name: "first face", traditionalName: "一", keywords: ["coffee"]),
            EmojiEntry(emoji: "😁", name: "coffee bean", traditionalName: "二"),
            EmojiEntry(emoji: "☕", name: "coffee", traditionalName: "咖啡"),
            EmojiEntry(emoji: "😂", name: "another face", traditionalName: "三", keywords: ["coffee"]),
        ])
        XCTAssertEqual(catalog.search("coffee").map(\.emoji), ["☕", "😀", "😂", "😁"])
        XCTAssertEqual(catalog.search("coffee", limit: 2).map(\.emoji), ["☕", "😀"])
    }

    func testInvalidOrUnsupportedCatalogFailsInsteadOfSilentlyShowingPartialData() throws {
        XCTAssertThrowsError(try EmojiCatalog(data: Data("not json".utf8)))
        XCTAssertThrowsError(try fixture([]))
        XCTAssertThrowsError(try fixture([EmojiEntry(emoji: "😀", name: "", traditionalName: "笑")]))
        XCTAssertThrowsError(try fixture([EmojiEntry(emoji: "😀", name: "smile", traditionalName: "")]))
        XCTAssertThrowsError(try fixture([
            EmojiEntry(emoji: "❤", name: "heart", traditionalName: "心"),
            EmojiEntry(emoji: "❤️", name: "red heart", traditionalName: "愛心"),
        ]))
        let data = try Data(contentsOf: Self.resourceURL)
        let source = String(decoding: data, as: UTF8.self)
        for (from, to) in [("\"formatVersion\":1", "\"formatVersion\":2"),
                           ("\"unicodeVersion\":\"15.0\"", "\"unicodeVersion\":\"16.0\"")] {
            XCTAssertThrowsError(try EmojiCatalog(data: Data(source.replacingOccurrences(of: from, with: to).utf8)))
        }
        XCTAssertThrowsError(try EmojiCatalog(data: Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1)))
    }

    func testOptimizedSearchBenchmarkReportsRealCatalogLatency() throws {
        let catalog = try Self.loaded.get()
        let queries = ["h", "hand", "face", "person", "smile", "heart", "thumbs up", "coffee", "笑", "愛心", "慶祝", "讚 白皮膚", "Taiwan", ":smile:", "noSuchEmoji"]
        var measurements: [Double] = []
        var count = 0
        for _ in 0..<20 {
            for query in queries {
                let start = DispatchTime.now().uptimeNanoseconds
                count += catalog.search(query).count
                measurements.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
        }
        measurements.sort()
        XCTAssertGreaterThan(count, 0)
        print(String(format: "Emoji catalog benchmark: %d entries, %d searches, median %.3f ms, p95 %.3f ms, max %.3f ms",
                     catalog.count, measurements.count, measurements[measurements.count / 2],
                     measurements[Int(Double(measurements.count) * 0.95)], measurements.last!))
    }

    private func fixture(_ entries: [EmojiEntry]) throws -> EmojiCatalog {
        let records = entries.map { ["emoji": $0.emoji, "name": $0.name, "traditionalName": $0.traditionalName, "keywords": $0.keywords] as [String: Any] }
        return try EmojiCatalog(data: JSONSerialization.data(withJSONObject: [
            "formatVersion": 1, "unicodeVersion": "15.0", "cldrVersion": "42", "entries": records,
        ]))
    }
}
