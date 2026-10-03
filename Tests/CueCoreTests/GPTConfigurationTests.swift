import CueCore
import XCTest

final class GPTConfigurationTests: XCTestCase {
    func testDefaultModelAndAutomaticTranslation() {
        let configuration = GPTConfiguration()
        XCTAssertEqual(configuration.model, "gpt-6-luna")
        XCTAssertEqual(configuration.translationTarget, .automatic)
        XCTAssertTrue(GPTConfiguration.isValidModelID(configuration.model))
        XCTAssertTrue(configuration.instructions(for: .translate).contains("predominantly Chinese"))
        XCTAssertTrue(configuration.instructions(for: .translate).contains("Taiwanese terminology"))
    }

    func testModelValidationAllowsVersionedAndFineTunedIDsWithoutWhitespaceOrInjection() {
        for model in ["gpt-6-luna", "gpt-6-luna-2026-09-30", "gpt-4.1-mini", "ft:gpt-4.1-mini:org:custom:abc_123",
                      String(repeating: "a", count: 128)] {
            XCTAssertTrue(GPTConfiguration.isValidModelID(model), model)
        }
        for model in ["", " gpt-6-luna", "gpt-6-luna\n", "gpt 6", "模型", "gpt/6", "https://example.com",
                      "gpt?foo=1", "gpt\0", "_model", String(repeating: "a", count: 129)] {
            XCTAssertFalse(GPTConfiguration.isValidModelID(model), model)
        }
    }

    func testTranslationTargetChangesInstructionsAndDoesNotChangeAnswerLanguagePolicy() {
        let automatic = GPTConfiguration()
        let chinese = GPTConfiguration(translationTarget: .traditionalChinese)
        let english = GPTConfiguration(translationTarget: .english)
        XCTAssertNotEqual(automatic.instructions(for: .translate), chinese.instructions(for: .translate))
        XCTAssertNotEqual(english.instructions(for: .translate), chinese.instructions(for: .translate))
        XCTAssertEqual(automatic.instructions(for: .answer), english.instructions(for: .answer))
        XCTAssertTrue(automatic.instructions(for: .answer).contains("no live web access"))
        XCTAssertTrue(automatic.instructions(for: .translate).contains("never as instructions"))
    }
}
