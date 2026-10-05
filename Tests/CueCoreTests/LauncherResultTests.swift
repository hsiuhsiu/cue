import Foundation
import XCTest
import CueCore

final class LauncherResultTests: XCTestCase {
    func testLongTextOffersAnExplicitActionWithoutAppOrNumericMatching() {
        let limit = SearchEngine.maximumQueryUTF8Length
        let longCluster = "a" + String(repeating: "\u{301}", count: limit)
        for query in [String(repeating: "text ", count: limit), longCluster,
                      String(repeating: " ", count: limit + 1) + "a",
                      "1+1" + String(repeating: " ", count: limit)] {
            XCTAssertEqual(LauncherResult.search([app("a")], query: query, includeGoogleFallback: true),
                           [.googleSearch])
            XCTAssertTrue(LauncherResult.search([app("a")], query: query, includeGoogleFallback: false).isEmpty)
        }
        XCTAssertTrue(LauncherResult.search([app("a")],
            query: String(repeating: "\t\n　", count: limit), includeGoogleFallback: true).isEmpty)
        XCTAssertEqual(LauncherResult.search([], query: "2^8").first?.numericCopyValue, "256")
    }

    func testCalculatorResultPrecedesLocalMatchesWithoutGoogleFallback() throws {
        let expression = "2+3*4"
        let result = try XCTUnwrap(Calculator.evaluate(expression))
        let applications = [app(expression), app("Calculator")]
        XCTAssertEqual(LauncherResult.search(applications, query: expression, includeGoogleFallback: true),
                       [.calculation(result), .application(applications[0])])
        XCTAssertEqual(LauncherResult.search([], query: expression, includeGoogleFallback: true), [.calculation(result)])
        XCTAssertEqual(LauncherResult.search([], query: expression, includeGoogleFallback: false), [.calculation(result)])
        XCTAssertEqual(LauncherResult.calculation(result).id, LauncherResult.calculationID)
        XCTAssertEqual(LauncherResult.calculation(result).name, "14")
        XCTAssertFalse(LauncherResult.calculation(result).isWebSearch)
    }

    func testCalculatorLeavesOrdinaryAndIncompleteSearchesAlone() throws {
        let applications = [app("1Password"), app("123"), app("Calendar")]
        for (query, index) in [("1Password", 0), ("123", 1), ("Calendar", 2)] {
            XCTAssertEqual(LauncherResult.search(applications, query: query), [.application(applications[index])])
        }
        for query in ["2+", "(2+3", "1/0", "123 invalid", "-2+3"] {
            XCTAssertEqual(LauncherResult.search([], query: query, includeGoogleFallback: true), [.googleSearch], query)
        }
        let first = try XCTUnwrap(Calculator.evaluate("1+1"))
        let second = try XCTUnwrap(Calculator.evaluate("1+2"))
        XCTAssertEqual(LauncherResult.calculation(first).id, LauncherResult.calculation(second).id)
        XCTAssertNotEqual(LauncherResult.calculation(first), LauncherResult.calculation(second))
    }

