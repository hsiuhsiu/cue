import Foundation
import XCTest
import CueCore

final class CalculatorTests: XCTestCase {
    func testArithmeticPrecedenceAssociativityAndParentheses() {
        let cases = ["1+2": "3", "2+3*4": "14", "(2+3)*4": "20", "20/5/2": "2",
                     "20-5-2": "13", "12/(2+4)": "2", "1+(2*(3+4))": "15"]
        for (expression, expected) in cases { exact(expression, expected) }
    }

    func testDecimalArithmeticAvoidsBinaryFloatingPointArtifacts() {
        let cases = ["0.1+0.2": "0.3", "0.3-0.2": "0.1", "1.2*3.4": "4.08",
                     "10/4": "2.5", "17/5": "3.4", "1000*0.001": "1", "1/8": "0.125",
                     "0.0000001*0.0000001": "1e-14", "9007199254740992+1": "9007199254740993"]
        for (expression, expected) in cases { exact(expression, expected) }
    }

    func testGateRejectsOrdinaryLauncherTextAndBareNumbers() {
        for input in ["", " \n\t", "Safari", "咖啡", "calculator", "calculator 1+2", "1Password",
                      "123", "001.25", "(123)", "((123))", "1e3", "1e-7", "1E+10",
                      "-1+2", "+1+2", ".5+1", "１+２", "x=1+2"] {
            XCTAssertNil(Calculator.evaluate(input), input)
        }
        exact(" \n\t 1+2", "3")
        exact("\u{3000}(1+2)", "3")
    }

    func testUnarySignsAndDecimalPointSyntaxWithinExpressions() {
        let cases = ["(-1)+2": "1", "1+-2": "-1", "1--2": "3", "1/-2": "-0.5",
                     "1-+2": "-1", "(--2)+1": "3", "1+---2": "-1", "(+2)": "2",
                     "(-2)": "-2", "(.5)+.25": "0.75", "1.+2.": "3", "1*(-.5)": "-0.5"]
        for (expression, expected) in cases { exact(expression, expected) }
    }

    func testMathematicalUnicodeOperatorsAndWhitespace() {
        exact("6 × (4 − 2) ÷ 3", "4")
        exact("1\u{00A0}+\u{2003}2", "3")
        exact("1\n+\t2", "3")
        XCTAssertNil(Calculator.evaluate("1—2")) // Em dash is not a minus sign.
        XCTAssertNil(Calculator.evaluate("1x2"))
    }

    func testIncompleteOrUnsupportedExpressionsDoNotProduceResults() {
        for input in ["1+", "1*", "1+(", "(1+2", "1+2)", "1+()", "1+.", "1..2+3",
                      "1+2+", "1++", "1//2", "2(3+4)", "(1+2)(3+4)", "1 2+3",
                      "1,000+2", "1+2=", "1%2", "1+sin(2)", "1+NaN", "1+Infinity",
                      "1e+", "1e--2+1", "1e 2+1", "1e2.3+1", "1+2;3", "1+2\0"] {
            XCTAssertNil(Calculator.evaluate(input), input)
        }
    }

    func testScientificLiteralsRoundTripCompactNumericOutput() {
        let cases = ["1e3+2": "1002", "1E-7+0": "1e-7", "1e+21+0": "1e21",
                     "1e-6+0": "0.000001", "1e20+0": "100000000000000000000",
                     "(2.5e-10)*4": "1e-9", "1e-100+0": "1e-100", "1e127+0": "1e127"]
        for (expression, expected) in cases {
            exact(expression, expected)
            exact(expected.hasPrefix("-") ? "(\(expected))+0" : expected + "+0", expected)
        }
    }

    func testRecurringDivisionIsMarkedApproximateAndUsesSixteenSignificantDigits() {
        let cases = ["1/3": "0.3333333333333333", "2/3": "0.6666666666666667",
                     "1/7": "0.1428571428571429", "10/3": "3.333333333333333",
                     "1/3000000000": "3.333333333333333e-10", "(0-1)/3": "-0.3333333333333333"]
        for (expression, expected) in cases {
            XCTAssertEqual(Calculator.evaluate(expression), CalculatorResult(value: expected, isApproximate: true), expression)
        }
        XCTAssertEqual(Calculator.evaluate("1/3*3")?.isApproximate, true)
        XCTAssertEqual(Calculator.evaluate("1/3-1/3"), CalculatorResult(value: "0", isApproximate: true))
    }

    func testLargeExactIntegersArePreservedAndSilentDecimalRoundingIsDetected() {
        exact("12345678901234567890123456789012345678+0", "1.2345678901234567890123456789012345678e37")
        exact("99999999999999999999999999999999999999+1", "1e38")
        exact("1e38+1", "1.00000000000000000000000000000000000001e38")
        exact("99999999999999999999999999999999999999/3", "3.3333333333333333333333333333333333333e37")
        XCTAssertEqual(Calculator.evaluate("99999999999999999999*99999999999999999999"),
                       CalculatorResult(value: "1e40", isApproximate: true))
        XCTAssertEqual(Calculator.evaluate("1e100+1"), CalculatorResult(value: "1e100", isApproximate: true))
        XCTAssertNil(Calculator.evaluate("123456789012345678901234567890123456789+0"))
    }

