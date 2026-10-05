import Foundation

public enum CurrencyConversionStatus: Hashable, Sendable {
    case networkRequired, loading, unavailable, unsupported
}

/// A selectable application, built-in command, or action on the current query.
public enum LauncherResult: Identifiable, Hashable, Sendable {
    case application(IndexedApplication)
    case file(FileSearchResult)
    case updateIndex
    case clipboardHistory
    case sleep
    case lockScreen
    case screenOff
    case windowControls
    case windowSettings
    case convertToTraditional
    case convertToSimplified
    case chineseConversionSettings
    case googleSearch
    case googleSearchIn(WebSearchBrowser)
    case webSearchSettings
    case chooseSearchBrowser
    case askGPT
    case translateGPT
    case gptSettings
    case cleanLink
    case emojiSearch
    case calculation(CalculatorResult)
    case conversion(ConversionResult)
    case currencyStatus(CurrencyConversionStatus)

    /// Keep expressions and numeric results out of identifiers and usage history.
    public static let calculationID = "action:calculate"
    public static let conversionIDPrefix = "action:convert:"
    public static let currencyStatusID = "action:currency-status"

    public var numericCopyValue: String? {
        switch self {
        case .calculation(let result): result.value
        case .conversion(let result): result.value
        default: nil
        }
    }

    public var id: String {
        switch self {
        case .application(let application): application.searchUsageID
        case .file(let file): file.id
        case .updateIndex: "command:update-index"
        case .clipboardHistory: "command:clipboard-history"
        case .sleep: "command:sleep"
        case .lockScreen: "command:lock-screen"
        case .screenOff: "command:screen-off"
        case .windowControls: "command:window-controls"
        case .windowSettings: "command:window-settings"
        case .convertToTraditional: "command:convert-to-traditional"
        case .convertToSimplified: "command:convert-to-simplified"
        case .chineseConversionSettings: "command:chinese-conversion-settings"
        case .googleSearch: "action:google-search"
        case .googleSearchIn(let browser): "action:google-search:\(browser.bundleIdentifier)"
        case .webSearchSettings: "command:web-search-settings"
        case .chooseSearchBrowser: "action:google-search:browsers"
        case .askGPT: "action:gpt-answer"
        case .translateGPT: "action:gpt-translate"
        case .gptSettings: "command:gpt-settings"
        case .cleanLink: "command:clean-link"
        case .emojiSearch: "command:emoji-search"
        case .calculation: Self.calculationID
        case .conversion(let result): Self.conversionIDPrefix + result.targetID
        case .currencyStatus: Self.currencyStatusID
        }
    }

    public var name: String {
        switch self {
        case .application(let application): application.name
        case .file(let file): file.name
        case .updateIndex: "Update App Index"
        case .clipboardHistory: "Clipboard History"
        case .sleep: "Sleep"
        case .lockScreen: "Lock Screen"
        case .screenOff: "Screen Off"
        case .windowControls: "Window Controls"
        case .windowSettings: "Window Settings"
        case .convertToTraditional: "Convert to Traditional Chinese"
        case .convertToSimplified: "Convert to Simplified Chinese"
        case .chineseConversionSettings: "Chinese Conversion Settings"
        case .googleSearch: "Search Google"
        case .googleSearchIn(let browser): "Search Google in \(browser.name)"
        case .webSearchSettings: "Google Search Settings"
        case .chooseSearchBrowser: "Choose Search Browser"
        case .askGPT: "Ask GPT"
        case .translateGPT: "Translate with GPT"
        case .gptSettings: "GPT Settings"
        case .cleanLink: "Clean Link"
        case .emojiSearch: "Emoji Search"
        case .calculation(let result): result.value
        case .conversion(let result): result.value + " " + result.unitSymbol
        case .currencyStatus: "Currency Conversion"
        }
    }

    /// Query actions must not store the user's arbitrary search text as launch history.
    public var isWebSearch: Bool {
        switch self {
        case .googleSearch, .googleSearchIn: true
        default: false
        }
    }

    public var isGPTAction: Bool { self == .askGPT || self == .translateGPT }

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

