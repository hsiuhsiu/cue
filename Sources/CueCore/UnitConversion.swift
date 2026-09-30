import Foundation

public struct ConversionUnit: Identifiable, Hashable, Sendable {
    public let id: String
    public let symbol: String
    public let isCurrency: Bool

    public init(id: String, symbol: String, isCurrency: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.isCurrency = isCurrency
    }
}

public struct ConversionQuery: Equatable, Sendable {
    public let amount: Decimal
    public let source: ConversionUnit
    public let target: ConversionUnit?

    public init(amount: Decimal, source: ConversionUnit, target: ConversionUnit? = nil) {
        self.amount = amount
        self.source = source
        self.target = target
    }

    public static func parse(_ input: String) -> Self? {
        guard let first = input.unicodeScalars.prefix(257).first(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }),
              (48...57).contains(first.value) || first == "+" || first == "-" || first.value == 0x2212,
              input.utf8.prefix(257).count <= 256 else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
        let bytes = Array(trimmed.utf8)
        var index = 0
        if bytes.first == 43 || bytes.first == 45 { index += 1 }
        let numberStart = index
        var digits = 0
        var point = false
        while index < bytes.count {
            let byte = bytes[index]
            if (48...57).contains(byte) { digits += 1 }
            else if byte == 46 && !point { point = true }
            else { break }
            index += 1
        }
        guard digits > 0, index > numberStart else { return nil }
        // E begins EUR as well as a scientific exponent. Consume it only when
        // followed by a digit or sign; malformed exponent syntax still fails below.
        if index + 1 < bytes.count, bytes[index] == 69 || bytes[index] == 101,
           (48...57).contains(bytes[index + 1]) || bytes[index + 1] == 43 || bytes[index + 1] == 45 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            let exponentStart = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            guard index > exponentStart else { return nil }
        }
        guard index < bytes.count else { return nil }
        let suffix = String(decoding: bytes[index...], as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let pair = UnitConversion.parseUnits(suffix) else { return nil }
        let literal = String(decoding: bytes[..<index], as: UTF8.self)
        guard let parsed = Calculator.evaluate("(" + literal + ")+0"), !parsed.isApproximate,
              let amount = Decimal(string: parsed.value, locale: UnitConversion.locale) else { return nil }
        return Self(amount: amount, source: pair.0, target: pair.1)
    }
}

public struct ConversionResult: Hashable, Sendable {
    public let value: String
    public let unitSymbol: String
    public let targetID: String
    public let isCurrency: Bool
    public let isApproximate: Bool

    public init(value: String, unitSymbol: String, targetID: String, isCurrency: Bool, isApproximate: Bool) {
        self.value = value
        self.unitSymbol = unitSymbol
        self.targetID = targetID
        self.isCurrency = isCurrency
        self.isApproximate = isApproximate
    }
}

public struct CurrencyRateSnapshot: Equatable, Sendable {
    public let base: String
    public let rates: [String: Decimal]
    public let updatedAt: Date
    public let nextUpdateAt: Date

    public init(base: String, rates: [String: Decimal], updatedAt: Date, nextUpdateAt: Date) {
        self.base = base
        self.rates = rates
        self.updatedAt = updatedAt
        self.nextUpdateAt = nextUpdateAt
    }
}

/// A fixed, offline conversion catalog. No discovery, I/O, or networking runs here.
public enum UnitConversion {
    fileprivate static let locale = Locale(identifier: "en_US_POSIX")

