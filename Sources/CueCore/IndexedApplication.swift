import Foundation

/// The small, immutable portion of an installed app needed by search and presentation.
public struct IndexedApplication: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let bundleIdentifier: String?

    let searchableName: String
    let searchableCharacters: [Character]
    let wordStarts: [Int]
    let wordSuffixes: [String]
    let initials: [Character]

    public init(
        id: String? = nil,
        name: String,
        url: URL,
        bundleIdentifier: String? = nil
    ) {
        self.id = id ?? url.standardizedFileURL.path
        self.name = name
        self.url = url
        self.bundleIdentifier = bundleIdentifier

        let searchableName = SearchEngine.normalize(name)
        let characters = Array(searchableName)
        self.searchableName = searchableName
        self.searchableCharacters = characters
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
            String(searchableName[searchableName.index(searchableName.startIndex, offsetBy: offset)...])
        }
    }
}