    private static let webSearchSettingsAliases = [
        "google settings", "google search settings", "browser settings", "web search settings",
        "Google 搜尋設定", "搜尋瀏覽器設定", "瀏覽器設定",
        "Google 搜索设置", "搜索浏览器设置", "浏览器设置",
    ].map(SearchEngine.normalize)

    private static let cleanLinkAliases = [
        "clean link", "link cleaner", "clean url", "remove tracking",
        "清理連結", "清理網址", "連結清理", "移除追蹤",
    ].map(SearchEngine.normalize)

    private static let gptSettingsAliases = [
        "gpt settings", "chatgpt settings", "openai settings", "api key",
        "GPT 設定", "ChatGPT 設定", "翻譯設定", "翻译设置",
    ].map(SearchEngine.normalize)

    private static let emojiAliases = [
        "emoji", "emoji search", "emoji finder", "emoticons",
        "表情符號", "表情", "表情搜尋", "搜尋表情符號", "繪文字",
    ].map(SearchEngine.normalize)

    private static let windowAliases = ["window", "window controls", "resize", "move window", "moom", "視窗", "視窗調整", "調整視窗", "移動視窗"].map(SearchEngine.normalize)
    private static let windowSettingsAliases = ["window settings", "window layout settings", "視窗設定", "視窗配置設定"].map(SearchEngine.normalize)

