import Foundation
import XCTest
import CueCore

final class LauncherResultTests: XCTestCase {
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
            .convertToTraditional, .convertToSimplified, .chineseConversionSettings,
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
        XCTAssertEqual(LauncherResult.search([], query: "sleep", usage: usage.snapshot(at: now), conversionAliases: aliases),
                       [.convertToTraditional, .sleep])
        let applications = [app("Quick Note")]
        XCTAssertEqual(LauncherResult.search(applications, query: "Q", conversionAliases: aliases),
                       [.convertToSimplified, .application(applications[0])])
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
}