    public static func convert(_ query: ConversionQuery) -> [ConversionResult] {
        guard !query.source.isCurrency, !query.amount.isNaN,
              let source = definitions[query.source.id], source.unit == query.source else { return [] }
        let targets: [Definition]
        if let target = query.target {
            guard let found = definitions[target.id], found.unit == target, found.dimension == source.dimension else { return [] }
            targets = [found]
        } else {
            targets = source.defaults.compactMap { definitions[$0] }
        }
        let amount = decimalString(query.amount)
        if source.dimension == .temperature {
            let minimum: Decimal = source.unit.id == "C" ? Decimal(string: "-273.15")!
                : source.unit.id == "F" ? Decimal(string: "-459.67")! : 0
            guard query.amount >= minimum else { return [] }
        }
        return targets.prefix(3).compactMap { target in
            let expression: String
            if source.dimension == .temperature {
                // Direct affine transforms avoid rounding through a Kelvin
                // intermediate, especially at absolute zero and freezing points.
                switch (source.unit.id, target.unit.id) {
                case ("C", "F"): expression = "(\(amount))*9/5+32"
                case ("F", "C"): expression = "((\(amount))-32)*5/9"
                case ("C", "K"): expression = "(\(amount))+273.15"
                case ("K", "C"): expression = "(\(amount))-273.15"
                case ("F", "K"): expression = "((\(amount))+459.67)*5/9"
                case ("K", "F"): expression = "(\(amount))*9/5-459.67"
                default: expression = "(\(amount))+0"
                }
            } else {
                expression = "(\(amount))*\(source.numerator)*\(target.denominator)/(\(source.denominator)*\(target.numerator))"
            }
            guard let calculated = Calculator.evaluate(expression) else { return nil }
            return result(calculated, target: target.unit)
        }
    }

    public static func convertCurrency(_ query: ConversionQuery, rates snapshot: CurrencyRateSnapshot) -> [ConversionResult] {
        guard query.source.isCurrency, currencies.contains(query.source.id), !query.amount.isNaN,
              currencies.contains(snapshot.base), snapshot.updatedAt.timeIntervalSince1970.isFinite,
              snapshot.nextUpdateAt.timeIntervalSince1970.isFinite else { return [] }
        func rate(_ code: String) -> Decimal? {
            if code == snapshot.base { return 1 }
            guard let rate = snapshot.rates[code], !rate.isNaN, rate > 0 else { return nil }
            return rate
        }
        guard let sourceRate = rate(query.source.id) else { return [] }
        let targets: [String]
        if let target = query.target {
            guard target.isCurrency, currencies.contains(target.id) else { return [] }
            targets = [target.id]
        } else {
            targets = Array(["TWD", "USD", "EUR", "JPY"].filter { $0 != query.source.id }.prefix(3))
        }
        return targets.compactMap { code in
            guard let targetRate = rate(code),
                  let calculated = Calculator.evaluate("(\(decimalString(query.amount)))*\(decimalString(targetRate))/\(decimalString(sourceRate))") else { return nil }
            return result(calculated, target: ConversionUnit(id: code, symbol: code, isCurrency: true))
        }
    }

    fileprivate static func parseUnits(_ suffix: String) -> (ConversionUnit, ConversionUnit?)? {
        if let source = lookup(suffix) { return (source, nil) }
        var parts: (String, String)?
        for separator in ["→", "轉"] where suffix.contains(separator) {
            let pieces = suffix.components(separatedBy: separator)
            guard parts == nil, pieces.count == 2 else { return nil }
            parts = (pieces[0], pieces[1])
        }
        if parts == nil {
            let words = suffix.split(separator: " ").map(String.init)
            let separators = words.indices.filter { $0 > 0 && $0 < words.count - 1 && ["to", "in"].contains(words[$0].lowercased()) }
            guard separators.count == 1, let index = separators.first else { return nil }
            parts = (words[..<index].joined(separator: " "), words[(index + 1)...].joined(separator: " "))
        }
        guard let parts, let source = lookup(parts.0.trimmingCharacters(in: .whitespaces)),
              let target = lookup(parts.1.trimmingCharacters(in: .whitespaces)) else { return nil }
        if source.isCurrency || target.isCurrency {
            guard source.isCurrency && target.isCurrency else { return nil }
        } else {
            guard definitions[source.id]?.dimension == definitions[target.id]?.dimension else { return nil }
        }
        return (source, target)
    }

    private static func lookup(_ name: String) -> ConversionUnit? {
        if let id = aliases[name], let definition = definitions[id] { return definition.unit }
        // Currency codes are case-insensitive; short metric symbols keep their
        // explicit case so M or ML cannot silently mean metres or millilitres.
        let currency = currencyAliases[name] ?? name.uppercased()
        if currencies.contains(currency) { return ConversionUnit(id: currency, symbol: currency, isCurrency: true) }
        if name.count > 3, let id = aliases[name.lowercased()] { return definitions[id]?.unit }
        return nil
    }

