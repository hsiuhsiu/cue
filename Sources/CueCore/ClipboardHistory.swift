import Foundation
import Darwin

/// Immutable clipboard content. Derived presentation/search strings are built off the UI path.
public struct ClipboardEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let copiedAt: Date
    public let preview: String

    let searchableBytes: [UInt8]
    let byteCount: Int

    public init(id: UUID = UUID(), text: String, copiedAt: Date) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        byteCount = text.utf8.count
        searchableBytes = Array(Self.normalizeForSearch(text).utf8)
        preview = Self.makePreview(text)
    }

    static func normalizeForSearch(_ text: String) -> String {
        // A canonical representation preserves equivalent Unicode spellings while
        // allowing fast literal byte matching instead of repeating Unicode comparisons.
        SearchEngine.normalize(text).precomposedStringWithCanonicalMapping
    }

    private static func makePreview(_ text: String) -> String {
        var preview = ""
        preview.reserveCapacity(160)
        var count = 0
        var bytes = 0
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                pendingSpace = !preview.isEmpty
                continue
            }
            let next = String(character)
            let space = pendingSpace ? 1 : 0
            // Stop at the visible prefix, without splitting/joining the complete text
            // again. A byte cap also keeps a huge combining-character cluster out of UI.
            guard count + space + 1 <= 160, bytes + space + next.utf8.count <= 1_024 else {
                return preview + "…"
            }
            if pendingSpace { preview.append(" ") }
            preview.append(next)
            count += space + 1
            bytes += space + next.utf8.count
            pendingSpace = false
        }
        return preview
    }

    private enum CodingKeys: String, CodingKey { case id, text, copiedAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            text: try values.decode(String.self, forKey: .text),
            copiedAt: try values.decode(Date.self, forKey: .copiedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(text, forKey: .text)
        try values.encode(copiedAt, forKey: .copiedAt)
    }
}

public enum ClipboardRetention: String, CaseIterable, Codable, Sendable {
    case hour, day, week, month, forever

    public static let `default`: Self = .week

    /// A month is a rolling 30-day window, independent of calendar and time zone.
    public var expiration: TimeInterval? {
        switch self {
        case .hour: 60 * 60
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        case .forever: nil
        }
    }
}

public enum ClipboardStoreError: Error, Equatable, Sendable {
    case corruptStore
    case unsupportedVersion
    case entryTooLarge
}

