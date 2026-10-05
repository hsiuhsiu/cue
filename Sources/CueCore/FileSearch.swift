import Foundation

/// An explicit launcher mode; ordinary application queries never enter file search.
public struct FileSearchQuery: Equatable, Sendable {
    public static let maximumTermUTF8Count = 1_024

    public let term: String
    public let isTooLong: Bool
    public var canSearch: Bool { !isTooLong && !term.isEmpty }

    public static func parse(_ input: String) -> FileSearchQuery? {
        var bytes = input.utf8.makeIterator()
        guard let first = bytes.next(), first == 102 || first == 70,
              bytes.next() == 32 else { return nil }

        // Bound validation before trimming/copying: a pasted document must not turn
        // the typing path into a full-document scan or a metadata query.
        // Work in UTF-8, not graphemes: a space followed by millions of combining
        // marks can itself be one Character, making String.dropFirst unbounded.
        let suffixBytes = input.utf8.dropFirst(2).prefix(maximumTermUTF8Count + 1)
        guard suffixBytes.count <= maximumTermUTF8Count else {
            return FileSearchQuery(term: "", isTooLong: true)
        }
        let suffix = String(decoding: suffixBytes, as: UTF8.self)
        return FileSearchQuery(
            term: suffix.trimmingCharacters(in: .whitespacesAndNewlines), isTooLong: false
        )
    }
}

/// Only Spotlight filename/path metadata is retained. File contents are never read.
public struct FileSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let parentPath: String
    public let isDirectory: Bool
    fileprivate let path: String

    public init(url: URL, name: String, parentPath: String, isDirectory: Bool = false) {
        let originalPath = url.path
        let path = url.isFileURL ? FileSearchRanking.canonicalPath(originalPath) : originalPath
        self.id = "file:" + path
        self.url = path == originalPath ? url : URL(fileURLWithPath: path, isDirectory: isDirectory)
        self.name = name
        self.parentPath = url.isFileURL ? FileSearchRanking.canonicalPath(parentPath) : parentPath
        self.isDirectory = isDirectory
        self.path = path
    }
}

public enum FileSearchFailure: Equatable, Sendable {
    case unavailable
}

public struct FileSearchResponse: Equatable, Sendable {
    public let results: [FileSearchResult]
    public let error: FileSearchFailure?

    public init(results: [FileSearchResult], error: FileSearchFailure? = nil) {
        self.results = results
        self.error = error
    }
}

public enum FileSearchRanking {
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let dataVolumePrefix = "/System/Volumes/Data/"

    /// Spotlight can expose the backing APFS Data-volume path for a normal
    /// document. Map only standard user-facing firmlinks, using strings alone:
    /// an arbitrary Data-volume directory need not exist at the root volume.
    /// Never resolve symlinks or inspect files/cloud placeholders while searching.
    public static func canonicalPath(_ path: String) -> String {
        guard path.hasPrefix(dataVolumePrefix) else { return path }
        let suffix = path.dropFirst(dataVolumePrefix.count - 1)
        guard suffix == "/Users" || suffix.hasPrefix("/Users/")
                || suffix == "/Applications" || suffix.hasPrefix("/Applications/")
                || suffix == "/Volumes" || suffix.hasPrefix("/Volumes/") else { return path }
        return String(suffix)
    }

    /// Exact filename, filename prefix, then literal substring; ties are stable.
    /// The caller supplies a bounded metadata candidate set, never a directory crawl.
    public static func results(
        from candidates: [FileSearchResult], term: String, limit: Int
    ) -> [FileSearchResult] {
        guard !term.isEmpty, limit > 0 else { return [] }
        let needle = folded(term)
        let capacity = min(limit, 9)
        var seen = Set<String>()
        seen.reserveCapacity(candidates.count)
        var ranked: [RankedResult] = []
        ranked.reserveCapacity(capacity + 1)
        for result in candidates {
            guard result.url.isFileURL, seen.insert(result.path).inserted,
                  isUserFacingPath(result.path) else { continue }
            let name = folded(result.name)
            // Recheck literally even though Spotlight already filters. A '*' or
            // '?' in user input must never broaden the displayed matches.
            guard name.contains(needle) else { continue }
            let score = name == needle ? 0 : (name.hasPrefix(needle) ? 1 : 2)
            let candidate = RankedResult(result: result, score: score, foldedName: name)
            // Only nine rows can be displayed. Keep that small sorted window
            // instead of sorting/materializing every metadata candidate. Most
            // candidates need only one comparison after the window fills.
            if ranked.count == capacity, let last = ranked.last,
               !candidate.precedes(last) { continue }
            let insertion = ranked.firstIndex { candidate.precedes($0) } ?? ranked.endIndex
            ranked.insert(candidate, at: insertion)
            if ranked.count > capacity { ranked.removeLast() }
        }
        return ranked.map(\.result)
    }

    private struct RankedResult {
        let result: FileSearchResult
        let score: Int
        let foldedName: String

        func precedes(_ other: Self) -> Bool {
            if score != other.score { return score < other.score }
            if foldedName != other.foldedName { return foldedName < other.foldedName }
            if result.name != other.result.name { return result.name < other.result.name }
            return result.path < other.result.path
        }
    }

    public static func isUserFacingPath(_ path: String) -> Bool {
        let path = canonicalPath(path)
        guard path.hasPrefix("/"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/")
        guard !parts.isEmpty, !parts.contains(where: { $0.hasPrefix(".") }) else { return false }
        if ["System", "Library", "usr", "bin", "sbin", "dev", "private"].contains(parts[0]) {
            return false
        }
        if parts.count >= 3, parts[0] == "Users", parts[2] == "Library" {
            // These are user document locations despite living under Library.
            // Spotlight metadata access does not download placeholder contents.
            guard parts.count >= 4,
                  parts[3] == "Mobile Documents" || parts[3] == "CloudStorage" else { return false }
        }
        // A bundle itself may be opened, but its resources aren't user documents.
        if parts.dropLast().contains(where: {
            $0.hasSuffix(".app") || $0.hasSuffix(".framework") || $0.hasSuffix(".bundle")
        }) { return false }
        return true
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }
}
