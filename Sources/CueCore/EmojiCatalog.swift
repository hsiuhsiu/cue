import Foundation

public struct EmojiEntry: Identifiable, Equatable, Sendable, Decodable {
    public var id: String { emoji }
    public let emoji: String
    public let name: String
    public let traditionalName: String
    public let keywords: [String]

    public init(emoji: String, name: String, traditionalName: String, keywords: [String] = []) {
        self.emoji = emoji
        self.name = name
        self.traditionalName = traditionalName
        self.keywords = keywords
    }
}

/// Immutable, local search data. Decode and index once away from the input thread.
public struct EmojiCatalog: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidCatalog
    }

    public var count: Int { entries.count }

    private let entries: [EmojiEntry]
    private let documents: [Document]
    private let exactEmoji: [String: Int]
    private let popular: [Int]

    public init(data: Data) throws {
        guard data.count <= 8 * 1_024 * 1_024 else { throw Error.invalidCatalog }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.formatVersion == 1, payload.unicodeVersion == "15.0",
              payload.cldrVersion == "42", !payload.entries.isEmpty,
              payload.entries.count <= 5_000 else { throw Error.invalidCatalog }

        var exactEmoji: [String: Int] = [:]
        var documents: [Document] = []
        exactEmoji.reserveCapacity(payload.entries.count)
        documents.reserveCapacity(payload.entries.count)
        for (index, entry) in payload.entries.enumerated() {
            let key = Self.emojiKey(entry.emoji)
            guard !key.isEmpty, entry.emoji.utf8.count <= 128,
                  !entry.name.isEmpty, entry.name.utf8.count <= 512,
                  !entry.traditionalName.isEmpty, entry.traditionalName.utf8.count <= 512,
                  entry.keywords.count <= 100,
                  entry.keywords.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
                  exactEmoji.updateValue(index, forKey: key) == nil else {
                throw Error.invalidCatalog
            }
            documents.append(Document(entry))
        }
        entries = payload.entries
        self.documents = documents
        self.exactEmoji = exactEmoji
        let favorites = ["😀", "😂", "❤️", "👍", "🎉", "🙏", "🔥", "✅", "😊"]
            .compactMap { exactEmoji[Self.emojiKey($0)] }
        let favoritesSet = Set(favorites)
        popular = favorites + entries.indices.filter {
            !favoritesSet.contains($0) && !documents[$0].hasSkinTone
        } + entries.indices.filter { !favoritesSet.contains($0) && documents[$0].hasSkinTone }
    }

    public func search(_ query: String, limit: Int = 9) -> [EmojiEntry] {
        guard limit > 0 else { return [] }
        let maximum = min(limit, entries.count)
        // Bound pasted prose before normalization; emoji search is a short keyword lookup.
        guard query.utf8.count <= 1_024 else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return popular.prefix(maximum).map { entries[$0] } }
        if let index = exactEmoji[Self.emojiKey(trimmed)] { return [entries[index]] }

        let normalized = Self.normalize(trimmed)
        guard !normalized.isEmpty else { return [] }
        let bytes = Array(normalized.utf8)
        let terms = bytes.split(separator: 32).map(Array.init)
        var best: [Candidate] = []
        best.reserveCapacity(maximum)
        for index in documents.indices {
            let document = documents[index]
            guard let rank = document.rank(query: bytes, terms: terms) else { continue }
            let candidate = Candidate(index: index, tone: document.hasSkinTone ? 1 : 0,
                                      rank: rank, common: document.commonRank)
            if best.count == maximum, let last = best.last, !candidate.precedes(last) { continue }
            let position = best.firstIndex(where: { candidate.precedes($0) }) ?? best.count
            best.insert(candidate, at: position)
            if best.count > maximum { best.removeLast() }
        }
        return best.map { entries[$0.index] }
    }

    private struct Payload: Decodable {
        let formatVersion: Int
        let unicodeVersion: String
        let cldrVersion: String
        let entries: [EmojiEntry]
    }

    private struct Candidate {
        let index: Int
        let tone: Int
        let rank: Int
        let common: Int

        func precedes(_ other: Candidate) -> Bool {
            (tone, rank, common, index) < (other.tone, other.rank, other.common, other.index)
        }
    }

    private struct Document: Sendable {
        let english: [UInt8]
        let traditional: [UInt8]
        let fields: [UInt8]
        let hasSkinTone: Bool
        let commonRank: Int

        init(_ entry: EmojiEntry) {
            english = Array(EmojiCatalog.normalize(entry.name).utf8)
            traditional = Array(EmojiCatalog.normalize(entry.traditionalName).utf8)
            // NUL separates fields, so a search cannot accidentally span two keywords.
            fields = [0] + Array(([entry.name, entry.traditionalName] + entry.keywords)
                .map(EmojiCatalog.normalize).joined(separator: "\0").utf8) + [0]
            hasSkinTone = entry.emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
            commonRank = ["😀", "😂", "❤️", "👍", "🎉", "🙏", "🔥", "✅", "😊"]
                .firstIndex(of: entry.emoji) ?? 9
        }

        func rank(query: [UInt8], terms: [[UInt8]]) -> Int? {
            if english == query || traditional == query { return 0 }
            let match = fieldMatch(query)
            if match == 2 { return 1 }
            if match == 0 {
                return terms.count > 1 && terms.allSatisfy({ Self.contains(fields, $0) }) ? 5 : nil
            }
            if english.starts(with: query) || traditional.starts(with: query) { return 2 }
            if Self.contains(english, query) || Self.contains(traditional, query) { return 3 }
            return 4
        }

        /// One pass distinguishes a whole keyword from a substring match.
        private func fieldMatch(_ needle: [UInt8]) -> Int {
            guard let first = needle.first, needle.count < fields.count else { return 0 }
            var matched = 0
            for start in 1..<(fields.count - needle.count) where fields[start] == first {
                var offset = 1
                while offset < needle.count, fields[start + offset] == needle[offset] { offset += 1 }
                if offset == needle.count {
                    if fields[start - 1] == 0 && fields[start + offset] == 0 { return 2 }
                    matched = 1
                }
            }
            return matched
        }

        // Matching normalized UTF-8 directly avoids locale collation and substring
        // allocations for each of the 3,655 entries on every keypress.
        private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
            guard let first = needle.first, needle.count <= haystack.count else { return false }
            for start in 0...(haystack.count - needle.count) where haystack[start] == first {
                var offset = 1
                while offset < needle.count, haystack[start + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return true }
            }
            return false
        }
    }

    private static func emojiKey(_ value: String) -> String {
        // Text and emoji presentation selectors change appearance, not identity.
        // Preserve ZWJ, tone modifiers, and the catalog's fully-qualified output.
        String(String.UnicodeScalarView(value.unicodeScalars.filter {
            $0.value != 0xFE0E && $0.value != 0xFE0F
        }))
    }

    private static func normalize(_ value: String) -> String {
        SearchEngine.normalize(value)
            .split(whereSeparator: { $0 == ":" || $0 == "_" || $0 == "-" || $0.isWhitespace })
            .joined(separator: " ")
    }
}
