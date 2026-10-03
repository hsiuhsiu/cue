import Foundation

/// Deterministic ranking over indexed names and optional in-memory usage scores.
public enum SearchEngine {
    public static func search(
        _ applications: [IndexedApplication],
        query: String,
        usage: SearchUsageSnapshot = .empty
    ) -> [IndexedApplication] {
        search(applications, normalizedQuery: normalize(query), usage: usage)
    }

    static func search(
        _ applications: [IndexedApplication],
        normalizedQuery query: String,
        usage: SearchUsageSnapshot = .empty
    ) -> [IndexedApplication] {
        if query.isEmpty {
            return applications.sorted(by: alphabeticallyPrecedes)
        }

        let queryCharacters = Array(query.filter { !$0.isWhitespace })
        let scorer = usage.scorer(normalizedQuery: query)
        let hasUsage = !usage.isEmpty
        // Sort scalar indices/scores, not IndexedApplication's strings and arrays.
        // Dense matches otherwise copy and retain that large value on every swap.
        var candidates: [Candidate] = []
        candidates.reserveCapacity(applications.count)
        for index in applications.indices {
            let application = applications[index]
            guard let rank = rank(application, query: query, characters: queryCharacters) else {
                continue
            }
            candidates.append(Candidate(index: index, rank: rank,
                signal: hasUsage ? scorer.signal(for: application.searchUsageID) : .zero))
        }
        candidates.sort { left, right in
            if left.rank.category != right.rank.category { return left.rank.category < right.rank.category }
            if left.signal != right.signal { return left.signal > right.signal }
            if left.rank != right.rank { return left.rank < right.rank }
            return alphabeticallyPrecedes(applications[left.index], applications[right.index])
        }
        return candidates.map { applications[$0.index] }
    }

    /// Use at index/preference preparation and once at the query boundary, not
    /// repeatedly for each application while searching.
    public static func normalize(_ value: String) -> String {
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

    private struct Candidate {
        let index: Int
        let rank: Rank
        let signal: SearchUsageSnapshot.Signal
    }

    private static func rank(
        _ application: IndexedApplication,
        query: String,
        characters queryCharacters: [Character]
    ) -> Rank? {
        var best: Rank?
        if let alias = application.normalizedSearchAlias {
            if alias == query {
                return Rank(category: -1, penalty: 0, position: 0, length: application.searchAliasLength)
            }
            if alias.hasPrefix(query) {
                best = Rank(category: 1, penalty: 0, position: 0, length: application.searchAliasLength)
            }
        }
        for name in application.searchNames {
            guard let candidate = rank(name, query: query, characters: queryCharacters) else { continue }
            if let previous = best {
                if candidate < previous { best = candidate }
            } else {
                best = candidate
            }
            // An automatic exact match cannot be improved by another name.
            if candidate.category == 0 { return candidate }
        }
        return best
    }

    private static func rank(
        _ searchName: SearchName,
        query: String,
        characters queryCharacters: [Character]
    ) -> Rank? {
        let name = searchName.name
        let characters = searchName.characters
        let length = characters.count
        if name == query { return Rank(category: 0, penalty: 0, position: 0, length: length) }
        if name.hasPrefix(query) {
            return Rank(category: 1, penalty: 0, position: 0, length: length)
        }
        for (index, suffix) in searchName.wordSuffixes.enumerated() {
            if suffix.hasPrefix(query) {
                let start = searchName.wordStarts[index + 1]
                return Rank(category: 2, penalty: 0, position: start, length: length)
            }
        }
        if let range = name.range(of: query) {
            let position = name.distance(from: name.startIndex, to: range.lowerBound)
            return Rank(category: 3, penalty: 0, position: position, length: length)
        }

        guard queryCharacters.count >= 2, queryCharacters.count <= length else { return nil }

        // Initials can span long words: "vsc" should find "Visual Studio Code".
        if subsequenceEnd(queryCharacters, in: searchName.initials, startingAt: 0) != nil {
            return Rank(category: 4, penalty: 0, position: 0, length: length)
        }

        // Otherwise anchor fuzzy matches to a word, and cap skipped characters so
        // short queries do not pull in names with only a distant accidental match.
        var best: Rank?
        for start in searchName.wordStarts where characters[start] == queryCharacters[0] {
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