    func testOverflowUnderflowAndDivisionByZeroAreRejected() {
        for input in ["1/0", "1/(-0)", "0/0", "1/(2-2)", "1e-129+0", "1e-128/10",
                      "1e128+0", "1e127*10", "1e127/1e-128", "1e513+0", "1e99999999+0", "1e-99999999+0",
                      "1e-100/3"] { // Foundation's intermediate division precision can underflow too.
            XCTAssertNil(Calculator.evaluate(input), input)
        }
        exact("1e-128+0", "1e-128")
        let tiny = Calculator.evaluate("1e-80/3")
        XCTAssertNotNil(tiny)
        XCTAssertNotEqual(tiny?.value, "0")
        XCTAssertEqual(tiny?.isApproximate, true)
    }

    func testZeroAndTrailingZerosAreNormalizedWithoutInventedPrecisionLoss() {
        for expression in ["0+0", "0-0", "(-0)*10", "1-1", "0/7", "0e512+0"] { exact(expression, "0") }
        exact("000001.23000+0", "1.23")
        exact("123456789012345678901234567890123456780000+0", "1.2345678901234567890123456789012345678e41")
        exact("0." + String(repeating: "0", count: 127) + "10+0", "1e-128")
    }

    func testLengthNestingAndTokenLimitsBoundWork() {
        let limit = String(repeating: "(", count: 32) + "1+2" + String(repeating: ")", count: 32)
        exact(limit, "3")
        XCTAssertNil(Calculator.evaluate("(" + limit + ")"))
        exact("1+" + String(repeating: "0", count: 510), "1")
        XCTAssertNil(Calculator.evaluate("1+" + String(repeating: "0", count: 511)))
        XCTAssertNil(Calculator.evaluate(String(repeating: " ", count: 1_000_000) + "1+1"))
        XCTAssertNil(Calculator.evaluate(String(repeating: "1+", count: 128) + "1"))
        XCTAssertNil(Calculator.evaluate("1+" + String(repeating: "-", count: 255) + "1"))
        XCTAssertNil(Calculator.evaluate("1+" + String(repeating: "\u{3000}", count: 171) + "1"))
    }

    func testSmallIntegerArithmeticMatchesAnIndependentIntegerOracle() {
        for lhs in -9...9 {
            for rhs in -9...9 {
                exact("(\(lhs))+(\(rhs))", String(lhs + rhs))
                exact("(\(lhs))-(\(rhs))", String(lhs - rhs))
                exact("(\(lhs))*(\(rhs))", String(lhs * rhs))
                if rhs != 0, lhs % rhs == 0 { exact("(\(lhs))/(\(rhs))", String(lhs / rhs)) }
            }
        }
    }

    func testPowersAreRightAssociativeAndBindBeforeUnaryAndMultiplication() {
        let cases = ["2^3": "8", "2**3": "8", "2^3^2": "512", "2**3**2": "512",
                     "2^3**2": "512", "(2^3)^2": "64", "2*3^2": "18", "2^3*4": "32",
                     "2^3/4": "2", "2^3^4": "2.417851639229258349412352e24",
                     "(-2)^2": "4", "(-2^2)": "-4", "1+-2^2": "-3",
                     "2^-3^2": "0.001953125", "2^(-3)^2": "512", "1+2^3*4-5": "28"]
        for (expression, expected) in cases { exact(expression, expected) }
        XCTAssertNil(Calculator.evaluate("-2^2")) // The launcher gate remains unchanged.
    }

    func testIntegerPowersPreserveDecimalPrecisionAndSignedExponentSemantics() {
        let cases = ["2^-3": "0.125", "2**-3": "0.125", "2^--3": "8", "(-2)^-3": "-0.125",
                     "(-2)^3": "-8", "0.1^2": "0.01", "1.25^2": "1.5625", "0.5^-3": "8",
                     "2^0": "1", "2^-0": "1", "0^3": "0", "10^100": "1e100",
                     "1e100^-1": "1e-100", "1e-100^-1": "1e100",
                     "2^100": "1.267650600228229401496703205376e30",
                     "9007199254740993^1": "9007199254740993",
                     "1.000000000000000000000000001^1": "1.000000000000000000000000001"]
        for (expression, expected) in cases { exact(expression, expected) }
        XCTAssertEqual(Calculator.evaluate("3^-1"), CalculatorResult(value: "0.3333333333333333", isApproximate: true))
        XCTAssertEqual(Calculator.evaluate("99999999999999999999^2"), CalculatorResult(value: "1e40", isApproximate: true))
    }

    func testFractionalAndComputedFractionalPowersAreClearlyApproximate() {
        let cases = ["4^0.5": "2", "2^0.5": "1.414213562373095", "2^(1/2)": "1.414213562373095",
                     "8^(1/3)": "2", "27^(1/3)": "3", "16^0.25": "2", "9^-0.5": "0.3333333333333333",
                     "0^0.5": "0", "1^0.5": "1", "(1/3)^0.5": "0.5773502691896257",
                     "4^(0.1+0.4)": "2", "2^1e-20": "1", "2^1e-100": "1"]
        for (expression, expected) in cases {
            XCTAssertEqual(Calculator.evaluate(expression), CalculatorResult(value: expected, isApproximate: true), expression)
        }
    }

