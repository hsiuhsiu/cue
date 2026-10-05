import Foundation
import XCTest
import CueCore

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testExactDuplicatesKeepIdentityAndMoveToNewestWithoutTrimmingText() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await store.record(text: "  hello\n", retention: .forever, now: start)
        _ = try await store.record(text: "hello", retention: .forever, now: start.addingTimeInterval(1))
        let recopied = try await store.record(text: "  hello\n", retention: .forever, now: start.addingTimeInterval(2))

        XCTAssertEqual(recopied.map(\.text), ["  hello\n", "hello"])
        XCTAssertEqual(recopied.first?.id, first.first?.id)
        XCTAssertEqual(recopied.first?.copiedAt, start.addingTimeInterval(2))
        XCTAssertEqual(recopied.first?.preview, "hello")
        let loaded = try await ClipboardStore(fileURL: file).load(retention: .forever, now: start.addingTimeInterval(3))
        XCTAssertEqual(loaded, recopied)
    }

    func testRecopyRestartsRetentionAndExpirationIncludesExactBoundary() async throws {
        let (directory, _, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "keep", retention: .hour, now: start)
        let recopied = try await store.record(text: "keep", retention: .hour, now: start.addingTimeInterval(3_000))
        let stillPresent = try await store.prune(retention: .hour, now: start.addingTimeInterval(3_600))
        XCTAssertEqual(stillPresent, recopied)
        let expired = try await store.prune(retention: .hour, now: start.addingTimeInterval(6_600))
        XCTAssertTrue(expired.isEmpty)
    }

    func testDeletingOneEntryPersistsWithoutRemovingOthers() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await store.record(text: "delete", retention: .forever, now: start)
        _ = try await store.record(text: "keep", retention: .forever, now: start.addingTimeInterval(1))
        let removed = try await store.remove(id: try XCTUnwrap(first.first?.id))
        XCTAssertEqual(removed.map(\.text), ["keep"])
        let loaded = try await ClipboardStore(fileURL: file).load(retention: .forever, now: start.addingTimeInterval(2))
        XCTAssertEqual(loaded, removed)
    }

    func testClearCannotRestoreOldEntriesOnLaterCaptureOrReload() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "old", retention: .forever, now: start)
        try await store.clear()
        let empty = await store.search(query: "")
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        _ = try await store.record(text: "new", retention: .forever, now: start.addingTimeInterval(1))
        let loaded = try await ClipboardStore(fileURL: file).load(retention: .forever, now: start.addingTimeInterval(2))
        XCTAssertEqual(loaded.map(\.text), ["new"])
    }

    func testOfflineExpirationIsRemovedOnLoadAndCannotReturnUnderForever() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "expired offline", retention: .forever, now: start)
        let expired = try await ClipboardStore(fileURL: file).load(retention: .hour, now: start.addingTimeInterval(3_600))
        XCTAssertTrue(expired.isEmpty)
        let loaded = try await ClipboardStore(fileURL: file).load(retention: .forever, now: start.addingTimeInterval(3_601))
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSearchNormalizesCaseDiacriticsWidthWhitespaceAndPreservesRecency() async throws {
        let (directory, _, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "Café\n正體中文", retention: .forever, now: start)
        _ = try await store.record(text: "ＣＡＦＥ 正體中文 最新", retention: .forever, now: start.addingTimeInterval(1))
        let matches = await store.search(query: "  CAFE  正體中文 ")
        XCTAssertEqual(matches.map(\.text), ["ＣＡＦＥ 正體中文 最新", "Café\n正體中文"])
        let chinese = await store.search(query: "中文")
        XCTAssertEqual(chinese, matches)
        let missing = await store.search(query: "unrelated")
        XCTAssertTrue(missing.isEmpty)
    }

    func testSearchPreservesCanonicalUnicodeEmojiAndURLSubstringMatching() async throws {
        let (directory, _, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "Résumé Cafe\u{0301} 👩🏽‍💻 🇹🇼 正體中文 가나 https://example.invalid/Some-Path?q=1"
        _ = try await store.record(text: text, retention: .forever, now: start)
        for query in [
            "Re\u{0301}sume\u{0301} CAFÉ", "👩🏽‍💻", "🇹🇼 正體中文",
            "\u{1100}\u{1161}나", "EXAMPLE.INVALID/some-path?Q=1",
        ] {
            let matches = await store.search(query: query)
            XCTAssertEqual(matches.map(\.text), [text], "Expected canonical or literal match for \(query)")
        }
        let wrongEmoji = await store.search(query: "👩🏻‍💻")
        XCTAssertTrue(wrongEmoji.isEmpty)
        let longerNonmatch = await store.search(query: text + " missing suffix")
        XCTAssertTrue(longerNonmatch.isEmpty)
    }

    func testWhitespaceIsIgnoredAndPreviewIsBoundedWithoutChangingOriginal() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = try await store.record(text: " \n\t　", retention: .forever, now: start)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let text = " \n" + String(repeating: "字", count: 200) + "\t "
        let recorded = try await store.record(text: text, retention: .forever, now: start)
        XCTAssertEqual(recorded.first?.text, text)
        XCTAssertEqual(recorded.first?.preview, String(repeating: "字", count: 160) + "…")
    }

    func testPerEntryLimitUsesUTF8BytesAndRejectedCaptureDoesNotLoseHistory() async throws {
        let (directory, _, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "keep", retention: .forever, now: start)
        let oversized = String(repeating: "界", count: ClipboardStore.maximumEntryBytes / 3 + 1)
        do {
            _ = try await store.record(text: oversized, retention: .forever, now: start)
            XCTFail("Expected oversized capture to be rejected")
        } catch {
            XCTAssertEqual(error as? ClipboardStoreError, .entryTooLarge)
        }
        let remaining = await store.search(query: "")
        XCTAssertEqual(remaining.map(\.text), ["keep"])
    }

    func testPreviewDoesNotExposeHugeCombiningCharacterClustersToRendering() {
        let text = "a" + String(repeating: "\u{0301}", count: 5_000) + " end"
        let entry = ClipboardEntry(text: text, copiedAt: start)
        XCTAssertLessThanOrEqual(entry.preview.utf8.count, 1_027)
        XCTAssertEqual(entry.text, text)
    }

    func testTotalByteLimitEvictsOldestEntries() async throws {
        let (directory, _, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capacity = ClipboardStore.maximumTotalBytes / ClipboardStore.maximumEntryBytes
        var entries: [ClipboardEntry] = []
        for index in 0...capacity {
            let prefix = "\(index):"
            let text = prefix + String(repeating: "a", count: ClipboardStore.maximumEntryBytes - prefix.utf8.count)
            entries = try await store.record(text: text, retention: .forever, now: start.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(entries.count, capacity)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.text.utf8.count }, ClipboardStore.maximumTotalBytes)
        XCTAssertTrue(entries.first?.text.hasPrefix("\(capacity):") == true)
        XCTAssertFalse(entries.contains { $0.text.hasPrefix("0:") })
    }

    func testLoadEnforcesEntryCountDeduplicationAndPersistsTheRepair() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entries = (0..<(ClipboardStore.maximumEntries + 2)).map {
            ClipboardEntry(text: "entry \($0)", copiedAt: start.addingTimeInterval(Double($0)))
        }
        let duplicate = ClipboardEntry(text: "entry 501", copiedAt: start.addingTimeInterval(503))
        try write(entries: entries + [duplicate], to: file)
        let loaded = try await store.load(retention: .forever, now: start.addingTimeInterval(600))
        XCTAssertEqual(loaded.count, ClipboardStore.maximumEntries)
        XCTAssertEqual(loaded.first?.id, duplicate.id)
        XCTAssertFalse(loaded.contains { $0.text == "entry 0" || $0.text == "entry 1" })
        let reloaded = try await ClipboardStore(fileURL: file).load(retention: .forever, now: start.addingTimeInterval(600))
        XCTAssertEqual(loaded, reloaded)
    }

    func testLoadDropsOversizedAndEmptyRecordsAndClampsFutureTimestamp() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(entries: [
            ClipboardEntry(text: "future", copiedAt: start.addingTimeInterval(100_000)),
            ClipboardEntry(text: " \n ", copiedAt: start),
            ClipboardEntry(text: String(repeating: "a", count: ClipboardStore.maximumEntryBytes + 1), copiedAt: start),
        ], to: file)
        let loaded = try await store.load(retention: .hour, now: start)
        XCTAssertEqual(loaded.map(\.text), ["future"])
        XCTAssertEqual(loaded.first?.copiedAt, start)
        let expired = try await store.prune(retention: .hour, now: start.addingTimeInterval(3_600))
        XCTAssertTrue(expired.isEmpty)
    }

    func testSearchNoOpPruningAndUnknownDeletionDoNotRewriteFile() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "keep", retention: .forever, now: start)
        let marker = start.addingTimeInterval(-10)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: file.path)
        _ = await store.search(query: "KEEP")
        _ = try await store.prune(retention: .forever, now: start.addingTimeInterval(1))
        _ = try await store.remove(id: UUID())
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        XCTAssertEqual(modified, marker)
    }

    func testPruneSkipsUnchangedHistoryButExpiresAtBoundaryAfterRetentionChange() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "oldest", retention: .forever, now: start)
        let saved = try await store.record(text: "newest", retention: .forever, now: start.addingTimeInterval(60))
        let marker = start.addingTimeInterval(-10)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: file.path)
        for retention in ClipboardRetention.allCases {
            let unchanged = try await store.prune(retention: retention, now: start.addingTimeInterval(3_599))
            XCTAssertEqual(unchanged, saved)
        }
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        XCTAssertEqual(modified, marker)
        let expired = try await store.prune(retention: .hour, now: start.addingTimeInterval(3_600))
        XCTAssertEqual(expired.map(\.text), ["newest"])
        let reloaded = try await ClipboardStore(fileURL: file).load(retention: .forever, now: start.addingTimeInterval(3_600))
        XCTAssertEqual(reloaded, expired)
    }

    func testPruneRepairsBackwardClockEvenWithForeverRetention() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "first", retention: .forever, now: start)
        _ = try await store.record(text: "second", retention: .forever, now: start.addingTimeInterval(60))
        let earlier = start.addingTimeInterval(-60)
        let repaired = try await store.prune(retention: .forever, now: earlier)
        XCTAssertEqual(repaired.map(\.text), ["second", "first"])
        XCTAssertTrue(repaired.allSatisfy { $0.copiedAt == earlier })
        let reloaded = try await ClipboardStore(fileURL: file).load(retention: .forever, now: earlier)
        XCTAssertEqual(reloaded, repaired)
        let expired = try await store.prune(retention: .hour, now: earlier.addingTimeInterval(3_600))
        XCTAssertTrue(expired.isEmpty)
    }

    func testPruneRejectsInvalidTimeEvenForEmptyLoadedStore() async throws {
        let (directory, _, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.load(retention: .forever, now: start)
        for value in [Double.infinity, -Double.infinity, .nan] {
            do {
                _ = try await store.prune(retention: .forever, now: Date(timeIntervalSinceReferenceDate: value))
                XCTFail("Expected invalid maintenance timestamp to be rejected")
            } catch {
                XCTAssertEqual(error as? ClipboardStoreError, .corruptStore)
            }
        }
    }

    func testPersistenceUsesOwnerOnlyDirectoryAndFilePermissions() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.record(text: "private", retention: .forever, now: start)
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(fileMode?.intValue, 0o600)
        XCTAssertEqual(directoryMode?.intValue, 0o700)
    }

    func testCorruptStoreDoesNotOverwriteEvidenceAndExplicitClearCanRecover() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("not JSON, possibly sensitive text".utf8)
        try corrupt.write(to: file)
        do {
            _ = try await store.load(retention: .week, now: start)
            XCTFail("Expected corrupted history to be rejected")
        } catch {
            XCTAssertEqual(error as? ClipboardStoreError, .corruptStore)
        }
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        try await store.clear()
        let recovered = try await store.record(text: "new", retention: .week, now: start)
        XCTAssertEqual(recovered.map(\.text), ["new"])
    }

    func testUnsupportedVersionIsRejectedWithoutRewriting() async throws {
        let (directory, file, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(entries: [], to: file, version: 2)
        let original = try Data(contentsOf: file)
        do {
            _ = try await store.load(retention: .week, now: start)
            XCTFail("Expected a newer unknown format to be rejected")
        } catch {
            XCTAssertEqual(error as? ClipboardStoreError, .unsupportedVersion)
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testRetentionIntervalsAndDefault() {
        XCTAssertEqual(ClipboardRetention.default, .week)
        XCTAssertEqual(ClipboardRetention.hour.expiration, 3_600)
        XCTAssertEqual(ClipboardRetention.day.expiration, 86_400)
        XCTAssertEqual(ClipboardRetention.week.expiration, 604_800)
        XCTAssertEqual(ClipboardRetention.month.expiration, 2_592_000)
        XCTAssertNil(ClipboardRetention.forever.expiration)
    }

    private func fixture() throws -> (URL, URL, ClipboardStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueClipboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("private/history.json")
        return (directory, file, ClipboardStore(fileURL: file))
    }

    private func write(entries: [ClipboardEntry], to url: URL, version: Int = 1) throws {
        struct File: Encodable {
            let version: Int
            let entries: [ClipboardEntry]
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(File(version: version, entries: entries)).write(to: url)
    }
}