    private static func result(_ calculated: CalculatorResult, target: ConversionUnit) -> ConversionResult? {
        guard var value = Decimal(string: calculated.value, locale: locale), !value.isNaN else { return nil }
        var coefficient = value.significand
        var significant = NSDecimalString(&coefficient, locale).filter(\.isNumber)
        while significant.last == "0" { significant.removeLast() }
        let original = value
        let digits = significant.count
        // Unit answers favor quick scanning; currency retains its existing
        // precision before the separate two-decimal money formatting below.
        let maximumDigits = target.isCurrency ? 16 : 8
        if digits > maximumDigits {
            let order = value.exponent + NSDecimalString(&coefficient, locale).filter(\.isNumber).count - 1
            var source = original
            NSDecimalRound(&value, &source, maximumDigits - 1 - order, .plain)
        }
        if target.isCurrency, value <= -oneCent || value >= oneCent {
            var source = value
            NSDecimalRound(&value, &source, 2, .plain)
        }
        guard !value.isNaN, value != 0 || original == 0 else { return nil }
        let plain = decimalString(value)
        // Calculator supplies consistent compact scientific notation. Adding zero
        // does not round the already bounded display value or introduce a Double.
        guard let formatted = Calculator.evaluate("(\(plain))+0") else { return nil }
        return ConversionResult(value: formatted.value, unitSymbol: target.symbol, targetID: target.id,
                                isCurrency: target.isCurrency,
                                isApproximate: target.isCurrency || calculated.isApproximate || value != original)
    }

    private static func decimalString(_ value: Decimal) -> String {
        var copy = value
        return NSDecimalString(&copy, locale)
    }
    private static let oneCent = Decimal(string: "0.01")!

    private enum Dimension: Sendable { case length, area, mass, volume, temperature, time, speed }
    private struct Definition: Sendable {
        let unit: ConversionUnit
        let dimension: Dimension
        let numerator: String
        let denominator: String
        let defaults: [String]
        let aliases: [String]
    }
    private static func unit(_ id: String, _ symbol: String, _ dimension: Dimension, _ factor: String,
                             _ defaults: [String], _ aliases: [String], denominator: String = "1") -> Definition {
        Definition(unit: ConversionUnit(id: id, symbol: symbol), dimension: dimension,
                   numerator: factor, denominator: denominator, defaults: defaults, aliases: aliases)
    }

