import Foundation
import XCTest
import CueCore

final class UnitConversionTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private var snapshot: CurrencyRateSnapshot {
        CurrencyRateSnapshot(base: "USD", rates: ["TWD": 32, "EUR": decimal("0.8"), "JPY": 160],
                             updatedAt: Date(timeIntervalSince1970: 1_000), nextUpdateAt: Date(timeIntervalSince1970: 87_400))
    }

    func testNumericLiteralsJoinedUnitsAndExplicitTargets() {
        let cases: [(String, String, String, String?)] = [
            ("10m", "10", "m", nil), ("5坪", "5", "ping", nil),
            ("10 m to ft", "10", "m", "ft"), ("10 m in ft", "10", "m", "ft"),
            ("10公尺轉英尺", "10", "m", "ft"), ("10 m → ft", "10", "m", "ft"),
            ("10 in in cm", "10", "in", "cm"), ("  -40 °C to °F\n", "-40", "C", "F"),
            ("−40C", "-40", "C", nil), ("+1.25kg", "1.25", "kg", nil),
            ("-.5m", "-0.5", "m", nil), ("1.e2m", "100", "m", nil),
            ("1e-7m", "0.0000001", "m", nil), ("100EUR", "100", "EUR", nil),
            ("100 eur to twd", "100", "EUR", "TWD"), ("100美元轉台幣", "100", "USD", "TWD"),
        ]
        for (input, amount, source, target) in cases {
            let query = ConversionQuery.parse(input)
            XCTAssertEqual(query?.amount, decimal(amount), input)
            XCTAssertEqual(query?.source.id, source, input)
            XCTAssertEqual(query?.target?.id, target, input)
        }
    }

    func testAliasesAndControlledSymbolCase() {
        let aliases = ["㎡": "m2", "平方公尺": "m2", "平方公分": "cm2", "平方呎": "ft2",
                       "公頃": "ha", "公克": "g", "英吋": "in", "小時": "h", "秒": "s",
                       "攝氏": "C", "℃": "C", "℉": "F", "公里每小時": "kmh", "m/s": "ms",
                       "mL": "mL", "ml": "mL", "L": "L", "l": "L", "METERS": "m",
                       "US fl oz": "USfloz", "fl oz": "USfloz", "gal": "USgal", "美制加侖": "USgal",
                       "新臺幣": "TWD", "美金": "USD", "日圓": "JPY", "hkd": "HKD"]
        for (alias, id) in aliases { XCTAssertEqual(ConversionQuery.parse("1 " + alias)?.source.id, id, alias) }
        for symbol in ["M", "CM", "KM", "ML", "KG", "k", "$", "NT$", "¥", "UK gal", "imperial gallon"] {
            XCTAssertNil(ConversionQuery.parse("1 " + symbol), symbol)
        }
    }

    func testPlainSearchIncompleteIncompatibleAndUntrustedInputStayOutOfConversion() {
        for input in ["", "Safari", "1Password", "100", "100000", "m10", "(.5)m", ".5m", "1+2m",
                      "10m to", "10m to ft to cm", "10m→ft→cm", "10m轉ft→cm", "10 m ft",
                      "1m to kg", "1USD to m", "1m to USD", "1 gal to oz", "1e+m", "1e--2m",
                      "1..2m", "1,000m", "NaNm", "1e999m", "1e-999m", "1\0m", "1m;run()",
                      "1 https://example.com", "１m", "1e2.3m", "123456789012345678901234567890123456789m"] {
            XCTAssertNil(ConversionQuery.parse(input), input)
        }
        XCTAssertNotNil(ConversionQuery.parse("1" + String(repeating: " ", count: 254) + "m"))
        XCTAssertNil(ConversionQuery.parse("1" + String(repeating: " ", count: 255) + "m"))
        XCTAssertNil(ConversionQuery.parse(String(repeating: " ", count: 1_000_000) + "1m"))
        XCTAssertNil(ConversionQuery.parse("Safari" + String(repeating: "x", count: 1_000_000)))
    }

    func testExactLengthMassVolumeTimeAndSpeedFactors() {
        let cases = ["12 in to ft": "1", "1 mi to km": "1.609344", "1 yd to m": "0.9144",
                     "1000 mm to m": "1", "1 lb to g": "453.59237", "16 oz to lb": "1",
                     "1 US gal to US fl oz": "128", "1000ml to L": "1",
                     "1day to s": "86400", "90min to h": "1.5", "36km/h to m/s": "10",
                     "60mph to km/h": "96.56064", "10m/s to km/h": "36"]
        for (input, expected) in cases { assertResult(input, expected, approximate: false) }
        assertResult("1 US gal to L", "3.7854118", approximate: true)
        assertResult("1 US fl oz to mL", "29.57353", approximate: true)
    }

    func testTaiwanAreaRatioUsesExactRationalInsteadOfRoundedSquareMetres() {
        assertResult("1m2 to 坪", "0.3025", approximate: false)
        assertResult("121坪 to m2", "400", approximate: false)
        assertResult("1坪 to m2", "3.3057851", approximate: true)
        assertResult("5坪 to m2", "16.528926", approximate: true)
        assertResult("1acre to m2", "4046.8564", approximate: true)
        assertResult("1ft2 to m2", "0.09290304", approximate: false)
        for source in ["m2", "cm2", "ft2", "ha", "acre"] {
            XCTAssertEqual(results("1" + source).first?.targetID, "ping", source)
        }
        XCTAssertEqual(results("1坪").map(\.targetID), ["m2", "ft2", "ha"])
    }

    func testTemperatureAffineTransformsAndAbsoluteZeroBoundaries() {
        let cases = ["0C to F": "32", "100C to F": "212", "32F to C": "0", "-40C to F": "-40",
                     "0C to K": "273.15", "0K to C": "-273.15", "0K to F": "-459.67",
                     "-273.15C to K": "0", "-459.67F to K": "0", "212F to C": "100"]
        for (input, expected) in cases { assertResult(input, expected, approximate: false) }
        for input in ["-273.15000001C", "-459.67000001F", "-0.00000001K"] {
            XCTAssertNotNil(ConversionQuery.parse(input))
            XCTAssertTrue(results(input).isEmpty, input)
        }
    }

    func testDefaultsStayDistinctBoundedAndExcludeSource() {
        for source in ["mm", "cm", "m", "km", "in", "ft", "yd", "mi", "m2", "cm2", "ft2", "坪", "ha", "acre",
                       "g", "kg", "oz", "lb", "mL", "L", "US fl oz", "US gal", "C", "F", "K", "s", "min", "h", "day", "km/h", "m/s", "mph"] {
            let query = ConversionQuery.parse("1 " + source)!
            let converted = UnitConversion.convert(query)
            XCTAssertTrue((2...3).contains(converted.count), source)
            XCTAssertEqual(Set(converted.map(\.targetID)).count, converted.count, source)
            XCTAssertFalse(converted.contains { $0.targetID == query.source.id }, source)
        }
        XCTAssertEqual(results("10m to m").count, 1)
        assertResult("10m to m", "10", approximate: false)
    }

    func testIndependentMetricIntegerOracleAndRoundedRoundTrips() {
        for amount in -10...10 {
            assertResult("\(amount)km to m", String(amount * 1000), approximate: false)
            assertResult("\(amount)h to s", String(amount * 3600), approximate: false)
            assertResult("\(amount)C to F", decimalString(Decimal(amount) * 9 / 5 + 32), approximate: false)
        }
        for (source, target) in [("m", "ft"), ("坪", "ft2"), ("kg", "lb"), ("L", "US gal"), ("C", "F"), ("km/h", "mph")] {
            let first = results("123.456 \(source) to \(target)").first!
            let returned = results("\(first.value) \(target) to \(source)").first!
            let difference = abs(NSDecimalNumber(decimal: decimal(returned.value) - decimal("123.456")).doubleValue)
            // Two display roundings retain the accuracy expected of an
            // eight-significant-digit result around this 123.456 input.
            XCTAssertLessThan(difference, 0.00002, "\(source) ↔ \(target)")
        }
    }

    func testCurrencyCrossRatesDefaultsAndAlwaysIndicativeFormatting() {
        assertCurrency("100USD to TWD", "3200")
        assertCurrency("100TWD to USD", "3.13")
        assertCurrency("100EUR to USD", "125")
        assertCurrency("-100TWD to USD", "-3.13")
        assertCurrency("100JPY to TWD", "20")
        assertCurrency("1USD to USD", "1")
        let twd = UnitConversion.convertCurrency(ConversionQuery.parse("100TWD")!, rates: snapshot)
        XCTAssertEqual(twd.map(\.targetID), ["USD", "EUR", "JPY"])
        let usd = UnitConversion.convertCurrency(ConversionQuery.parse("100USD")!, rates: snapshot)
        XCTAssertEqual(usd.map(\.targetID), ["TWD", "EUR", "JPY"])
        XCTAssertTrue(usd.allSatisfy { $0.isCurrency && $0.isApproximate && $0.unitSymbol == $0.targetID })
        XCTAssertTrue(UnitConversion.convert(ConversionQuery.parse("100USD")!).isEmpty)
        XCTAssertTrue(UnitConversion.convertCurrency(ConversionQuery.parse("100m")!, rates: snapshot).isEmpty)
    }

    func testInvalidRatesAndIncompatibleConstructedQueriesCannotProduceResults() {
        let query = ConversionQuery.parse("1USD to TWD")!
        for rates: [String: Decimal] in [[:], ["TWD": 0], ["TWD": -1], ["TWD": .nan]] {
            let invalid = CurrencyRateSnapshot(base: "USD", rates: rates, updatedAt: snapshot.updatedAt, nextUpdateAt: snapshot.nextUpdateAt)
            XCTAssertTrue(UnitConversion.convertCurrency(query, rates: invalid).isEmpty)
        }
        let unknown = CurrencyRateSnapshot(base: "FAKE", rates: snapshot.rates, updatedAt: snapshot.updatedAt, nextUpdateAt: snapshot.nextUpdateAt)
        XCTAssertTrue(UnitConversion.convertCurrency(query, rates: unknown).isEmpty)
        let notFinite = CurrencyRateSnapshot(base: "USD", rates: snapshot.rates, updatedAt: Date(timeIntervalSince1970: .infinity), nextUpdateAt: snapshot.nextUpdateAt)
        XCTAssertTrue(UnitConversion.convertCurrency(query, rates: notFinite).isEmpty)
        let metres = ConversionQuery.parse("1m")!.source
        let kilograms = ConversionQuery.parse("1kg")!.source
        XCTAssertTrue(UnitConversion.convert(ConversionQuery(amount: 1, source: metres, target: kilograms)).isEmpty)
        XCTAssertTrue(UnitConversion.convert(ConversionQuery(amount: .nan, source: metres)).isEmpty)
        XCTAssertTrue(UnitConversion.convert(ConversionQuery(amount: 1, source: ConversionUnit(id: "m", symbol: "fake"))).isEmpty)
    }

    func testFormattingAvoidsBinaryTailsZeroedTinyValuesAndUnmarkedRounding() {
        assertResult("0.1m to cm", "10", approximate: false)
        assertResult("1e-20m to cm", "1e-18", approximate: false)
        assertResult("12345678901234567m to m", "12345679000000000", approximate: true)
        assertResult("10m to ft", "32.808399", approximate: true)
        assertResult("9.99999996m to m", "10", approximate: true)
        assertResult("-9.99999996m to m", "-10", approximate: true)
        assertResult("0m to cm", "0", approximate: false)
        assertCurrency("0.000001USD to TWD", "0.000032")
        assertCurrency("0.000000123456789USD to USD", "1.23456789e-7")
        XCTAssertTrue(results("1e127km to mm").isEmpty)
        XCTAssertTrue(results("1e-128mm to km").isEmpty)
    }

    func testOptimizedOrdinaryTextGateAndRepresentativeConversionCost() {
        let ordinary = ["Safari", "clipboard", "emoji", "Google 搜尋設定", "繁轉簡", "1Password"]
        var consumed = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<2_000 { for input in ordinary { consumed += ConversionQuery.parse(input) == nil ? 1 : 0 } }
        let ordinaryNanos = Double(DispatchTime.now().uptimeNanoseconds - start) / 12_000
        let inputs = ["10m", "5坪", "100USD", "100 usd to twd", "-40C to F", "10 m to ft", "60mph"]
        var samples: [Double] = []
        for _ in 0..<100 {
            for input in inputs {
                let before = DispatchTime.now().uptimeNanoseconds
                let query = ConversionQuery.parse(input)!
                let output = query.source.isCurrency ? UnitConversion.convertCurrency(query, rates: snapshot) : UnitConversion.convert(query)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - before) / 1_000_000)
                consumed += output.count
            }
        }
        samples.sort()
        print(String(format: "Unit conversion benchmark: ordinary gate %.3f µs; parse + convert p50 %.3f ms, p99 %.3f ms, max %.3f ms", ordinaryNanos / 1_000, samples[samples.count / 2], samples[samples.count * 99 / 100], samples.last!))
        XCTAssertGreaterThan(consumed, 12_000)
    }

    private func results(_ input: String) -> [ConversionResult] { ConversionQuery.parse(input).map(UnitConversion.convert) ?? [] }
    private func decimal(_ value: String) -> Decimal { Decimal(string: value, locale: locale)! }
    private func decimalString(_ value: Decimal) -> String { var value = value; return NSDecimalString(&value, locale) }
    private func assertResult(_ input: String, _ value: String, approximate: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let output = results(input)
        XCTAssertEqual(output.count, 1, input, file: file, line: line)
        XCTAssertEqual(output.first?.value, value, input, file: file, line: line)
        XCTAssertEqual(output.first?.isApproximate, approximate, input, file: file, line: line)
    }
    private func assertCurrency(_ input: String, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let query = ConversionQuery.parse(input) else { return XCTFail(input, file: file, line: line) }
        let output = UnitConversion.convertCurrency(query, rates: snapshot)
        XCTAssertEqual(output.count, 1, input, file: file, line: line)
        XCTAssertEqual(output.first?.value, value, input, file: file, line: line)
        XCTAssertEqual(output.first?.isApproximate, true, input, file: file, line: line)
    }
}