/// Serializes clipboard mutation and disk work away from the main actor.
/// Give each store a file in a dedicated directory: it enforces owner-only permissions.
/// Call `load` with the saved retention preference before displaying history.
public actor ClipboardStore {
    public static let maximumEntries = 500
    public static let maximumEntryBytes = 256 * 1024
    public static let maximumTotalBytes = 4 * 1024 * 1024

    private static let maximumFileBytes = 32 * 1024 * 1024
    private let fileURL: URL
    private var entries: [ClipboardEntry] = []
    private var isLoaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    public func load(retention: ClipboardRetention = .default, now: Date = Date()) throws -> [ClipboardEntry] {
        if isLoaded { return try prune(retention: retention, now: now) }
        let stored = try read()
        let cleaned = try bounded(stored, retention: retention, now: now)
        if cleaned != stored {
            try persist(cleaned)
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            try restrictPermissions()
        }
        entries = cleaned
        isLoaded = true
        return entries
    }

    public func record(
        text: String, retention: ClipboardRetention = .default, now: Date = Date()
    ) throws -> [ClipboardEntry] {
        guard text.utf8.count <= Self.maximumEntryBytes else { throw ClipboardStoreError.entryTooLarge }
        if !isLoaded { _ = try load(retention: retention, now: now) }
        var updated = try bounded(entries, retention: retention, now: now)
        if !text.allSatisfy(\.isWhitespace) {
            let previous = updated.first { $0.text == text }
            updated.removeAll { $0.text == text }
            updated.insert(ClipboardEntry(id: previous?.id ?? UUID(), text: text, copiedAt: now), at: 0)
            updated = try bounded(updated, retention: retention, now: now)
        }
        try commit(updated)
        return entries
    }

    public func remove(id: UUID) throws -> [ClipboardEntry] {
        // A deletion alone must not apply an unknown retention preference to other items.
        if !isLoaded { _ = try load(retention: .forever) }
        try commit(entries.filter { $0.id != id })
        return entries
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        // There are no suspension points within a mutation, so queued writes cannot
        // restore an older snapshot after a deletion or clear has completed.
        entries = []
        isLoaded = true
    }

    public func prune(retention: ClipboardRetention = .default, now: Date = Date()) throws -> [ClipboardEntry] {
        if !isLoaded { return try load(retention: retention, now: now) }
        try commit(bounded(entries, retention: retention, now: now))
        return entries
    }

    /// Searches the cached text in recency order without touching persistence.
    public func search(query: String, limit: Int? = nil) -> [ClipboardEntry] {
        guard !Task.isCancelled else { return [] }
        let cap = max(0, limit ?? entries.count)
        guard cap > 0 else { return [] }
        let query = Array(ClipboardEntry.normalizeForSearch(query).utf8)
        guard !Task.isCancelled else { return [] }
        guard !query.isEmpty else { return Array(entries.prefix(cap)) }
        return query.withUnsafeBytes { needle in
            var matches: [ClipboardEntry] = []
            matches.reserveCapacity(min(cap, entries.count))
            for entry in entries {
                // Obsolete keystrokes must not scan every retained payload before
                // the newest query can enter this serial store actor.
                guard !Task.isCancelled else { return [] }
                let matchesQuery = entry.searchableBytes.withUnsafeBytes { haystack in
                    guard haystack.count >= needle.count else { return false }
                    return memmem(haystack.baseAddress, haystack.count, needle.baseAddress, needle.count) != nil
                }
                if matchesQuery {
                    matches.append(entry)
                    if matches.count == cap { break }
                }
            }
            return matches
        }
    }

    private func commit(_ updated: [ClipboardEntry]) throws {
        guard updated != entries else { return }
        try persist(updated)
        entries = updated
    }

    private func bounded(
        _ candidates: [ClipboardEntry], retention: ClipboardRetention, now: Date
    ) throws -> [ClipboardEntry] {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              candidates.allSatisfy({ $0.copiedAt.timeIntervalSinceReferenceDate.isFinite })
        else { throw ClipboardStoreError.corruptStore }
        // Preserve insertion order for equal timestamps, including the newest recopy.
        let sorted = candidates.enumerated().sorted {
            if $0.element.copiedAt != $1.element.copiedAt {
                return $0.element.copiedAt > $1.element.copiedAt
            }
            return $0.offset < $1.offset
        }
        var result: [ClipboardEntry] = []
        result.reserveCapacity(min(candidates.count, Self.maximumEntries))
        var seenText = Set<String>()
        var seenIDs = Set<UUID>()
        var totalBytes = 0
        for (_, candidate) in sorted {
            guard candidate.byteCount <= Self.maximumEntryBytes,
                  !candidate.searchableBytes.isEmpty,
                  !seenText.contains(candidate.text), !seenIDs.contains(candidate.id)
            else { continue }
            if let expiration = retention.expiration,
               now.timeIntervalSince(candidate.copiedAt) >= expiration { continue }
            guard result.count < Self.maximumEntries,
                  totalBytes + candidate.byteCount <= Self.maximumTotalBytes else { break }
            // A backward clock change or a malformed future timestamp must not evade
            // the configured retention window indefinitely.
            let entry = candidate.copiedAt > now
                ? ClipboardEntry(id: candidate.id, text: candidate.text, copiedAt: now) : candidate
            result.append(entry)
            totalBytes += entry.byteCount
            seenText.insert(entry.text)
            seenIDs.insert(entry.id)
        }
        return result
    }

    private func read() throws -> [ClipboardEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= Self.maximumFileBytes
        else { throw ClipboardStoreError.corruptStore }
        let data = try Data(contentsOf: fileURL)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let file = try decoder.decode(HistoryFile.self, from: data)
            guard file.version == 1 else { throw ClipboardStoreError.unsupportedVersion }
            return file.entries
        } catch let error as ClipboardStoreError {
            throw error
        } catch {
            // Decode errors may contain clipboard data; expose a content-free error.
            throw ClipboardStoreError.corruptStore
        }
    }

    private func persist(_ entries: [ClipboardEntry]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(HistoryFile(version: 1, entries: entries))
        try data.write(to: fileURL, options: .atomic)
        try restrictPermissions()
    }

    private func restrictPermissions() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fileURL.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private struct HistoryFile: Codable {
        let version: Int
        let entries: [ClipboardEntry]

        init(version: Int, entries: [ClipboardEntry]) {
            self.version = version
            self.entries = entries
        }

        private enum CodingKeys: String, CodingKey { case version, entries }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            var items = try values.nestedUnkeyedContainer(forKey: .entries)
            // Permit repair of an over-capacity history without unbounded allocations
            // from a corrupted file containing millions of tiny records.
            guard (items.count ?? 0) <= ClipboardStore.maximumEntries * 20 else {
                throw ClipboardStoreError.corruptStore
            }
            var entries: [ClipboardEntry] = []
            while !items.isAtEnd {
                entries.append(try items.decode(ClipboardEntry.self))
            }
            self.entries = entries
        }
    }
}
