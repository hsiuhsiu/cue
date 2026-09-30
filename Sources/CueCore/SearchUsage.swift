import Foundation

/// Small, local-only learning state. The caller records successful explicit actions,
/// then builds an immutable snapshot away from the typing/rendering path.
public struct SearchUsage: Codable, Equatable, Sendable {
    public static let maximumResults = 512
    public static let maximumQueries = 256
    public static let maximumResultsPerQuery = 8
    public static let maximumQueryBytes = 128
    public static let maximumResultIDBytes = 512

    private static let halfLife: TimeInterval = 14 * 24 * 60 * 60
    private static let minimumScore = 0.01
    private static let maximumScore = 1_000_000.0

    private struct Entry: Codable, Equatable, Sendable {
        var score: Double
        var lastUsed: Date

        var isValid: Bool {
            score.isFinite && score > 0 && score <= SearchUsage.maximumScore
                && lastUsed.timeIntervalSinceReferenceDate.isFinite
        }

        func score(at date: Date) -> Double {
            let elapsed = max(0, date.timeIntervalSince(lastUsed))
            let decayed = score * exp2(-elapsed / SearchUsage.halfLife)
            return decayed >= SearchUsage.minimumScore ? decayed : 0
        }

        mutating func record(at date: Date) {
            // A clock correction or an older queued action must not amplify history.
            let date = max(date, lastUsed)
            score = min(SearchUsage.maximumScore, score(at: date) + 1)
            lastUsed = date
        }
    }

    private var results: [String: Entry] = [:]
    private var queries: [String: [String: Entry]] = [:]

    public init() {}

    public var resultCount: Int { results.count }
    public var queryCount: Int { queries.count }

    public mutating func record(resultID: String, query: String, at date: Date = Date()) {
        let query = SearchEngine.normalize(query)
        guard Self.validResultID(resultID), Self.validQuery(query),
              date.timeIntervalSinceReferenceDate.isFinite else { return }

        var result = results[resultID] ?? Entry(score: 0, lastUsed: date)
        result.record(at: date)
        results[resultID] = result

        var selections = queries[query] ?? [:]
        var selection = selections[resultID] ?? Entry(score: 0, lastUsed: date)
        selection.record(at: date)
        selections[resultID] = selection
        queries[query] = Self.trim(selections, to: Self.maximumResultsPerQuery)
        enforceLimits()
    }

    public func snapshot(at date: Date = Date()) -> SearchUsageSnapshot {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return .empty }
        return SearchUsageSnapshot(
            general: results.compactMapValues { entry in
                let score = entry.score(at: date)
                return score > 0 ? score : nil
            },
            queries: queries.compactMapValues { selections in
                let scores = selections.compactMapValues { entry in
                    let score = entry.score(at: date)
                    return score > 0 ? score : nil
                }
                return scores.isEmpty ? nil : scores
            }
        )
    }

    private static func validResultID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= maximumResultIDBytes
    }

    private static func validQuery(_ query: String) -> Bool {
        !query.isEmpty && query.utf8.count <= maximumQueryBytes
    }

    private static func trim(_ entries: [String: Entry], to limit: Int) -> [String: Entry] {
        guard entries.count > limit else { return entries }
        let kept = entries.sorted {
            if $0.value.lastUsed != $1.value.lastUsed { return $0.value.lastUsed > $1.value.lastUsed }
            return $0.key < $1.key
        }.prefix(limit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private mutating func enforceLimits() {
        if results.count > Self.maximumResults {
            results = Self.trim(results, to: Self.maximumResults)
            queries = queries.compactMapValues { selections in
                let kept = selections.filter { results[$0.key] != nil }
                return kept.isEmpty ? nil : kept
            }
        }
        if queries.count > Self.maximumQueries {
            let newest = queries.map { key, selections in
                (key, selections.values.map(\.lastUsed).max() ?? .distantPast)
            }.sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0 < $1.0
            }.prefix(Self.maximumQueries)
            let kept = Set(newest.map(\.0))
            queries = queries.filter { kept.contains($0.key) }
        }
    }

    // Query selections refer to the result table by index, so long application
    // paths are stored once instead of repeated for every remembered query.
    private struct StoredResult: Codable {
        let id: String
        let usage: Entry
    }

    private struct StoredSelection: Codable {
        let result: Int
        let usage: Entry
    }

    private struct StoredQuery: Codable {
        let query: String
        let selections: [StoredSelection]
    }

    private enum CodingKeys: String, CodingKey { case results, queries }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedResults = try container.decode([StoredResult].self, forKey: .results)
        let storedQueries = try container.decode([StoredQuery].self, forKey: .queries)
        for result in storedResults where Self.validResultID(result.id) && result.usage.isValid {
            if let previous = results[result.id], previous.lastUsed >= result.usage.lastUsed { continue }
            results[result.id] = result.usage
        }
        results = Self.trim(results, to: Self.maximumResults)
        for storedQuery in storedQueries {
            let query = SearchEngine.normalize(storedQuery.query)
            guard Self.validQuery(query) else { continue }
            var selections = queries[query] ?? [:]
            for selection in storedQuery.selections where selection.usage.isValid {
                guard storedResults.indices.contains(selection.result) else { continue }
                let id = storedResults[selection.result].id
                guard results[id] != nil else { continue }
                if let previous = selections[id], previous.lastUsed >= selection.usage.lastUsed { continue }
                selections[id] = selection.usage
            }
            if !selections.isEmpty { queries[query] = Self.trim(selections, to: Self.maximumResultsPerQuery) }
        }
        enforceLimits()
    }

    public func encode(to encoder: any Encoder) throws {
        let storedResults = results.sorted { $0.key < $1.key }.map { StoredResult(id: $0.key, usage: $0.value) }
        let indices = Dictionary(uniqueKeysWithValues: storedResults.enumerated().map { ($0.element.id, $0.offset) })
        let storedQueries = queries.sorted { $0.key < $1.key }.map { query, selections in
            StoredQuery(query: query, selections: selections.sorted { $0.key < $1.key }.compactMap { id, entry in
                guard let index = indices[id] else { return nil }
                return StoredSelection(result: index, usage: entry)
            })
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storedResults, forKey: .results)
        try container.encode(storedQueries, forKey: .queries)
    }
}

/// Precomputed scores: no persistence, clocks, or decay math on a search keystroke.
public struct SearchUsageSnapshot: Equatable, Sendable {
    public static let empty = SearchUsageSnapshot(general: [:], queries: [:])

    fileprivate let general: [String: Double]
    fileprivate let queries: [String: [String: Double]]

    var isEmpty: Bool { general.isEmpty && queries.isEmpty }

    func scorer(normalizedQuery: String) -> Scorer {
        Scorer(general: general, query: queries[normalizedQuery] ?? [:])
    }

    struct Signal: Comparable {
        static let zero = Signal(query: 0, general: 0)
        let query: Double
        let general: Double

        static func < (left: Signal, right: Signal) -> Bool {
            if left.query != right.query { return left.query < right.query }
            return left.general < right.general
        }
    }

    struct Scorer {
        let general: [String: Double]
        let query: [String: Double]

        var hasQueryHistory: Bool { !query.isEmpty }

        func signal(for resultID: String) -> Signal {
            Signal(query: query[resultID] ?? 0, general: general[resultID] ?? 0)
        }
    }
}