    public static func search(
        _ applications: [IndexedApplication],
        query: String,
        usage: SearchUsageSnapshot = .empty,
        conversionAliases: ChineseConversionAliases = .defaults,
        includeGoogleFallback: Bool = false,
        conversionResults: [ConversionResult]? = nil,
        currencyStatus: CurrencyConversionStatus? = nil
    ) -> [LauncherResult] {
        // File queries have their own asynchronous index and must never fall
        // through to application matching or external text actions.
        guard FileSearchQuery.parse(query) == nil else { return [] }
        guard SearchEngine.acceptsQuery(query) else {
            return includeGoogleFallback && query.unicodeScalars.contains(where: {
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }) ? [.googleSearch] : []
        }
        // The calculator rejects ordinary text before parsing or allocating. Use
        // the original expression: search normalization is not math normalization.
        let calculation = Calculator.evaluate(query).map(Self.calculation)
        let conversionQuery = ConversionQuery.parse(query)
        var conversions = (conversionResults ?? conversionQuery.map { UnitConversion.convert($0) } ?? [])
            .map(Self.conversion)
        if conversionQuery?.source.isCurrency == true, conversions.isEmpty {
            conversions = [.currencyStatus(currencyStatus ?? .networkRequired)]
        }
        let normalizedQuery = SearchEngine.normalize(query)
        guard !normalizedQuery.isEmpty else {
            // Folding may erase a non-whitespace character (for example a lone
            // combining accent). It is still usable as a literal web query.
            return includeGoogleFallback && query.contains(where: { !$0.isWhitespace }) ? [.googleSearch] : []
        }
        let query = normalizedQuery
        let matchingApplications = SearchEngine.search(applications, normalizedQuery: query, usage: usage)
        // Exact user aliases form the first app rank category. Count that small
        // prefix once so it can also precede ordinary built-in commands.
        let pinnedApplicationCount = matchingApplications.prefix { $0.normalizedSearchAlias == query }.count
        let applications = matchingApplications.map(Self.application)
        let exactAlias = conversionAliases.command(normalizedQuery: query)

        // Avoid crowding normal app searches with a command for one Latin letter.
        let isSingleASCIICharacter = query.count == 1 && query.unicodeScalars.allSatisfy(\.isASCII)
        guard !isSingleASCIICharacter else {
            let matches = exactAlias.map { [$0] + applications } ?? applications
            return matches.isEmpty && includeGoogleFallback ? [.googleSearch] : matches
        }
        var commands: [LauncherResult] = []
        if clipboardAliases.contains(where: { $0.contains(query) }) { commands.append(.clipboardHistory) }
        if updateIndexAliases.contains(where: { $0.contains(query) }) { commands.append(.updateIndex) }
        if sleepAliases.contains(where: { $0.contains(query) }) { commands.append(.sleep) }
        if lockScreenAliases.contains(where: { $0.contains(query) }) { commands.append(.lockScreen) }
        if screenOffAliases.contains(where: { $0.contains(query) }) { commands.append(.screenOff) }
        if windowAliases.contains(where: { $0.hasPrefix(query) }) { commands.append(.windowControls) }
        if (query.contains("setting") || query.contains("設定")), windowSettingsAliases.contains(where: { $0.contains(query) }) { commands.append(.windowSettings) }
        if cleanLinkAliases.contains(where: { $0.contains(query) }) { commands.append(.cleanLink) }
        // Generic "search"/"finder" queries still belong to apps or web search.
        if query != "搜尋", emojiAliases.contains(where: { $0.hasPrefix(query) }) {
            commands.append(.emojiSearch)
        }
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
        // A plain query such as "Google" must stay available for web search.
        // Require settings intent before matching this feature's settings aliases.
        if (query.contains("setting") || query.contains("設定") || query.contains("设置")),
           webSearchSettingsAliases.contains(where: { $0.contains(query) }) {
            commands.append(.webSearchSettings)
        }
        if gptSettingsAliases.contains(where: { $0.hasPrefix(query) }) {
            commands.append(.gptSettings)
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
        if calculation == nil && conversions.isEmpty && commands.isEmpty && applications.isEmpty && includeGoogleFallback { return [.googleSearch] }
        let matches: [LauncherResult]
        if pinnedApplicationCount > 0 {
            let scorer = usage.isEmpty ? nil : usage.scorer(normalizedQuery: query)
            matches = merge(commands: commands, applications: applications,
                            scorer: scorer?.hasQueryHistory == true ? scorer : nil,
                            pinnedCommand: exactAlias, pinnedApplicationCount: pinnedApplicationCount)
        } else if commands.isEmpty || applications.isEmpty || usage.isEmpty {
            matches = commands + applications
        } else {
            let scorer = usage.scorer(normalizedQuery: query)
            matches = scorer.hasQueryHistory
                ? merge(commands: commands, applications: applications,
                        scorer: scorer, pinnedCommand: exactAlias)
                : commands + applications
        }
        return conversions + (calculation.map { [$0] } ?? []) + matches
    }

    /// A choice for this exact query may cross the command/app boundary. Keep
    /// each group's existing order, so app text-match categories remain intact;
    /// general popularity alone must not displace a command for a new query.
    private static func merge(
        commands: [LauncherResult], applications: [LauncherResult],
        scorer: SearchUsageSnapshot.Scorer?, pinnedCommand: LauncherResult?,
        pinnedApplicationCount: Int = 0
    ) -> [LauncherResult] {
        var matches: [LauncherResult] = []
        matches.reserveCapacity(commands.count + applications.count)
        var commandIndex = 0
        var applicationIndex = 0
        if let pinnedCommand, commands.first == pinnedCommand {
            matches.append(pinnedCommand)
            commandIndex = 1
        }
        matches.append(contentsOf: applications.prefix(pinnedApplicationCount))
        applicationIndex = pinnedApplicationCount
        guard let scorer, commandIndex < commands.count, applicationIndex < applications.count else {
            matches.append(contentsOf: commands[commandIndex...])
            matches.append(contentsOf: applications[applicationIndex...])
            return matches
        }

        // Read each head's precomputed query score once. Merging is linear and
        // does not sort the app values again or perform persistence work.
        var commandScore = scorer.signal(for: commands[commandIndex].id).query
        var applicationScore = scorer.signal(for: applications[applicationIndex].id).query
        while commandIndex < commands.count && applicationIndex < applications.count {
            if applicationScore > commandScore {
                matches.append(applications[applicationIndex])
                applicationIndex += 1
                if applicationIndex < applications.count {
                    applicationScore = scorer.signal(for: applications[applicationIndex].id).query
                }
            } else {
                // Equal query scores retain the original command-first order.
                matches.append(commands[commandIndex])
                commandIndex += 1
                if commandIndex < commands.count {
                    commandScore = scorer.signal(for: commands[commandIndex].id).query
                }
            }
        }
        matches.append(contentsOf: commands[commandIndex...])
        matches.append(contentsOf: applications[applicationIndex...])
        return matches
    }
}
