import Foundation
import XCTest
import CueCore

final class ChineseConversionTests: XCTestCase {
    private static let resource = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Cue/Resources/ChineseConversion.cuecc")
    private static let converter = Result { try ChineseConverter(resourceURL: resource) }

    func testSimplifiedToTaiwanIncludesRegionalTerminology() throws {
        let converter = try Self.converter.get()
        XCTAssertEqual(try converter.convert("软件开发，鼠标和打印机，网络视频，内存数据库，默认设置。", to: .traditionalTaiwan),
                       "軟體開發，滑鼠和印表機，網路影片，記憶體資料庫，預設設定。")
    }

    func testTaiwanToSimplifiedIncludesMainlandTerminology() throws {
        let converter = try Self.converter.get()
        XCTAssertEqual(try converter.convert("滑鼠、記憶體、軟體、硬碟、隨身碟、程式碼、螢幕、網路影片。", to: .simplifiedChina),
                       "鼠标、内存、软件、硬盘、U盘、代码、屏幕、网络视频。")
    }

    func testPhraseContextResolvesAmbiguousSimplifiedCharacters() throws {
        let converter = try Self.converter.get()
        XCTAssertEqual(try converter.convert("头发发展，干燥干杯干活，皇后后面，面条里面。", to: .traditionalTaiwan),
                       "頭髮發展，乾燥乾杯幹活，皇后後面，麵條裡面。")
    }

    func testAlreadyTraditionalMainlandTermsStillBecomeTaiwanTerms() throws {
        let converter = try Self.converter.get()
        XCTAssertEqual(try converter.convert("軟件和鼠標，打印機、內存、數據庫。", to: .traditionalTaiwan),
                       "軟體和滑鼠，印表機、記憶體、資料庫。")
    }

    func testWhitespaceEmojiLatinCombiningMarksAndNullArePreservedExactly() throws {
        let converter = try Self.converter.get()
        let untouched = "\t😀👩‍💻 👨‍👩‍👧‍👦 Aé e\u{301} ℌ 𝕏\r\n\n\u{0}終　"
        let converted = try converter.convert(untouched + "软件\n鼠标", to: .traditionalTaiwan)
        XCTAssertEqual(converted.unicodeScalars.map(\.value), (untouched + "軟體\n滑鼠").unicodeScalars.map(\.value))
    }

    func testCompatibilityIdeographsFollowOfficialNormalizationOnly() throws {
        let converter = try Self.converter.get()
        XCTAssertEqual(try converter.convert("神 車 ℌ 𝕏", to: .traditionalTaiwan), "神 車 ℌ 𝕏")
        XCTAssertEqual(try converter.convert("神 車 ℌ 𝕏", to: .simplifiedChina), "神 车 ℌ 𝕏")
    }

    func testIdeographicDescriptionSequencesKeepTheirComponents() throws {
        let converter = try Self.converter.get()
        XCTAssertEqual(try converter.convert("⿰髟发和头发，⿱艹⿰氵台软件。", to: .traditionalTaiwan),
                       "⿰髟发和頭髮，⿱艹⿰氵台軟體。")
        // An incomplete sequence is not protected; normal conversion resumes.
        XCTAssertEqual(try converter.convert("⿰发", to: .traditionalTaiwan), "⿰發")
    }

    func testEmptyTextAndUnmappedSupplementaryCharacters() throws {
        let converter = try Self.converter.get()
        XCTAssertEqual(try converter.convert("", to: .traditionalTaiwan), "")
        XCTAssertEqual(try converter.convert("𠀀\n\r\t", to: .simplifiedChina), "𠀀\n\r\t")
    }

    func testInputLimitUsesUTF8BytesAndDoesNotReturnPartialText() throws {
        let converter = try Self.converter.get()
        let boundary = String(repeating: "a", count: ChineseConverter.maximumInputBytes)
        XCTAssertEqual(try converter.convert(boundary, to: .traditionalTaiwan), boundary)
        for text in [boundary + "a", String(repeating: "字", count: ChineseConverter.maximumInputBytes / 3 + 1)] {
            XCTAssertThrowsError(try converter.convert(text, to: .traditionalTaiwan)) {
                guard case ChineseConversionError.inputTooLarge = $0 else { return XCTFail("Wrong error: \($0)") }
            }
        }
    }

    func testCancelledOperationDoesNotReturnAReplacement() async throws {
        let converter = try Self.converter.get()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try converter.convert("软件", to: .traditionalTaiwan)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled conversion unexpectedly completed")
        } catch is CancellationError {
            // Expected: caller keeps the original selection intact.
        }
    }

    func testTruncatedOrInvalidResourceFailsCleanly() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let valid = try Data(contentsOf: Self.resource)
        for invalid in [Data(), Data("not a dictionary".utf8), valid.dropLast(), valid + Data([0])] {
            try Data(invalid).write(to: temporary)
            XCTAssertThrowsError(try ChineseConverter(resourceURL: temporary))
        }
    }
}