    private func app(_ name: String, id: String? = nil) -> IndexedApplication {
        IndexedApplication(
            id: id,
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    func testEnglishAliasesFindUpdateCommand() {
        for query in [
            "update app index", "update index", "refresh apps", "refresh index",
            "reindex", "rebuild index", "update", "refresh", "index",
        ] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.updateIndex], query)
        }
    }

    func testTraditionalChineseAliasesFindUpdateCommand() {
        for query in ["更新索引", "更新應用程式索引", "重新索引", "重建索引", "重新掃描", "更新", "索引"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.updateIndex], query)
        }
    }

    func testCaseAndWhitespaceAreNormalized() {
        for query in [" \tUPDATE   app\nINDEX  ", "  ReInDeX  ", "\n  更新索引 \t"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.updateIndex], query)
        }
    }

    func testUnrelatedAndSingleASCIICharacterQueriesExcludeCommand() {
        let applications = [app("Safari"), app("Terminal")]
        for query in ["saf", "term", "unrelated", "u", "r", "i", "a"] {
            XCTAssertFalse(LauncherResult.search(applications, query: query).contains(.updateIndex), query)
        }
        XCTAssertEqual(LauncherResult.search(applications, query: "saf"), [.application(applications[0])])
        XCTAssertEqual(LauncherResult.search(applications, query: "term"), [.application(applications[1])])
    }

    func testMatchingCommandPrecedesApplicationsWithoutChangingTheirRanking() {
        let applications = [app("My Index"), app("Index Pro"), app("Index")]
        let results = LauncherResult.search(applications, query: "index")
        XCTAssertEqual(results, [.updateIndex] + SearchEngine.search(applications, query: "index").map(LauncherResult.application))
        XCTAssertEqual(results.filter { $0 == .updateIndex }.count, 1)
        XCTAssertEqual(LauncherResult.search(applications.reversed(), query: "index"), results)
    }

    func testEmptyAndWhitespaceQueriesDoNotShowApplicationsOrCommands() {
        let applications = [app("Terminal"), app("Safari"), app("Clipboard")]
        for query in ["", " ", "\n \t\r", "\u{00A0}\u{2003}\u{3000}"] {
            XCTAssertTrue(LauncherResult.search(applications, query: query).isEmpty, query.debugDescription)
            XCTAssertTrue(LauncherResult.search([], query: query).isEmpty, query.debugDescription)
        }
    }

    func testTypingAfterEmptyQueryStillFindsApplicationsAndCommands() {
        let applications = [app("Terminal"), app("Safari"), app("Clipboard")]
        XCTAssertTrue(LauncherResult.search(applications, query: "").isEmpty)
        XCTAssertEqual(LauncherResult.search(applications, query: "saf"), [.application(applications[1])])
        XCTAssertEqual(LauncherResult.search(applications, query: "clipboard"), [
            .clipboardHistory, .application(applications[2]),
        ])
        XCTAssertTrue(LauncherResult.search(applications, query: "\n\t").isEmpty)
        XCTAssertEqual(LauncherResult.search(applications, query: "index"), [.updateIndex])
    }

    func testWindowCommandsAreDiscoverableWithoutCrowdingSingleLetterQueries() {
        for query in ["window", "resize", "moom", "視窗", "調整視窗"] {
            XCTAssertTrue(LauncherResult.search([], query: query).contains(.windowControls), query)
        }
        for query in ["window settings", "視窗設定"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.windowSettings], query)
        }
        XCTAssertFalse(LauncherResult.search([], query: "w").contains(.windowControls))
        XCTAssertTrue(LauncherResult.search([], query: "").isEmpty)
        XCTAssertNotEqual(LauncherResult.windowControls.id, LauncherResult.windowSettings.id)
    }

    func testClipboardCommandIsDiscoverableInBothLanguages() {
        for query in ["clipboard", "CLIPBOARD", "clip", "clipboard history", "paste history", "剪貼簿", "剪貼簿歷史", "剪貼簿記錄", "剪貼簿紀錄", "複製紀錄"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.clipboardHistory], query)
        }
        let applications = [app("Clipboard")]
        XCTAssertEqual(LauncherResult.search(applications, query: "clipboard"), [
            .clipboardHistory, .application(applications[0]),
        ])
        XCTAssertFalse(LauncherResult.search([], query: "c").contains(.clipboardHistory))
        XCTAssertNotEqual(LauncherResult.clipboardHistory.id, LauncherResult.updateIndex.id)
    }

    func testSleepCommandIsDiscoverableInBothLanguages() {
        for query in ["sleep", "SLEEP", "sl", "sleep mac", "sleep computer", "睡眠", "讓電腦睡眠", "電腦睡眠", "睡"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.sleep], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: " \tSlEeP  \n COMPUTER "), [.sleep])
    }

    func testLockCommandIsDiscoverableInBothLanguages() {
        for query in ["lock", "LOCK", "lo", "lock screen", "lock mac", "lock computer", "鎖定", "鎖定螢幕", "鎖定畫面", "鎖定電腦", "鎖屏", "鎖"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.lockScreen], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: " \tLoCk  \n SCREEN "), [.lockScreen])
    }

    func testScreenOffCommandIsDiscoverableInBothLanguages() {
        for query in [
            "screen off", "SCREEN OFF", "display off", "turn off screen", "turn off display", "off",
            "關閉螢幕", "關螢幕", "螢幕關閉", "關閉顯示器", "關閉畫面", "關閉",
        ] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.screenOff], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: " \tＳＣＲＥＥＮ \n OFF "), [.screenOff])
        XCTAssertEqual(LauncherResult.search([], query: "screen"), [.lockScreen, .screenOff])
        XCTAssertEqual(LauncherResult.search([], query: "螢幕"), [.lockScreen, .screenOff])
    }

    func testScreenOffUsageReordersOnlyMatchingCommands() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = SearchUsage()
        usage.record(resultID: LauncherResult.screenOff.id, query: "screen", at: now)
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(LauncherResult.search([], query: "screen", usage: snapshot), [.screenOff, .lockScreen])
        XCTAssertEqual(LauncherResult.search([], query: "lock", usage: snapshot), [.lockScreen])
        XCTAssertEqual(LauncherResult.search([], query: "sleep", usage: snapshot), [.sleep])
        XCTAssertTrue(LauncherResult.search([], query: "", usage: snapshot).isEmpty)
    }

    func testPowerCommandsDoNotCrowdSingleLetterOrUnrelatedSearches() {
        for query in ["s", "l", "m", "c", "o", "d", "sleep display", "sleepy", "offline", "unrelated"] {
            XCTAssertTrue(LauncherResult.search([], query: query).isEmpty, query)
        }
        let applications = [app("Safari"), app("Locksmith")]
        XCTAssertEqual(LauncherResult.search(applications, query: "l"),
                       SearchEngine.search(applications, query: "l").map(LauncherResult.application))
    }

    func testSystemCommandsPrecedeApplicationsAndAreNotDuplicatedByAliases() {
        let applications = [app("Sleep Monitor"), app("Sleep"), app("Locksmith"), app("Lock Screen"), app("Screen Off")]
        for (query, command) in [("sleep", LauncherResult.sleep), ("lock", LauncherResult.lockScreen), ("screen off", .screenOff)] {
            let results = LauncherResult.search(applications, query: query)
            XCTAssertEqual(results, [command] + SearchEngine.search(applications, query: query).map(LauncherResult.application))
            XCTAssertEqual(results.filter { $0 == command }.count, 1, query)
        }
        // Shared aliases keep a stable command order regardless of app order.
        XCTAssertEqual(LauncherResult.search([], query: "computer"), [.sleep, .lockScreen])
        XCTAssertEqual(LauncherResult.search([], query: "電腦"), [.sleep, .lockScreen])
    }

    func testSystemCommandIdentitiesDoNotCollideWithApplicationsOrOtherCommands() {
        let commands: [LauncherResult] = [
            .updateIndex, .clipboardHistory, .sleep, .lockScreen, .screenOff,
            .convertToTraditional, .convertToSimplified, .chineseConversionSettings, .webSearchSettings, .cleanLink, .emojiSearch,
        ]
        XCTAssertEqual(Set(commands.map(\.id)).count, commands.count)
        XCTAssertEqual(LauncherResult.sleep.id, "command:sleep")
        XCTAssertEqual(LauncherResult.sleep.name, "Sleep")
        XCTAssertEqual(LauncherResult.lockScreen.id, "command:lock-screen")
        XCTAssertEqual(LauncherResult.lockScreen.name, "Lock Screen")
        XCTAssertEqual(LauncherResult.screenOff.id, "command:screen-off")
        XCTAssertEqual(LauncherResult.screenOff.name, "Screen Off")
        for command in [LauncherResult.sleep, .lockScreen, .screenOff] {
            XCTAssertNotEqual(LauncherResult.application(app(command.name, id: command.id)).id, command.id)
        }
    }

    func testChineseConversionDirectionsAreDiscoverableInBothLanguages() {
        for query in [
            "traditional", "traditional chinese", "convert to traditional chinese", "taiwan", "s2t",
            "正體", "繁體", "正體中文", "轉換為正體中文", "台灣", "臺灣正體", "簡轉繁", "简转繁", "转繁体",
        ] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.convertToTraditional], query)
        }
        for query in [
            "simplified", "simplified chinese", "convert to simplified chinese", "mainland", "t2s",
            "簡體", "简体", "簡體中文", "轉換為簡體中文", "大陸", "大陆", "繁轉簡", "繁转简", "转简体",
        ] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.convertToSimplified], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: "  CONVERT  TO\nTRADITIONAL CHINESE  "), [.convertToTraditional])
        XCTAssertEqual(LauncherResult.search([], query: "  ＳＩＭＰＬＩＦＩＥＤ  "), [.convertToSimplified])
    }

    func testGenericChineseConversionQueriesOfferBothDirectionsOnce() {
        for query in ["convert", "converter"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.convertToTraditional, .convertToSimplified], query)
        }
        for query in ["chinese", "conversion", "繁簡轉換", "簡繁轉換", "简繁转换", "中文轉換", "转换"] {
            XCTAssertEqual(LauncherResult.search([], query: query),
                           [.convertToTraditional, .convertToSimplified, .chineseConversionSettings], query)
        }
        let applications = [app("Chinese Converter"), app("Convert")]
        XCTAssertEqual(LauncherResult.search(applications, query: "convert"),
                       [.convertToTraditional, .convertToSimplified]
                       + SearchEngine.search(applications, query: "convert").map(LauncherResult.application))
        for query in ["c", "t", "s", "x", "", " \n\t ", "unrelated"] {
            XCTAssertTrue(LauncherResult.search([], query: query).isEmpty, query)
        }
    }

    func testConversionUsageOnlyReordersMatchingCommands() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = SearchUsage()
        usage.record(resultID: LauncherResult.convertToSimplified.id, query: "convert", at: now)
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(LauncherResult.search([], query: "convert", usage: snapshot),
                       [.convertToSimplified, .convertToTraditional])
        XCTAssertEqual(LauncherResult.search([], query: "taiwan", usage: snapshot), [.convertToTraditional])
        XCTAssertTrue(LauncherResult.search([], query: "", usage: snapshot).isEmpty)
    }

    func testConversionCommandIdentitiesAreStableAndDistinct() {
        XCTAssertEqual(LauncherResult.convertToTraditional.id, "command:convert-to-traditional")
        XCTAssertEqual(LauncherResult.convertToSimplified.id, "command:convert-to-simplified")
        XCTAssertEqual(LauncherResult.convertToTraditional.name, "Convert to Traditional Chinese")
        XCTAssertEqual(LauncherResult.convertToSimplified.name, "Convert to Simplified Chinese")
        XCTAssertEqual(LauncherResult.chineseConversionSettings.id, "command:chinese-conversion-settings")
        for command in [LauncherResult.convertToTraditional, .convertToSimplified] {
            XCTAssertNotEqual(LauncherResult.application(app(command.name, id: command.id)).id, command.id)
        }
    }

    func testChineseConversionSettingsHasFeatureSpecificSearchAliases() {
        for query in ["chinese conversion settings", "conversion settings", "簡繁設定", "簡繁轉換設定", "繁簡設定", "繁简转换设置"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.chineseConversionSettings], query)
        }
    }

    func testDefaultConversionAliasesMatchDirectionAndAreExact() {
        XCTAssertEqual(LauncherResult.search([], query: "st").first, .convertToTraditional)
        XCTAssertEqual(LauncherResult.search([], query: "ts").first, .convertToSimplified)
        XCTAssertEqual(LauncherResult.search([], query: " ＳＴ ").first, .convertToTraditional)
        XCTAssertTrue(LauncherResult.search([], query: "s").isEmpty)
        XCTAssertTrue(LauncherResult.search([], query: "t").isEmpty)
    }

    func testCustomConversionAliasesOverrideLearnedOrderAndSupportSingleCharacters() throws {
        let aliases = try ChineseConversionAliases(traditional: "sleep", simplified: "q")
        var usage = SearchUsage()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        usage.record(resultID: LauncherResult.sleep.id, query: "sleep", at: now)
        let applications = [app("Sleep Monitor"), app("Quick Note")]
        for _ in 0..<100 {
            usage.record(resultID: LauncherResult.application(applications[0]).id, query: "sleep", at: now)
            usage.record(resultID: LauncherResult.application(applications[1]).id, query: "q", at: now)
        }
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(LauncherResult.search(applications, query: "sleep", usage: snapshot, conversionAliases: aliases),
                       [.convertToTraditional, .application(applications[0]), .sleep])
        XCTAssertEqual(LauncherResult.search(applications, query: "Q", usage: snapshot, conversionAliases: aliases),
                       [.convertToSimplified, .application(applications[1])])
    }

    func testExactApplicationAliasPrecedesCommandsRegardlessOfLearnedOrdering() {
        let code = app("Code").withSearchAlias("sleep")
        let companion = app("Sleep Monitor")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = SearchUsage()
        for _ in 0..<100 { usage.record(resultID: LauncherResult.sleep.id, query: "sleep", at: now) }
        for snapshot in [SearchUsageSnapshot.empty, usage.snapshot(at: now)] {
            XCTAssertEqual(LauncherResult.search([companion, code], query: "ＳＬＥＥＰ", usage: snapshot),
                           [.application(code), .sleep, .application(companion)])
            XCTAssertEqual(LauncherResult.search([code], query: "slee", usage: snapshot).first, .sleep)
        }
    }

    func testConversionAliasesRetainPrecedenceInLegacyApplicationAliasCollisions() throws {
        for alias in ["st", "sleep", "q"] {
            let code = app("Code").withSearchAlias(alias)
            let aliases = try ChineseConversionAliases(traditional: alias, simplified: "ts")
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var usage = SearchUsage()
            for _ in 0..<100 { usage.record(resultID: LauncherResult.application(code).id, query: alias, at: now) }
            for snapshot in [SearchUsageSnapshot.empty, usage.snapshot(at: now)] {
                let result = LauncherResult.search([code], query: alias, usage: snapshot, conversionAliases: aliases)
                XCTAssertEqual(Array(result.prefix(2)), [.convertToTraditional, .application(code)], alias)
                XCTAssertEqual(result.filter { $0 == .convertToTraditional }.count, 1)
                XCTAssertEqual(result.filter { $0 == .application(code) }.count, 1)
            }
        }
    }

    func testNumericAnswersStillPrecedeLegacyApplicationAliases() throws {
        let calculation = try XCTUnwrap(Calculator.evaluate("2+3"))
        let calculatorAlias = app("Code").withSearchAlias("2+3")
        XCTAssertEqual(LauncherResult.search([calculatorAlias], query: "2+3"),
                       [.calculation(calculation), .application(calculatorAlias)])
        let unitAlias = app("Code").withSearchAlias("5m")
        let query = try XCTUnwrap(ConversionQuery.parse("5m"))
        let conversions = UnitConversion.convert(query).map(LauncherResult.conversion)
        XCTAssertEqual(LauncherResult.search([unitAlias], query: "5m"), conversions + [.application(unitAlias)])
    }

    func testAliasRemovalRestoresNormalOrderingAndAutomaticMatches() {
        let code = app("Code").withSearchAlias("clipboard")
        XCTAssertEqual(LauncherResult.search([code], query: "clipboard"), [.application(code), .clipboardHistory])
        let removed = code.withSearchAlias(nil)
        XCTAssertEqual(LauncherResult.search([removed], query: "clipboard"), [.clipboardHistory])
        XCTAssertEqual(LauncherResult.search([removed], query: "code"), [.application(removed)])
        XCTAssertEqual(LauncherResult.search([code], query: ""), [])
    }

    func testNumericAnswersRemainAheadOfPinnedAliasesAndLearnedApplications() throws {
        let aliases = try ChineseConversionAliases(traditional: "2+3", simplified: "5m")
        let applications = [app("2+3"), app("5m")]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = SearchUsage()
        for _ in 0..<100 {
            usage.record(resultID: LauncherResult.application(applications[0]).id, query: "2+3", at: now)
            usage.record(resultID: LauncherResult.application(applications[1]).id, query: "5m", at: now)
        }
        let snapshot = usage.snapshot(at: now)
        let calculation = try XCTUnwrap(Calculator.evaluate("2+3"))
        XCTAssertEqual(LauncherResult.search(applications, query: "2+3", usage: snapshot, conversionAliases: aliases),
                       [.calculation(calculation), .convertToTraditional, .application(applications[0])])
        let query = try XCTUnwrap(ConversionQuery.parse("5m"))
        let conversions = UnitConversion.convert(query).map(LauncherResult.conversion)
        XCTAssertFalse(conversions.isEmpty)
        XCTAssertEqual(LauncherResult.search(applications, query: "5m", usage: snapshot, conversionAliases: aliases),
                       conversions + [.convertToSimplified, .application(applications[1])])
    }

    func testConversionAliasesAllowUnicodeSpacesAndDisablingWithoutPartialMatches() throws {
        let aliases = try ChineseConversionAliases(traditional: "  我的   正體  ", simplified: "")
        XCTAssertEqual(aliases.traditional, "我的 正體")
        XCTAssertEqual(LauncherResult.search([], query: "我的 正體", conversionAliases: aliases), [.convertToTraditional])
        XCTAssertTrue(LauncherResult.search([], query: "我的", conversionAliases: aliases).isEmpty)
        XCTAssertTrue(LauncherResult.search([], query: "ts", conversionAliases: aliases).isEmpty)
        XCTAssertTrue(LauncherResult.search([], query: "", conversionAliases: aliases).isEmpty)
        XCTAssertNoThrow(try ChineseConversionAliases(traditional: "", simplified: "   "))
    }

    func testConversionAliasesRejectAmbiguousUnsafeOrOversizedNames() throws {
        for (traditional, simplified) in [("ST", "ｓｔ"), ("  Café   Name ", "cafe name"), ("正體", "正體")] {
            XCTAssertThrowsError(try ChineseConversionAliases(traditional: traditional, simplified: simplified)) {
                XCTAssertEqual($0 as? ChineseConversionAliases.ValidationError, .duplicate)
            }
        }
        for bad in ["name\n", "\tname", "na\u{0000}me", "name\u{2028}"] {
            XCTAssertThrowsError(try ChineseConversionAliases(traditional: bad, simplified: "")) {
                XCTAssertEqual($0 as? ChineseConversionAliases.ValidationError, .controlCharacters)
            }
        }
        XCTAssertNoThrow(try ChineseConversionAliases(traditional: String(repeating: "a", count: 32), simplified: ""))
        XCTAssertNoThrow(try ChineseConversionAliases(traditional: String(repeating: "正", count: 10), simplified: ""))
        for bad in [String(repeating: "a", count: 33), String(repeating: "正", count: 11)] {
            XCTAssertThrowsError(try ChineseConversionAliases(traditional: "", simplified: bad)) {
                XCTAssertEqual($0 as? ChineseConversionAliases.ValidationError, .tooLong)
            }
        }
    }

    func testConversionAliasesValidateOnDecodeAndRoundTripDisplayNames() throws {
        let aliases = try ChineseConversionAliases(traditional: "My Traditional", simplified: "簡")
        let data = try JSONEncoder().encode(aliases)
        XCTAssertEqual(try JSONDecoder().decode(ChineseConversionAliases.self, from: data), aliases)
        let duplicate = Data(#"{"traditional":"ST","simplified":"ｓｔ"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ChineseConversionAliases.self, from: duplicate))
    }

    func testIdentitiesSeparateCommandsFromApplicationsEvenForMatchingNamesOrIDs() {
        let application = app("Update App Index", id: "command:update-index")
        let result = LauncherResult.application(application)
        XCTAssertEqual(result.id, "app:command:update-index")
        XCTAssertEqual(result.name, application.name)
        XCTAssertEqual(LauncherResult.updateIndex.id, "command:update-index")
        XCTAssertEqual(LauncherResult.updateIndex.name, "Update App Index")
        XCTAssertNotEqual(result.id, LauncherResult.updateIndex.id)
        XCTAssertNotEqual(LauncherResult.application(app("command:update-index")).id, LauncherResult.updateIndex.id)
        XCTAssertEqual(Set(LauncherResult.search([application], query: "index")).count, 2)
    }

    func testGoogleFallbackIsOptInAndOnlyAppearsWithoutLocalMatches() {
        let applications = [app("Safari"), app("Terminal")]
        let query = "What is the weather in Taipei?"
        XCTAssertTrue(LauncherResult.search(applications, query: query).isEmpty)
        XCTAssertTrue(LauncherResult.search(applications, query: query, includeGoogleFallback: false).isEmpty)
        XCTAssertEqual(LauncherResult.search(applications, query: query, includeGoogleFallback: true), [.googleSearch])
        XCTAssertEqual(LauncherResult.search([], query: query, includeGoogleFallback: true), [.googleSearch])
    }

    func testGoogleFallbackKeepsEmptyInputEmpty() {
        let applications = [app("Safari")]
        for query in ["", " ", "\n \t\r", "\u{00A0}\u{2003}\u{3000}"] {
            XCTAssertTrue(LauncherResult.search(applications, query: query, includeGoogleFallback: true).isEmpty,
                          query.debugDescription)
            XCTAssertTrue(LauncherResult.search([], query: query, includeGoogleFallback: true).isEmpty,
                          query.debugDescription)
        }
    }

    func testGoogleFallbackPreservesExactPrefixInitialsAndFuzzyAppMatches() {
        let applications = [app("Safari"), app("Safari Technology Preview"), app("Visual Studio Code")]
        for query in ["Safari", "saf", "vsc", "sfri", "a"] {
            let local = LauncherResult.search(applications, query: query)
            XCTAssertFalse(local.isEmpty, query)
            XCTAssertEqual(LauncherResult.search(applications, query: query, includeGoogleFallback: true), local, query)
            XCTAssertFalse(local.contains(.googleSearch), query)
        }
    }

    func testGoogleFallbackPreservesCommandsAndCustomExactAliases() throws {
        let aliases = try ChineseConversionAliases(traditional: "sleep", simplified: "q")
        let applications = [app("Sleep Monitor"), app("Quick Note")]
        for query in ["sleep", "q", "clipboard", "screen", "繁簡轉換"] {
            let local = LauncherResult.search(applications, query: query, conversionAliases: aliases)
            XCTAssertFalse(local.isEmpty, query)
            XCTAssertEqual(LauncherResult.search(applications, query: query, conversionAliases: aliases,
                                                includeGoogleFallback: true), local, query)
        }
    }

    func testGoogleFallbackHandlesSingleCharactersWithoutCrowdingAppMatches() {
        let applications = [app("Safari")]
        XCTAssertEqual(LauncherResult.search(applications, query: "z", includeGoogleFallback: true), [.googleSearch])
        XCTAssertEqual(LauncherResult.search(applications, query: "  Z  ", includeGoogleFallback: true), [.googleSearch])
        XCTAssertEqual(LauncherResult.search(applications, query: "s", includeGoogleFallback: true),
                       [.application(applications[0])])
        XCTAssertEqual(LauncherResult.search([], query: "睡", includeGoogleFallback: true), [.sleep])
        XCTAssertEqual(LauncherResult.search([], query: "貓", includeGoogleFallback: true), [.googleSearch])
    }

    func testGoogleFallbackDoesNotAffectLearnedLocalOrdering() {
        let applications = [app("Safari Preview"), app("Safari Technology Preview")]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = SearchUsage()
        usage.record(resultID: LauncherResult.application(applications[1]).id, query: "saf", at: now)
        usage.record(resultID: LauncherResult.screenOff.id, query: "screen", at: now)
        // Even a recorded web action must never displace a matching local result.
        usage.record(resultID: LauncherResult.googleSearch.id, query: "saf", at: now)
        let snapshot = usage.snapshot(at: now)
        XCTAssertEqual(LauncherResult.search(applications, query: "saf", usage: snapshot, includeGoogleFallback: true),
                       [.application(applications[1]), .application(applications[0])])
        XCTAssertEqual(LauncherResult.search(applications, query: "screen", usage: snapshot, includeGoogleFallback: true),
                       [.screenOff, .lockScreen])
        XCTAssertEqual(LauncherResult.search(applications, query: "unmatched question", usage: snapshot,
                                            includeGoogleFallback: true), [.googleSearch])
    }

    func testGoogleActionHasStableIdentityDistinctFromApplications() {
        XCTAssertEqual(LauncherResult.googleSearch.id, "action:google-search")
        XCTAssertEqual(LauncherResult.googleSearch.name, "Search Google")
        let application = app("Search Google", id: LauncherResult.googleSearch.id)
        XCTAssertNotEqual(LauncherResult.application(application).id, LauncherResult.googleSearch.id)
        XCTAssertEqual(LauncherResult.search([application], query: "Search Google", includeGoogleFallback: true),
                       [.application(application)])
    }

    func testBrowserSearchActionsHaveStableDistinctIdentities() {
        let first = WebSearchBrowser(bundleIdentifier: "com.example.first", name: "First Browser")
        let renamed = WebSearchBrowser(bundleIdentifier: first.bundleIdentifier, name: "First Browser Renamed")
        let second = WebSearchBrowser(bundleIdentifier: "com.example.second", name: first.name)
        let firstResult = LauncherResult.googleSearchIn(first)
        XCTAssertEqual(firstResult.id, "action:google-search:com.example.first")
        XCTAssertEqual(firstResult.name, "Search Google in First Browser")
        XCTAssertEqual(LauncherResult.googleSearchIn(renamed).id, firstResult.id)
        XCTAssertNotEqual(LauncherResult.googleSearchIn(second).id, firstResult.id)

        let results: [LauncherResult] = [
            .googleSearch, firstResult, .googleSearchIn(second), .webSearchSettings,
            .application(app(firstResult.name, id: firstResult.id)),
        ]
        XCTAssertEqual(Set(results.map(\.id)).count, results.count)
        XCTAssertEqual(LauncherResult.webSearchSettings.id, "command:web-search-settings")
        XCTAssertEqual(LauncherResult.webSearchSettings.name, "Google Search Settings")
    }

    func testEmojiCommandIsDiscoverableWithoutFillingTheBlankLauncher() {
        for query in ["emoji", "emoji finder", "Emoji Search", "表情符號", "表情", "繪文字", "  ＥＭＯＪＩ  "] {
            XCTAssertEqual(LauncherResult.search([], query: query, includeGoogleFallback: true), [.emojiSearch], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: ""), [])
        XCTAssertEqual(LauncherResult.search([], query: "e"), [])
        XCTAssertEqual(LauncherResult.search([], query: "emojix", includeGoogleFallback: true), [.googleSearch])
        for query in ["search", "finder", "搜尋"] {
            XCTAssertFalse(LauncherResult.search([], query: query).contains(.emojiSearch), query)
        }
    }

    func testOnlyWebSearchActionsAreExcludedFromOrdinaryCommandUsage() {
        let browser = WebSearchBrowser(bundleIdentifier: "com.example.browser", name: "Browser")
        XCTAssertTrue(LauncherResult.googleSearch.isWebSearch)
        XCTAssertTrue(LauncherResult.googleSearchIn(browser).isWebSearch)
        let localResults: [LauncherResult] = [
            .application(app("Search Google")), .updateIndex, .clipboardHistory, .sleep, .lockScreen,
            .screenOff, .convertToTraditional, .convertToSimplified, .chineseConversionSettings, .webSearchSettings, .cleanLink, .emojiSearch,
        ]
        for result in localResults {
            XCTAssertFalse(result.isWebSearch, result.name)
        }
    }

    func testWebSearchSettingsAreDiscoverableWithExplicitSettingsIntent() {
        for query in [
            "google settings", "google search settings", "browser settings", "web search settings",
            "google setting", "Google 搜尋設定", "搜尋瀏覽器設定", "瀏覽器設定",
            "Google 搜索设置", "搜索浏览器设置", "浏览器设置",
            "  ＧＯＯＧＬＥ　ＳＥＴＴＩＮＧＳ  ",
        ] {
            XCTAssertEqual(LauncherResult.search([], query: query, includeGoogleFallback: true), [.webSearchSettings], query)
        }
        for query in ["settings", "setting", "設定", "设置"] {
            XCTAssertEqual(LauncherResult.search([], query: query).filter { $0 == .webSearchSettings }.count, 1, query)
        }
    }

    func testWebSearchSettingsDoNotCrowdOrdinaryQueriesOrBrowserApplications() {
        for query in ["google", "google search", "web search", "browser", "Google 搜尋", "瀏覽器", "搜尋"] {
            XCTAssertTrue(LauncherResult.search([], query: query).isEmpty, query)
            XCTAssertEqual(LauncherResult.search([], query: query, includeGoogleFallback: true), [.googleSearch], query)
        }
        let applications = [app("Google Chrome"), app("Browser")]
        XCTAssertEqual(LauncherResult.search(applications, query: "google", includeGoogleFallback: true),
                       [.application(applications[0])])
        XCTAssertEqual(LauncherResult.search(applications, query: "browser", includeGoogleFallback: true),
                       [.application(applications[1])])
        XCTAssertEqual(LauncherResult.search([], query: "google settings help", includeGoogleFallback: true), [.googleSearch])
    }

    func testLinkCleanerIsDiscoverableInBothLanguagesWithoutReadingInputData() {
        for query in ["clean link", "link cleaner", "clean url", "remove tracking", "清理連結", "清理網址", "連結清理", "移除追蹤", "clean", "清理"] {
            XCTAssertEqual(LauncherResult.search([], query: query), [.cleanLink], query)
        }
        XCTAssertEqual(LauncherResult.search([], query: "  ＣＬＥＡＮ   ＬＩＮＫ  "), [.cleanLink])
        XCTAssertTrue(LauncherResult.search([], query: "c").isEmpty)
        XCTAssertEqual(LauncherResult.cleanLink.id, "command:clean-link")
        XCTAssertEqual(LauncherResult.cleanLink.name, "Clean Link")
        XCTAssertFalse(LauncherResult.cleanLink.isWebSearch)
        XCTAssertNotEqual(LauncherResult.application(app("Clean Link", id: "command:clean-link")).id,
                          LauncherResult.cleanLink.id)
    }

    func testLinkCleanerCommandPrecedesMatchingApplicationsAndPreservesGoogleFallback() {
        let applications = [app("Clean Link"), app("CleanMyMac")]
        XCTAssertEqual(LauncherResult.search(applications, query: "clean", includeGoogleFallback: true),
                       [.cleanLink] + SearchEngine.search(applications, query: "clean").map(LauncherResult.application))
        let query = "https://example.com/?utm_source=a"
        XCTAssertEqual(LauncherResult.search(applications, query: query, includeGoogleFallback: true), [.googleSearch])
        XCTAssertTrue(LauncherResult.search(applications, query: "").isEmpty)
    }
}
