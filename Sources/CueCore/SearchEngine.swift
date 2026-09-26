import Foundation

/// Stateless, deterministic ranking over the already indexed application names.
public enum SearchEngine {
    public static func search(
        _ applications: [IndexedApplication],
        query: String
    ) -> [IndexedApplication] {
        search(applications, normalizedQuery: normalize(query))
    }

    static func search(
        _ applications: [IndexedApplication],
        normalizedQuery query: String
    ) -> [IndexedApplication] {
        if query.isEmpty {
            return applications.sorted(by: alphabeticallyPrecedes)
        }

        let queryCharacters = Array(query.filter { !$0.isWhitespace })
        return applications.compactMap { application -> (IndexedApplication, Rank)? in
            guard let rank = rank(application, query: query, characters: queryCharacters) else {
                return nil
            }
            return (application, rank)
        }.sorted { left, right in
            if left.1 != right.1 { return left.1 < right.1 }
            return alphabeticallyPrecedes(left.0, right.0)
        }.map(\.0)
    }

    static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func alphabeticallyPrecedes(
        _ left: IndexedApplication,
        _ right: IndexedApplication
    ) -> Bool {
        if left.searchableName != right.searchableName {
            return left.searchableName < right.searchableName
        }
        return left.id < right.id
    }

    private struct Rank: Comparable {
        let category: Int
        let penalty: Int
        let position: Int
        let length: Int

        static func < (left: Rank, right: Rank) -> Bool {
            (left.category, left.penalty, left.position, left.length)
                < (right.category, right.penalty, right.position, right.length)
        }
    }

    private static func rank(
        _ application: IndexedApplication,
        query: String,
        characters queryCharacters: [Character]
    ) -> Rank? {
        let name = application.searchableName
        let characters = application.searchableCharacters
        let length = characters.count
        if name == query { return Rank(category: 0, penalty: 0, position: 0, length: length) }
        if name.hasPrefix(query) {
            return Rank(category: 1, penalty: 0, position: 0, length: length)
        }
        for (index, suffix) in application.wordSuffixes.enumerated() {
            if suffix.hasPrefix(query) {
                let start = application.wordStarts[index + 1]
                return Rank(category: 2, penalty: 0, position: start, length: length)
            }
        }
        if let range = name.range(of: query) {
            let position = name.distance(from: name.startIndex, to: range.lowerBound)
            return Rank(category: 3, penalty: 0, position: position, length: length)
        }

        guard queryCharacters.count >= 2, queryCharacters.count <= length else { return nil }

        // Initials can span long words: "vsc" should find "Visual Studio Code".
        if subsequenceEnd(queryCharacters, in: application.initials, startingAt: 0) != nil {
            return Rank(category: 4, penalty: 0, position: 0, length: length)
        }

        // Otherwise anchor fuzzy matches to a word, and cap skipped characters so
        // short queries do not pull in names with only a distant accidental match.
        var best: Rank?
        for start in application.wordStarts where characters[start] == queryCharacters[0] {
            guard let end = subsequenceEnd(queryCharacters, in: characters, startingAt: start) else {
                continue
            }
            let skipped = end - start + 1 - queryCharacters.count
            guard skipped <= max(2, queryCharacters.count * 2) else { continue }
            let candidate = Rank(category: 4, penalty: skipped + 1, position: start, length: length)
            if let previous = best {
                if candidate < previous { best = candidate }
            } else {
                best = candidate
            }
        }
        return best
    }

    private static func subsequenceEnd(
        _ query: [Character],
        in characters: [Character],
        startingAt start: Int
    ) -> Int? {
        var queryIndex = 0
        for index in start..<characters.count where characters[index] == query[queryIndex] {
            queryIndex += 1
            if queryIndex == query.count { return index }
        }
        return nil
    }
}
