import Foundation

public struct CommandHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let query: String
    public let actionID: String
    public let title: String
    public let date: Date

    public init(id: UUID = UUID(), query: String, actionID: String, title: String, date: Date = Date()) {
        self.id = id
        self.query = query
        self.actionID = actionID
        self.title = title
        self.date = date
    }

    public var isValid: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && query.utf8.count <= 32_768
            && !actionID.isEmpty && actionID.utf8.count <= 8_192
            && title.utf8.count <= 1_024
            && date.timeIntervalSince1970.isFinite
            && !query.contains("\0") && !actionID.contains("\0")
    }

    var byteCount: Int { query.utf8.count + actionID.utf8.count + title.utf8.count }
}

/// Only explicit executions enter this bounded, local history. It is separate
/// from search ranking, clipboard payloads, selected text and GPT responses.
public struct CommandHistory: Codable, Equatable, Sendable {
    public static let maximumEntries = 200
    public static let maximumTextBytes = 512 * 1_024
    public static let retention: TimeInterval = 30 * 86_400
    public private(set) var entries: [CommandHistoryEntry] = []

    public init() {}

    public mutating func record(_ entry: CommandHistoryEntry, now: Date = Date()) {
        guard entry.isValid else { return }
        // One shortcut per input/action; repeating a command moves it to the top.
        entries.removeAll { $0.query == entry.query && $0.actionID == entry.actionID }
        entries.insert(entry, at: 0)
        prune(now: now)
    }

    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func clear() { entries.removeAll(keepingCapacity: false) }

    public mutating func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var ids = Set<UUID>()
        var queries: [String: Set<String>] = [:]
        var bytes = 0
        entries = entries.filter {
            guard $0.isValid, $0.date >= cutoff, $0.date <= now.addingTimeInterval(300),
                  ids.insert($0.id).inserted, ids.count <= Self.maximumEntries,
                  queries[$0.actionID, default: []].insert($0.query).inserted,
                  bytes + $0.byteCount <= Self.maximumTextBytes else { return false }
            bytes += $0.byteCount
            return true
        }
    }
}

/// Freeze the small snapshot while browsing, so background loads cannot shift
/// the command under the user's next Up/Down key. Editing ends recall.
public struct CommandHistoryCursor: Sendable {
    private var entries: [CommandHistoryEntry] = []
    private var index: Int?
    public var isActive: Bool { index != nil }
    public init() {}

    public mutating func previous(in history: [CommandHistoryEntry]) -> CommandHistoryEntry? {
        if let index { self.index = min(index + 1, entries.count - 1) }
        else {
            guard !history.isEmpty else { return nil }
            entries = history
            index = 0
        }
        return entries[index!]
    }

    public mutating func next() -> CommandHistoryEntry? {
        guard let index, index > 0 else { reset(); return nil }
        self.index = index - 1
        return entries[index - 1]
    }

    public mutating func reset() { index = nil; entries.removeAll(keepingCapacity: false) }
}
