/// A selectable application or a built-in Cue command.
public enum LauncherResult: Identifiable, Hashable, Sendable {
    case application(IndexedApplication)
    case updateIndex
    case clipboardHistory
    case sleep
    case lockScreen

    public var id: String {
        switch self {
        case .application(let application): application.searchUsageID
        case .updateIndex: "command:update-index"
        case .clipboardHistory: "command:clipboard-history"
        case .sleep: "command:sleep"
        case .lockScreen: "command:lock-screen"
        }
    }

    public var name: String {
        switch self {
        case .application(let application): application.name
        case .updateIndex: "Update App Index"
        case .clipboardHistory: "Clipboard History"
        case .sleep: "Sleep"
        case .lockScreen: "Lock Screen"
        }
    }

    private static let updateIndexAliases = [
        "update app index", "update index", "refresh apps", "refresh index",
        "reindex", "rebuild index", "更新索引", "更新應用程式索引", "重新索引", "重建索引", "重新掃描",
    ].map(SearchEngine.normalize)

    private static let clipboardAliases = [
        "clipboard", "clipboard history", "paste history", "copy history",
        "剪貼簿", "剪貼簿歷史", "剪貼簿記錄", "剪貼簿紀錄", "剪貼板", "複製紀錄", "複製記錄",
    ].map(SearchEngine.normalize)

    private static let sleepAliases = [
        "sleep", "sleep mac", "sleep computer",
        "睡眠", "讓電腦睡眠", "電腦睡眠",
    ].map(SearchEngine.normalize)

    private static let lockScreenAliases = [
        "lock", "lock screen", "lock mac", "lock computer",
        "鎖定", "鎖定螢幕", "鎖定畫面", "鎖定電腦", "鎖屏",
    ].map(SearchEngine.normalize)

    public static func search(
        _ applications: [IndexedApplication],
        query: String,
        usage: SearchUsageSnapshot = .empty
    ) -> [LauncherResult] {
        let query = SearchEngine.normalize(query)
        guard !query.isEmpty else { return [] }
        let applications = SearchEngine.search(applications, normalizedQuery: query, usage: usage).map(Self.application)

        // Avoid crowding normal app searches with a command for one Latin letter.
        let isSingleASCIICharacter = query.count == 1 && query.unicodeScalars.allSatisfy(\.isASCII)
        guard !isSingleASCIICharacter else { return applications }
        var commands: [LauncherResult] = []
        if clipboardAliases.contains(where: { $0.contains(query) }) { commands.append(.clipboardHistory) }
        if updateIndexAliases.contains(where: { $0.contains(query) }) { commands.append(.updateIndex) }
        if sleepAliases.contains(where: { $0.contains(query) }) { commands.append(.sleep) }
        if lockScreenAliases.contains(where: { $0.contains(query) }) { commands.append(.lockScreen) }
        if commands.count > 1 && !usage.isEmpty {
            let scorer = usage.scorer(normalizedQuery: query)
            commands = commands.enumerated().map { ($0.offset, $0.element, scorer.signal(for: $0.element.id)) }
                .sorted {
                    if $0.2 != $1.2 { return $0.2 > $1.2 }
                    return $0.0 < $1.0
                }.map(\.1)
        }
        return commands + applications
    }
}
