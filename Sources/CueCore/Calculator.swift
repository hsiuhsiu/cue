import Foundation

public struct CalculatorResult: Hashable, Sendable {
    public let value: String
    public let isApproximate: Bool

    public init(value: String, isApproximate: Bool = false) {
        self.value = value
        self.isApproximate = isApproximate
    }
}

/// Bounded, local arithmetic. Ordinary launcher text exits before normalization.
public enum Calculator {
    public static func evaluate(_ input: String) -> CalculatorResult? {
        guard input.utf8.count <= 512,
              let first = input.unicodeScalars.first(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }),
              first.value == 40 || (48...57).contains(first.value) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(input.utf8.count)
        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 0...127:
                bytes.append(CharacterSet.whitespacesAndNewlines.contains(scalar) ? 32 : UInt8(scalar.value))
            case 0xD7: bytes.append(42) // ×
            case 0xF7: bytes.append(47) // ÷
            case 0x2212: bytes.append(45) // −
            default:
                guard CharacterSet.whitespacesAndNewlines.contains(scalar) else { return nil }
                bytes.append(32)
            }
        }
        var parser = Parser(bytes: bytes)
        guard let number = try? parser.parse() else { return nil }
        return format(number)
    }

    private static let locale = Locale(identifier: "en_US_POSIX")
    private enum Failure: Swift.Error { case invalid }

    private struct Number {
        var decimal: Decimal
        let exact: Coefficient
        let approximate: Bool

        init(_ decimal: Decimal, approximate: Bool = false) {
            self.decimal = decimal
            exact = Coefficient(decimal)
            self.approximate = approximate
        }
    }

    private struct Parser {
        let bytes: [UInt8]
        var position = 0
        var tokens = 0
        var operators = 0

        mutating func parse() throws -> Number {
            let value = try expression(depth: 0)
            skipSpaces()
            guard position == bytes.count, operators > 0 else { throw Failure.invalid }
            return value
        }

        mutating func expression(depth: Int) throws -> Number {
            var value = try term(depth: depth)
            while let operation = peek(), operation == 43 || operation == 45 {
                try advance()
                operators += 1
                let right = try term(depth: depth)
                value = try calculate(value, right, operation: operation)
            }
            return value
        }

        mutating func term(depth: Int) throws -> Number {
            var value = try unary(depth: depth)
            while let operation = peek(), operation == 42 || operation == 47 {
                try advance()
                operators += 1
                let right = try unary(depth: depth)
                value = try calculate(value, right, operation: operation)
            }
            return value
        }

        mutating func unary(depth: Int) throws -> Number {
            var negative = false
            var signedDepth = depth
            while let sign = peek(), sign == 43 || sign == 45 {
                guard signedDepth < 32 else { throw Failure.invalid }
                signedDepth += 1
                negative = sign == 45 ? !negative : negative
                operators += 1
                try advance()
            }
            let value = try power(depth: signedDepth)
            return negative ? Number(-value.decimal, approximate: value.approximate) : value
        }

        mutating func power(depth: Int) throws -> Number {
            let base = try primary(depth: depth)
            let next = peek()
            let doubledStar = next == 42 && position + 1 < bytes.count && bytes[position + 1] == 42
            guard next == 94 || doubledStar else { return base }
            guard depth < 32 else { throw Failure.invalid }
            try advance()
            if doubledStar { try advance() }
            operators += 1
            // Reading the exponent through unary permits 2^-3 and makes chains
            // right-associative, while a leading sign still applies after powers.
            let exponent = try unary(depth: depth + 1)
            return try raise(base, to: exponent)
        }

        mutating func primary(depth: Int) throws -> Number {
            if peek() == 40 {
                guard depth < 32 else { throw Failure.invalid }
                try advance()
                let value = try expression(depth: depth + 1)
                guard peek() == 41 else { throw Failure.invalid }
                try advance()
                return value
            }
            return try literal()
        }

        mutating func literal() throws -> Number {
            skipSpaces()
            var digits: [UInt8] = []
            var fractionDigits = 0
            var hasPoint = false
            while position < bytes.count {
                let byte = bytes[position]
                if (48...57).contains(byte) {
                    digits.append(byte)
                    if hasPoint { fractionDigits += 1 }
                } else if byte == 46, !hasPoint { hasPoint = true }
                else { break }
                position += 1
            }
            guard !digits.isEmpty else { throw Failure.invalid }
            var exponent = -fractionDigits
            if position < bytes.count, bytes[position] == 69 || bytes[position] == 101 {
                position += 1
                var sign = 1
                if position < bytes.count, bytes[position] == 43 || bytes[position] == 45 {
                    sign = bytes[position] == 45 ? -1 : 1
                    position += 1
                }
                let start = position
                var explicit = 0
                while position < bytes.count, (48...57).contains(bytes[position]) {
                    explicit = explicit * 10 + Int(bytes[position] - 48)
                    guard explicit <= 512 else { throw Failure.invalid }
                    position += 1
                }
                guard position > start else { throw Failure.invalid }
                exponent += sign * explicit
            }
            try countToken()
            guard let first = digits.firstIndex(where: { $0 != 48 }) else { return Number(0) }
            digits.removeFirst(first)
            while digits.last == 48 { digits.removeLast(); exponent += 1 }
            guard digits.count <= 38, exponent >= -128 else { throw Failure.invalid }
            // Decimal stores a 128-bit coefficient and an exponent through 127.
            // Move excess positive powers into the coefficient when they fit exactly.
            if exponent > 127 {
                let zeros = exponent - 127
                guard digits.count + zeros <= 38 else { throw Failure.invalid }
                digits += Array(repeating: 48, count: zeros)
                exponent = 127
            }
            guard var coefficient = Decimal(string: String(decoding: digits, as: UTF8.self), locale: Calculator.locale) else {
                throw Failure.invalid
            }
            var value = Decimal()
            guard NSDecimalMultiplyByPowerOf10(&value, &coefficient, Int16(exponent), .plain) == .noError,
                  !value.isNaN else { throw Failure.invalid }
            return Number(value)
        }

        mutating func peek() -> UInt8? {
            skipSpaces()
            return position < bytes.count ? bytes[position] : nil
        }

        mutating func skipSpaces() {
            while position < bytes.count, bytes[position] == 32 { position += 1 }
        }

        mutating func advance() throws { position += 1; try countToken() }
        mutating func countToken() throws {
            tokens += 1
            guard tokens <= 256 else { throw Failure.invalid }
        }

        func raise(_ base: Number, to exponent: Number) throws -> Number {
            guard exponent.decimal >= -10_000, exponent.decimal <= 10_000 else { throw Failure.invalid }
            let integer = exponent.exact.digits.isEmpty || exponent.exact.exponent >= 0
            if base.decimal == 0 {
                guard exponent.decimal > 0 else { throw Failure.invalid }
                return Number(0, approximate: base.approximate || exponent.approximate || !integer)
            }
            if integer {
                let signed = NSDecimalNumber(decimal: exponent.decimal).intValue
                var remaining = abs(signed)
                var result = Number(1, approximate: base.approximate || exponent.approximate)
                var factor = signed < 0 ? try calculate(Number(1), base, operation: 47) : base
                // At most 14 squaring steps for |exponent| <= 10,000; never loop
                // once per power or build an unbounded recursive evaluation tree.
                while remaining > 0 {
                    if remaining & 1 == 1 { result = try calculate(result, factor, operation: 42) }
                    remaining >>= 1
                    if remaining > 0 { factor = try calculate(factor, factor, operation: 42) }
                }
                return result
            }

            guard base.decimal > 0 else { throw Failure.invalid }
            let lhs = try powerOperand(base)
            let rhs = try powerOperand(exponent)
            let powered = pow(lhs, rhs)
            guard powered.isFinite, powered > 0,
                  let value = Decimal(string: String(powered), locale: Calculator.locale),
                  !value.isNaN, value != 0 else { throw Failure.invalid }
            return Number(value, approximate: true)
        }

        func powerOperand(_ number: Number) throws -> Double {
            var source = number.decimal
            if number.approximate {
                // A computed recurring exponent such as 1/3 already has bounded
                // approximation semantics. Reuse its displayed precision for pow.
                guard let formatted = Calculator.format(number),
                      let rounded = Decimal(string: formatted.value, locale: Calculator.locale) else {
                    throw Failure.invalid
                }
                source = rounded
            }
            guard let value = Double(NSDecimalString(&source, Calculator.locale)) else { throw Failure.invalid }
            // Do not silently turn an exact Decimal near one into 1.0, or lose
            // significant digits from a large integer before calling native pow.
            guard value.isFinite,
                  Decimal(string: String(value), locale: Calculator.locale) == source else {
                throw Failure.invalid
            }
            return value
        }

        func calculate(_ left: Number, _ right: Number, operation: UInt8) throws -> Number {
            var lhs = left.decimal
            var rhs = right.decimal
            var value = Decimal()
            let status: Decimal.CalculationError
            switch operation {
            case 43: status = NSDecimalAdd(&value, &lhs, &rhs, .plain)
            case 45: status = NSDecimalSubtract(&value, &lhs, &rhs, .plain)
            case 42: status = NSDecimalMultiply(&value, &lhs, &rhs, .plain)
            default:
                guard rhs != 0 else { throw Failure.invalid }
                // Divide coefficients first, then restore scale. Foundation's
                // direct division can underflow on an exact reciprocal such as
                // 1 / 1e100 even though 1e-100 is representable.
                var numerator = lhs.significand
                var denominator = rhs.significand
                var quotient = Decimal()
                let division = NSDecimalDivide(&quotient, &numerator, &denominator, .plain)
                guard division == .noError || division == .lossOfPrecision else { throw Failure.invalid }
                if (lhs < 0) != (rhs < 0) { quotient = -quotient }
                let scaling = NSDecimalMultiplyByPowerOf10(&value, &quotient, Int16(lhs.exponent - rhs.exponent), .plain)
                status = scaling == .noError ? division : scaling
            }
            guard status == .noError || status == .lossOfPrecision, !value.isNaN else { throw Failure.invalid }
            let actual = Coefficient(value)
            let expected: Coefficient
            let compared: Coefficient
            switch operation {
            case 43: expected = Coefficient.add(left.exact, right.exact); compared = actual
            case 45: expected = Coefficient.add(left.exact, right.exact.negated); compared = actual
            case 42: expected = Coefficient.multiply(left.exact, right.exact); compared = actual
            default: expected = left.exact; compared = Coefficient.multiply(actual, right.exact)
            }
            let exact = compared == expected
            // Decimal can also wrap an out-of-range multiplication exponent
            // without returning an error. Such a magnitude change is not rounding.
            guard exact || expected.permitsRounding(to: compared) else { throw Failure.invalid }
            // Foundation can silently round multiply/divide while returning noError.
            // Compare bounded integer coefficients as well, never claim rounded math is exact.
            return Number(value, approximate: left.approximate || right.approximate || status == .lossOfPrecision || !exact)
        }
    }

    /// Exact verification only, not a second evaluator: at most 39 coefficient
    /// digits per Decimal, 78 after multiplication, and 294 after scale alignment.
    private struct Coefficient: Equatable {
        var digits: [Int] // Least significant first, with no leading/trailing zeros.
        var exponent: Int
        var negative: Bool

        init(_ value: Decimal) {
            var significand = value.significand
            digits = NSDecimalString(&significand, Calculator.locale).utf8
                .filter { (48...57).contains($0) }.reversed().map { Int($0 - 48) }
            exponent = value.exponent
            negative = value < 0
            normalize()
        }

        init(digits: [Int], exponent: Int, negative: Bool) {
            self.digits = digits
            self.exponent = exponent
            self.negative = negative
            normalize()
        }

        var negated: Self {
            Self(digits: digits, exponent: exponent, negative: !negative)
        }

        func permitsRounding(to other: Self) -> Bool {
            guard !digits.isEmpty, !other.digits.isEmpty, negative == other.negative else { return false }
            return abs((exponent + digits.count) - (other.exponent + other.digits.count)) <= 1
        }

        mutating func normalize() {
            while digits.last == 0 { digits.removeLast() }
            if digits.isEmpty { exponent = 0; negative = false; return }
            let zeros = digits.firstIndex(where: { $0 != 0 }) ?? 0
            if zeros > 0 { digits.removeFirst(zeros); exponent += zeros }
        }

        static func add(_ lhs: Self, _ rhs: Self) -> Self {
            if lhs.digits.isEmpty { return rhs }
            if rhs.digits.isEmpty { return lhs }
            let exponent = min(lhs.exponent, rhs.exponent)
            var a = Array(repeating: 0, count: lhs.exponent - exponent) + lhs.digits
            var b = Array(repeating: 0, count: rhs.exponent - exponent) + rhs.digits
            let count = max(a.count, b.count)
            a += Array(repeating: 0, count: count - a.count)
            b += Array(repeating: 0, count: count - b.count)
            if lhs.negative == rhs.negative {
                var carry = 0
                for index in a.indices {
                    let sum = a[index] + b[index] + carry
                    a[index] = sum % 10
                    carry = sum / 10
                }
                if carry > 0 { a.append(carry) }
                return Self(digits: a, exponent: exponent, negative: lhs.negative)
            }
            let swap = a.reversed().lexicographicallyPrecedes(b.reversed())
            if swap { Swift.swap(&a, &b) }
            var borrow = 0
            for index in a.indices {
                let difference = a[index] - b[index] - borrow
                a[index] = difference < 0 ? difference + 10 : difference
                borrow = difference < 0 ? 1 : 0
            }
            return Self(digits: a, exponent: exponent, negative: swap ? rhs.negative : lhs.negative)
        }

        static func multiply(_ lhs: Self, _ rhs: Self) -> Self {
            guard !lhs.digits.isEmpty, !rhs.digits.isEmpty else { return Self(0) }
            var digits = Array(repeating: 0, count: lhs.digits.count + rhs.digits.count)
            for left in lhs.digits.indices {
                for right in rhs.digits.indices { digits[left + right] += lhs.digits[left] * rhs.digits[right] }
            }
            for index in 0..<(digits.count - 1) {
                digits[index + 1] += digits[index] / 10
                digits[index] %= 10
            }
            return Self(digits: digits, exponent: lhs.exponent + rhs.exponent, negative: lhs.negative != rhs.negative)
        }
    }

    private static func format(_ number: Number) -> CalculatorResult? {
        var value = number.decimal
        if number.approximate, number.exact.digits.count > 16 {
            var source = value
            NSDecimalRound(&value, &source, 16 - number.exact.exponent - number.exact.digits.count, .plain)
            guard !value.isNaN, value != 0 || source == 0 else { return nil }
        }
        let exact = Coefficient(value)
        guard !exact.digits.isEmpty else { return CalculatorResult(value: "0", isApproximate: number.approximate) }
        let order = exact.exponent + exact.digits.count - 1
        let rendered: String
        if order < -6 || order >= 21 {
            let digits = exact.digits.reversed().map(String.init)
            let fraction = digits.dropFirst().joined()
            rendered = (exact.negative ? "-" : "") + digits[0]
                + (fraction.isEmpty ? "" : "." + fraction) + "e" + String(order)
        } else {
            rendered = NSDecimalString(&value, locale)
        }
        guard rendered.utf8.count <= 64 else { return nil }
        return CalculatorResult(value: rendered, isApproximate: number.approximate)
    }
}
