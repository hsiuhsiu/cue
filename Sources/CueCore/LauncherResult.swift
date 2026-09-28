/// A selectable application or a built-in Cue command.
public enum LauncherResult: Identifiable, Hashable, Sendable {
    case application(IndexedApplication)
    case updateIndex
    case clipboardHistory
    case sleep
    case lockScreen
    case screenOff
    case convertToTraditional
    case convertToSimplified
    case chineseConversionSettings

    public var id: String {
        switch self {
        case .application(let application): application.searchUsageID
        case .updateIndex: "command:update-index"
        case .clipboardHistory: "command:clipboard-history"
        case .sleep: "command:sleep"
        case .lockScreen: "command:lock-screen"
        case .screenOff: "command:screen-off"
        case .convertToTraditional: "command:convert-to-traditional"
        case .convertToSimplified: "command:convert-to-simplified"
        case .chineseConversionSettings: "command:chinese-conversion-settings"
        }
    }

    public var name: String {
        switch self {
        case .application(let application): application.name
        case .updateIndex: "Update App Index"
        case .clipboardHistory: "Clipboard History"
        case .sleep: "Sleep"
        case .lockScreen: "Lock Screen"
        case .screenOff: "Screen Off"
        case .convertToTraditional: "Convert to Traditional Chinese"
        case .convertToSimplified: "Convert to Simplified Chinese"
        case .chineseConversionSettings: "Chinese Conversion Settings"
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

    private static let screenOffAliases = [
        "screen off", "display off", "turn off screen", "turn off display",
        "關閉螢幕", "關螢幕", "螢幕關閉", "關閉顯示器", "關閉畫面",
    ].map(SearchEngine.normalize)

    private static let chineseConversionAliases = [
        "convert chinese", "chinese converter", "chinese conversion",
        "繁簡轉換", "繁简转换", "簡繁轉換", "简繁转换", "中文轉換", "中文转换",
    ].map(SearchEngine.normalize)

    private static let traditionalAliases = [
        "convert to traditional chinese", "traditional chinese taiwan", "s2t",
        "轉換為正體中文", "轉換為繁體中文", "正體中文", "繁體中文",
        "台灣正體", "臺灣正體", "台灣用語", "臺灣用語",
        "簡轉繁", "简转繁", "轉正體", "轉繁體", "转繁体", "转正体", "台湾繁体",
    ].map(SearchEngine.normalize)

    private static let simplifiedAliases = [
        "convert to simplified chinese", "simplified chinese mainland china", "t2s",
        "轉換為簡體中文", "簡體中文", "简体中文", "大陸用語", "大陆用语",
        "繁轉簡", "繁转简", "轉簡體", "转简体",
    ].map(SearchEngine.normalize)

    private static let conversionSettingsAliases = [
        "chinese conversion settings", "chinese settings", "conversion settings",
        "簡繁設定", "簡繁轉換設定", "繁簡設定", "繁簡轉換設定", "中文轉換設定",
        "简繁设置", "简繁转换设置", "繁简设置", "繁简转换设置", "中文转换设置",
    ].map(SearchEngine.normalize)

    public static func search(
        _ applications: [IndexedApplication],
        query: String,
        usage: SearchUsageSnapshot = .empty,
        conversionAliases: ChineseConversionAliases = .defaults
    ) -> [LauncherResult] {
        let query = SearchEngine.normalize(query)
        guard !query.isEmpty else { return [] }
        let applications = SearchEngine.search(applications, normalizedQuery: query, usage: usage).map(Self.application)
        let exactAlias = conversionAliases.command(normalizedQuery: query)

        // Avoid crowding normal app searches with a command for one Latin letter.
        let isSingleASCIICharacter = query.count == 1 && query.unicodeScalars.allSatisfy(\.isASCII)
        guard !isSingleASCIICharacter else {
            return exactAlias.map { [$0] + applications } ?? applications
        }
        var commands: [LauncherResult] = []
        if clipboardAliases.contains(where: { $0.contains(query) }) { commands.append(.clipboardHistory) }
        if updateIndexAliases.contains(where: { $0.contains(query) }) { commands.append(.updateIndex) }
        if sleepAliases.contains(where: { $0.contains(query) }) { commands.append(.sleep) }
        if lockScreenAliases.contains(where: { $0.contains(query) }) { commands.append(.lockScreen) }
        if screenOffAliases.contains(where: { $0.contains(query) }) { commands.append(.screenOff) }
        let matchesChineseConversion = chineseConversionAliases.contains(where: { $0.contains(query) })
        if matchesChineseConversion || traditionalAliases.contains(where: { $0.contains(query) }) {
            commands.append(.convertToTraditional)
        }
        if matchesChineseConversion || simplifiedAliases.contains(where: { $0.contains(query) }) {
            commands.append(.convertToSimplified)
        }
        if conversionSettingsAliases.contains(where: { $0.contains(query) }) {
            commands.append(.chineseConversionSettings)
        }
        if commands.count > 1 && !usage.isEmpty {
            let scorer = usage.scorer(normalizedQuery: query)
            commands = commands.enumerated().map { ($0.offset, $0.element, scorer.signal(for: $0.element.id)) }
                .sorted {
                    if $0.2 != $1.2 { return $0.2 > $1.2 }
                    return $0.0 < $1.0
                }.map(\.1)
        }
        // An explicitly configured exact alias wins over learned/default command
        // ordering. Ordinary aliases keep their existing substring behavior.
        if let exactAlias {
            commands.removeAll { $0 == exactAlias }
            commands.insert(exactAlias, at: 0)
        }
        return commands + applications
    }
}
