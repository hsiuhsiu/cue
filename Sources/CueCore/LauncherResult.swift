/// A selectable application or Cue's built-in index refresh command.
public enum LauncherResult: Identifiable, Hashable, Sendable {
    case application(IndexedApplication)
    case updateIndex

    public var id: String {
        switch self {
        case .application(let application): "app:" + application.id
        case .updateIndex: "command:update-index"
        }
    }

    public var name: String {
        switch self {
        case .application(let application): application.name
        case .updateIndex: "Update App Index"
        }
    }

    private static let updateIndexAliases = [
        "update app index", "update index", "refresh apps", "refresh index",
        "reindex", "rebuild index", "更新索引", "更新應用程式索引", "重新索引", "重建索引", "重新掃描",
    ].map(SearchEngine.normalize)

    public static func search(
        _ applications: [IndexedApplication],
        query: String
    ) -> [LauncherResult] {
        let query = SearchEngine.normalize(query)
        let applications = SearchEngine.search(applications, normalizedQuery: query).map(Self.application)
        guard !query.isEmpty else { return applications + [.updateIndex] }

        // Avoid crowding normal app searches with a command for one Latin letter.
        let isSingleASCIICharacter = query.count == 1 && query.unicodeScalars.allSatisfy(\.isASCII)
        let matchesCommand = !isSingleASCIICharacter
            && updateIndexAliases.contains { $0.contains(query) }
        return matchesCommand ? [.updateIndex] + applications : applications
    }
}