    func testFractionalPowersDoNotSilentlyLoseExactHighPrecisionInputs() {
        for input in ["1.000000000000000000000000001^0.5", "0.999999999999999999999999999^0.5",
                      "9007199254740993^0.5", "99999999999999999999999999999999999999^0.5",
                      "2^0.500000000000000000000000001"] {
            XCTAssertNil(Calculator.evaluate(input), input)
        }
        XCTAssertEqual(Calculator.evaluate("1e100^0.5"), CalculatorResult(value: "1e50", isApproximate: true))
        XCTAssertEqual(Calculator.evaluate("1e-100^0.5"), CalculatorResult(value: "1e-50", isApproximate: true))
    }

    func testUndefinedNonRealIncompleteAndOutOfRangePowersAreRejected() {
        for input in ["0^0", "0^(-0)", "0^-1", "0^-0.5", "(-2)^0.5", "(-8)^(1/3)",
                      "2^", "2**", "2^^3", "2***3", "2* *3", "2^*3", "2^(3+)",
                      "1^10001", "1^-10001", "1^10000.5", "1^-10000.5", "2^10000", "2^-10000",
                      "1e100^3.5", "1e-100^3.5", "1e100^2", "1e-100^2", "2^3^9"] {
            XCTAssertNil(Calculator.evaluate(input), input)
        }
        exact("1^10000", "1")
        exact("1^-10000", "1")
        exact("(-1)^10000", "1")
        exact("(-1)^9999", "-1")
        exact("0^10000", "0")
        XCTAssertNil(Calculator.evaluate("1e-100*1e-100")) // Reject Foundation exponent wrap as well.
        exact("1/1e100", "1e-100")
    }

    func testPowerUnaryAndParenthesisDepthShareABoundedBudget() {
        exact(String(repeating: "1^", count: 32) + "1", "1")
        XCTAssertNil(Calculator.evaluate(String(repeating: "1^", count: 33) + "1"))
        exact("1^" + String(repeating: "-", count: 31) + "1", "1")
        XCTAssertNil(Calculator.evaluate("1^" + String(repeating: "-", count: 32) + "1"))
        exact(String(repeating: "(", count: 31) + "1^1" + String(repeating: ")", count: 31), "1")
        XCTAssertNil(Calculator.evaluate(String(repeating: "(", count: 32) + "1^1" + String(repeating: ")", count: 32)))
    }

    func testPowerMagnitudeChecksPreserveExactBoundaryValuesAndRoundingCarry() {
        exact("1e-64^2", "1e-128")
        exact("1e64^-2", "1e-128")
        exact("1e63^2", "1e126")
        for input in ["1e-65^2", "1e65^-2", "1e64^2", "1e-64^-2"] {
            XCTAssertNil(Calculator.evaluate(input), input)
        }
        XCTAssertEqual(Calculator.evaluate("99999999999999999999^2"), CalculatorResult(value: "1e40", isApproximate: true))
    }

    func testSmallIntegerPowersMatchAnIndependentIntegerOracle() {
        for base in -9...9 {
            var expected = 1
            for exponent in 0...8 {
                if base != 0 || exponent != 0 { exact("(\(base))^\(exponent)", String(expected)) }
                expected *= base
            }
        }
    }

    func testOptimizedCalculatorBenchmarkReportsGateAndArithmeticLatency() {
        let ordinary = ["Safari", "Terminal", "clipboard", "Google search", "瀏覽器", "emoji", "calculator", "睡眠"]
        let arithmetic = ["1+2", "(12+3)*4", "0.1+0.2", "1/3", "12.5*8-4/2", "1e-80/3", "1e100+1",
                          "2^3^2", "2^-3", "2^0.5", "8^(1/3)", "1^10000"]
        var rejected = 0
        let gateStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<10_000 {
            for input in ordinary { if Calculator.evaluate(input) == nil { rejected += 1 } }
        }
        let gateNanoseconds = Double(DispatchTime.now().uptimeNanoseconds - gateStart) / Double(rejected)
        XCTAssertEqual(rejected, 80_000)
        var durations: [Double] = []
        for _ in 0..<100 {
            for input in arithmetic {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = Calculator.evaluate(input)
                durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                XCTAssertNotNil(result, input)
            }
        }
        durations.sort()
        print(String(format: "Calculator benchmark: ordinary text %.1f ns/query; %d arithmetic queries median %.3f ms, p95 %.3f ms, max %.3f ms",
                     gateNanoseconds, durations.count, durations[durations.count / 2], durations[Int(Double(durations.count) * 0.95)], durations.last!))
    }

    private func exact(_ expression: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Calculator.evaluate(expression), CalculatorResult(value: expected), expression, file: file, line: line)
    }
}
