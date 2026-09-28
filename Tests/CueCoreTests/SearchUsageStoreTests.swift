import Darwin
import Foundation
import XCTest
import CueCore

@MainActor
final class SearchUsageStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let safari = "app:/Applications/Safari.app"
    private let studio = "app:/Applications/Studio.app"

    func testMissingStoreDoesNotCreateFilesUntilASuccessfulSelection() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = await store.load(now: now)
        XCTAssertEqual(initial, .empty)
        try await store.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        let selected = await store.record(resultID: safari, query: "s", at: now)
        try await store.flush()
        let reloaded = await SearchUsageStore(fileURL: file).load(now: now)
        XCTAssertEqual(reloaded, selected)
        XCTAssertNotEqual(reloaded, .empty)
    }

    func testRecordBeforeStartupLoadPreservesExistingLearningAndNewSelection() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var expected = SearchUsage()
        expected.record(resultID: safari, query: "s", at: now.addingTimeInterval(-60))
        try write(expected, to: file)

        let recorded = await store.record(resultID: studio, query: "st", at: now)
        expected.record(resultID: studio, query: "st", at: now)
        XCTAssertEqual(recorded, expected.snapshot(at: now))
        let lateLoad = await store.load(now: now)
        XCTAssertEqual(lateLoad, recorded)
        try await store.flush()
        let reloaded = await SearchUsageStore(fileURL: file).load(now: now)
        XCTAssertEqual(reloaded, recorded)
    }

    func testFlushPersistsLatestSnapshotAndDoesNotRestoreAnOlderScheduledWrite() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var expected = SearchUsage()
        for index in 0..<30 {
            let date = now.addingTimeInterval(Double(index))
            _ = await store.record(resultID: safari, query: "s", at: date)
            expected.record(resultID: safari, query: "s", at: date)
        }
        try await store.flush()
        _ = await store.record(resultID: studio, query: "st", at: now.addingTimeInterval(31))
        expected.record(resultID: studio, query: "st", at: now.addingTimeInterval(31))
        try await store.flush()
        let result = await SearchUsageStore(fileURL: file).load(now: now.addingTimeInterval(31))
        XCTAssertEqual(result, expected.snapshot(at: now.addingTimeInterval(31)))
        let contents = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        XCTAssertEqual(contents, [file.lastPathComponent])
    }

    func testConcurrentEarlyRecordsAreSerializedWithoutLostUpdates() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resultID = safari
        let date = now
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    _ = await store.record(resultID: resultID, query: "s", at: date)
                }
            }
        }
        var expected = SearchUsage()
        for _ in 0..<50 { expected.record(resultID: safari, query: "s", at: now) }
        try await store.flush()
        let result = await SearchUsageStore(fileURL: file).load(now: now)
        XCTAssertEqual(result, expected.snapshot(at: now))
    }

    func testCorruptUnsupportedAndOversizedFilesFallBackWithoutChangingThemUntilSelection() async throws {
        let payloads = [
            Data("not json".utf8),
            try JSONEncoder().encode(StoredUsage(version: 99, usage: SearchUsage())),
            Data(repeating: 0x20, count: SearchUsageStore.maximumFileBytes + 1),
        ]
        for payload in payloads {
            let (directory, file, store) = fixture()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.write(to: file)
            let initial = await store.load(now: now)
            XCTAssertEqual(initial, .empty)
            try await store.flush()
            XCTAssertEqual(try Data(contentsOf: file), payload)
            let updated = await store.record(resultID: safari, query: "s", at: now)
            try await store.flush()
            let reloaded = await SearchUsageStore(fileURL: file).load(now: now)
            XCTAssertEqual(reloaded, updated)
        }
    }

    func testStoreRestrictsExistingAndNewFilePermissions() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var existing = SearchUsage()
        existing.record(resultID: safari, query: "s", at: now)
        try write(existing, to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        _ = await store.load(now: now)
        XCTAssertEqual(try permissions(of: file), 0o600)
        XCTAssertEqual(try permissions(of: file.deletingLastPathComponent()), 0o700)
        _ = await store.record(resultID: studio, query: "st", at: now)
        try await store.flush()
        XCTAssertEqual(try permissions(of: file), 0o600)
        XCTAssertEqual(try permissions(of: file.deletingLastPathComponent()), 0o700)
    }

    func testSymlinkIsNotReadOrFollowedByAtomicReplacement() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("unrelated.json")
        var previous = SearchUsage()
        previous.record(resultID: studio, query: "st", at: now)
        try write(previous, to: target)
        let untouched = try Data(contentsOf: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)

        let initial = await store.load(now: now)
        XCTAssertEqual(initial, .empty)
        _ = await store.record(resultID: safari, query: "s", at: now)
        try await store.flush()
        XCTAssertEqual(try Data(contentsOf: target), untouched)
        XCTAssertFalse(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true)
        XCTAssertEqual(try permissions(of: file), 0o600)
    }

    func testWriteFailureRetainsInMemoryLearningAndCanRetry() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = file.deletingLastPathComponent()
        try Data("temporary blocker".utf8).write(to: blocker)
        let learned = await store.record(resultID: safari, query: "s", at: now)
        do {
            try await store.flush()
            XCTFail("Expected an unavailable store")
        } catch {
            XCTAssertEqual(error as? SearchUsageStoreError, .unavailable)
        }
        let remembered = await store.load(now: now)
        XCTAssertEqual(remembered, learned)

        try FileManager.default.removeItem(at: blocker)
        try await store.flush()
        let reloaded = await SearchUsageStore(fileURL: file).load(now: now)
        XCTAssertEqual(reloaded, learned)
    }

    func testFullyPopulatedEscapedModelRoundTripsWithinFileLimit() async throws {
        let (directory, file, store) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ids = (0..<SearchUsage.maximumResults).map {
            "app:" + String(repeating: "\u{0001}", count: SearchUsage.maximumResultIDBytes - 16) + "\($0)"
        }
        var expected = SearchUsage()
        for id in ids { expected.record(resultID: id, query: "initial", at: now) }
        var lastQuery = ""
        for queryIndex in 0..<SearchUsage.maximumQueries {
            let query = "q\(queryIndex):" + String(repeating: "\u{0001}", count: SearchUsage.maximumQueryBytes - 10)
            lastQuery = query
            for index in 0..<SearchUsage.maximumResultsPerQuery {
                expected.record(resultID: ids[(queryIndex * 8 + index) % ids.count], query: query, at: now)
            }
        }
        XCTAssertEqual(expected.resultCount, SearchUsage.maximumResults)
        XCTAssertEqual(expected.queryCount, SearchUsage.maximumQueries)
        try write(expected, to: file)
        let loaded = await store.load(now: now)
        XCTAssertEqual(loaded, expected.snapshot(at: now))
        expected.record(resultID: ids[0], query: lastQuery, at: now)
        let updated = await store.record(resultID: ids[0], query: lastQuery, at: now)
        try await store.flush()
        XCTAssertEqual(updated, expected.snapshot(at: now))
        XCTAssertLessThan(try Data(contentsOf: file).count, SearchUsageStore.maximumFileBytes)
        let reloaded = await SearchUsageStore(fileURL: file).load(now: now)
        XCTAssertEqual(reloaded, updated)
    }

    private func fixture() -> (URL, URL, SearchUsageStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CueUsageTests-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("Search/usage.json")
        return (directory, file, SearchUsageStore(fileURL: file))
    }

    private func write(_ usage: SearchUsage, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(StoredUsage(version: 1, usage: usage)).write(to: file)
    }

    private func permissions(of file: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        return (try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)).intValue & 0o777
    }

    private struct StoredUsage: Codable {
        let version: Int
        let usage: SearchUsage
    }
}
