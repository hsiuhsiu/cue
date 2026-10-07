import Darwin
import Foundation
import XCTest
import CueCore

@MainActor
final class CommandHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func entry(_ query: String, action: String = "action:google-search", date: Date? = nil) -> CommandHistoryEntry {
        CommandHistoryEntry(query: query, actionID: action, title: "Fixture", date: date ?? now)
    }

    func testDistinctActionsSameInputAndRepeatDeduplication() {
        var history = CommandHistory()
        history.record(entry("你好"), now: now)
        history.record(entry("你好", action: "action:gpt-translate"), now: now)
        history.record(entry("1+2"), now: now)
        history.record(entry("你好"), now: now)
        XCTAssertEqual(history.entries.map(\.query), ["你好", "1+2", "你好"])
        XCTAssertEqual(history.entries.last?.actionID, "action:gpt-translate")
    }

    func testBoundsExpiryAndInvalidInputs() {
        var history = CommandHistory()
        for i in 0..<300 { history.record(entry("query \(i)"), now: now) }
        XCTAssertEqual(history.entries.count, 200)
        XCTAssertEqual(history.entries.first?.query, "query 299")
        history.record(entry(" \n\t"), now: now)
        history.record(entry(String(repeating: "a", count: 32_769)), now: now)
        history.record(entry("bad\0query"), now: now)
        history.record(entry("expired", date: now.addingTimeInterval(-CommandHistory.retention - 1)), now: now)
        history.record(entry("future", date: now.addingTimeInterval(10_000)), now: now)
        XCTAssertEqual(history.entries.first?.query, "query 299")
        history.prune(now: now.addingTimeInterval(CommandHistory.retention + 1))
        XCTAssertTrue(history.entries.isEmpty)
        for i in 0..<200 { history.record(entry("\(i)" + String(repeating: "z", count: 16_000)), now: now) }
        XCTAssertLessThan(history.entries.count, 40)
    }

    func testRecallSnapshotAndBoundaries() {
        let entries = [entry("newest"), entry("older")]
        var cursor = CommandHistoryCursor()
        XCTAssertNil(cursor.previous(in: []))
        XCTAssertEqual(cursor.previous(in: entries)?.query, "newest")
        XCTAssertEqual(cursor.previous(in: [entry("arrived later")])?.query, "older")
        XCTAssertEqual(cursor.previous(in: [])?.query, "older")
        XCTAssertEqual(cursor.next()?.query, "newest")
        XCTAssertNil(cursor.next())
        XCTAssertFalse(cursor.isActive)
    }

    func testStoreReloadEarlyRecordClearAndPermissions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cue-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("History/history.json")
        let store = CommandHistoryStore(fileURL: url)
        _ = await store.load(now: now)
        try await store.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        _ = await store.record(entry("old"), now: now)
        try await store.flush()

        let restarted = CommandHistoryStore(fileURL: url)
        _ = await restarted.record(entry("new"), now: now) // Before explicit startup load.
        let loaded = await restarted.load(now: now)
        XCTAssertEqual(loaded.entries.map(\.query), ["new", "old"])
        _ = await restarted.remove(loaded.entries[1].id, now: now)
        try await restarted.flush()
        let reloaded = await CommandHistoryStore(fileURL: url).load(now: now)
        XCTAssertEqual(reloaded.entries.map(\.query), ["new"])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(permissions.intValue, 0o600)
        let parentPermissions = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(parentPermissions.intValue, 0o700)
        _ = await restarted.clear()
        try await restarted.flush()
        let cleared = await CommandHistoryStore(fileURL: url).load(now: now)
        XCTAssertTrue(cleared.entries.isEmpty)
    }

    func testMalformedOversizedAndSymlinkFilesAreNotFollowed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cue-history-invalid-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("history.json")
        let original = Data("private fixture".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = CommandHistoryStore(fileURL: link)
        let initial = await linked.load(now: now)
        XCTAssertTrue(initial.entries.isEmpty)
        _ = await linked.record(entry("replacement"), now: now)
        try await linked.flush()
        XCTAssertEqual(try Data(contentsOf: target), original)
        try Data(repeating: 0, count: CommandHistoryStore.maximumFileBytes + 1).write(to: link)
        let oversized = await CommandHistoryStore(fileURL: link).load(now: now)
        XCTAssertTrue(oversized.entries.isEmpty)
    }
}
