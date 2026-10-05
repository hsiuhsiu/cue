import Foundation

/// The small, immutable portion of an installed app needed by search and presentation.
public struct IndexedApplication: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let bundleIdentifier: String?
    public let aliasPreferenceID: String
    public private(set) var searchAlias: String?

    let searchableName: String
    let searchNames: [SearchName]
    private(set) var normalizedSearchAlias: String?
    private(set) var searchAliasLength = 0
    let searchUsageID: String

    public init(
        id: String? = nil,
        name: String,
        url: URL,
        bundleIdentifier: String? = nil,
        searchNames: [String] = [],
        searchAlias: String? = nil
    ) {
        self.id = id ?? url.standardizedFileURL.path
        self.name = name
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.searchUsageID = "app:" + self.id
        let identifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliasPreferenceID = identifier.flatMap { $0.isEmpty ? nil : "bundle:" + $0.lowercased() }
            ?? "path:" + url.standardizedFileURL.path

        let searchableName = SearchEngine.normalize(name)
        self.searchableName = searchableName
        var seenNames = Set<String>()
        self.searchNames = ([searchableName] + searchNames.map(SearchEngine.normalize)).compactMap { name in
            guard !name.isEmpty, seenNames.insert(name).inserted else { return nil }
            return SearchName(normalizedName: name)
        }
        self.setSearchAlias(searchAlias)
    }

    /// Reuse the automatic names and tokens when a preference changes. IDs and
    /// launch history remain tied to the original application, never its alias.
    public func withSearchAlias(_ alias: String?) -> IndexedApplication {
        var application = self
        application.setSearchAlias(alias)
        return application
    }

    private mutating func setSearchAlias(_ alias: String?) {
        let normalized = alias.map(SearchEngine.normalize)
        normalizedSearchAlias = normalized.flatMap { $0.isEmpty ? nil : $0 }
        searchAliasLength = normalizedSearchAlias?.count ?? 0
        searchAlias = normalizedSearchAlias == nil ? nil : alias?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// All string normalization and token preparation happens while constructing
/// the index, never inside the per-application search loop.
struct SearchName: Hashable, Sendable {
    let name: String
    let characters: [Character]
    /// Latin application names dominate most indexes. Keep their byte spelling
    /// beside the Unicode tokens so substring matching can avoid NSString/ICU.
    /// Non-ASCII names retain the Unicode search path and its matching rules.
    let asciiBytes: [UInt8]?
    let wordStarts: [Int]
    let wordSuffixes: [String]
    let initials: [Character]

    init(normalizedName name: String) {
        self.name = name
        let characters = Array(name)
        self.characters = characters
        let bytes = Array(name.utf8)
        self.asciiBytes = bytes.count <= 512 && bytes.allSatisfy { $0 < 128 } ? bytes : nil
        let wordStarts = characters.indices.filter { index in
            let isWordCharacter = characters[index].isLetter || characters[index].isNumber
            let followsSeparator = index == 0
                || !(characters[index - 1].isLetter || characters[index - 1].isNumber)
            return isWordCharacter && followsSeparator
        }
        self.wordStarts = wordStarts
        self.initials = wordStarts.map { characters[$0] }
        // Preparing suffixes once keeps native String prefix matching fast and
        // avoids constructing a new String for every word on every keystroke.
        self.wordSuffixes = wordStarts.dropFirst().map { offset in
            String(name[name.index(name.startIndex, offsetBy: offset)...])
        }
    }
}