    private static let catalog: [Definition] = [
        unit("mm", "mm", .length, "0.001", ["cm", "m", "in"], ["mm", "millimeter", "millimeters", "millimetre", "millimetres", "毫米", "公釐"]),
        unit("cm", "cm", .length, "0.01", ["in", "m", "ft"], ["cm", "centimeter", "centimeters", "centimetre", "centimetres", "公分", "厘米"]),
        unit("m", "m", .length, "1", ["ft", "cm", "km"], ["m", "meter", "meters", "metre", "metres", "公尺", "米"]),
        unit("km", "km", .length, "1000", ["mi", "m", "ft"], ["km", "kilometer", "kilometers", "kilometre", "kilometres", "公里", "千米"]),
        unit("in", "in", .length, "0.0254", ["cm", "mm", "ft"], ["in", "inch", "inches", "英吋", "英寸"]),
        unit("ft", "ft", .length, "0.3048", ["m", "cm", "in"], ["ft", "foot", "feet", "英尺", "呎"]),
        unit("yd", "yd", .length, "0.9144", ["m", "ft", "cm"], ["yd", "yard", "yards", "碼"]),
        unit("mi", "mi", .length, "1609.344", ["km", "m", "ft"], ["mi", "mile", "miles", "英里"]),
        unit("m2", "m²", .area, "1", ["ping", "ft2", "ha"], ["m²", "m2", "㎡", "sq m", "square meter", "square meters", "square metre", "square metres", "平方公尺", "平方米"]),
        unit("cm2", "cm²", .area, "0.0001", ["ping", "m2", "ft2"], ["cm²", "cm2", "sq cm", "square centimeter", "square centimeters", "平方公分", "平方厘米"]),
        unit("ft2", "ft²", .area, "0.09290304", ["ping", "m2", "ha"], ["ft²", "ft2", "sq ft", "square foot", "square feet", "平方英尺", "平方呎"]),
        unit("ping", "坪", .area, "400", ["m2", "ft2", "ha"], ["坪", "ping"], denominator: "121"),
        unit("ha", "ha", .area, "10000", ["ping", "m2", "acre"], ["ha", "hectare", "hectares", "公頃"]),
        unit("acre", "acre", .area, "4046.8564224", ["ping", "m2", "ha"], ["acre", "acres", "英畝"]),
        unit("g", "g", .mass, "0.001", ["kg", "oz", "lb"], ["g", "gram", "grams", "公克", "克"]),
        unit("kg", "kg", .mass, "1", ["lb", "g", "oz"], ["kg", "kilogram", "kilograms", "公斤", "千克"]),
        unit("oz", "oz", .mass, "0.028349523125", ["g", "kg", "lb"], ["oz", "ounce", "ounces", "盎司"]),
        unit("lb", "lb", .mass, "0.45359237", ["kg", "g", "oz"], ["lb", "lbs", "pound", "pounds", "磅"]),
        unit("mL", "mL", .volume, "0.001", ["L", "USfloz", "USgal"], ["mL", "ml", "milliliter", "milliliters", "millilitre", "millilitres", "毫升", "毫公升"]),
        unit("L", "L", .volume, "1", ["mL", "USgal", "USfloz"], ["L", "l", "liter", "liters", "litre", "litres", "公升", "升"]),
        unit("USfloz", "US fl oz", .volume, "0.0295735295625", ["mL", "L", "USgal"], ["US fl oz", "us fl oz", "fl oz", "US fluid ounce", "US fluid ounces", "us fluid ounce", "us fluid ounces", "美制液量盎司", "美制液盎司"]),
        unit("USgal", "US gal", .volume, "3.785411784", ["L", "mL", "USfloz"], ["US gal", "us gal", "gal", "gallon", "gallons", "US gallon", "US gallons", "us gallon", "us gallons", "美制加侖"]),
        unit("C", "°C", .temperature, "1", ["F", "K"], ["°C", "°c", "C", "c", "℃", "celsius", "攝氏", "攝氏度"]),
        unit("F", "°F", .temperature, "1", ["C", "K"], ["°F", "°f", "F", "f", "℉", "fahrenheit", "華氏", "華氏度"]),
        unit("K", "K", .temperature, "1", ["C", "F"], ["K", "kelvin", "kelvins", "克耳文", "開爾文"]),
        unit("s", "s", .time, "1", ["min", "h", "day"], ["s", "sec", "second", "seconds", "秒"]),
        unit("min", "min", .time, "60", ["s", "h", "day"], ["min", "minute", "minutes", "分鐘", "分"]),
        unit("h", "h", .time, "3600", ["min", "s", "day"], ["h", "hr", "hour", "hours", "小時", "時"]),
        unit("day", "day", .time, "86400", ["h", "min", "s"], ["d", "day", "days", "天", "日"]),
        unit("kmh", "km/h", .speed, "5", ["mph", "ms"], ["km/h", "kph", "公里/小時", "公里每小時"], denominator: "18"),
        unit("ms", "m/s", .speed, "1", ["kmh", "mph"], ["m/s", "公尺/秒", "公尺每秒"]),
        unit("mph", "mph", .speed, "0.44704", ["kmh", "ms"], ["mph", "英里/小時", "英里每小時"]),
    ]
    private static let definitions = Dictionary(uniqueKeysWithValues: catalog.map { ($0.unit.id, $0) })
    private static let aliases = Dictionary(uniqueKeysWithValues: catalog.flatMap { definition in definition.aliases.map { ($0, definition.unit.id) } })
    private static let currencies: Set<String> = Set("AED ARS AUD BDT BGN BHD BND BRL CAD CHF CLP CNY COP CZK DKK EGP EUR GBP HKD HUF IDR ILS INR ISK JPY KHR KRW KWD LAK LKR MAD MMK MOP MXN MYR NOK NPR NZD PHP PKR PLN QAR RON RSD RUB SAR SEK SGD THB TRY TWD UAH USD VND ZAR".split(separator: " ").map(String.init))
    private static let currencyAliases = ["台幣": "TWD", "臺幣": "TWD", "新台幣": "TWD", "新臺幣": "TWD", "美元": "USD", "美金": "USD", "歐元": "EUR", "日圓": "JPY", "日元": "JPY", "英鎊": "GBP", "人民幣": "CNY", "港幣": "HKD", "韓元": "KRW", "澳幣": "AUD", "澳元": "AUD", "加幣": "CAD", "加元": "CAD", "新加坡元": "SGD"]
}
