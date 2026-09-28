import Foundation

/// Optional exact command aliases, validated and normalized outside the typing path.
public struct ChineseConversionAliases: Codable, Equatable, Sendable {
    public static let maximumBytes = 32
    public static let defaults = Self(
        traditional: "st", simplified: "ts",
        normalizedTraditional: "st", normalizedSimplified: "ts"
    )

    public enum ValidationError: Error, Equatable, Sendable {
        case tooLong
        case controlCharacters
        case duplicate
    }

    public let traditional: String
    public let simplified: String
    private let normalizedTraditional: String
    private let normalizedSimplified: String

    public init(traditional: String, simplified: String) throws {
        let traditional = try Self.validate(traditional)
        let simplified = try Self.validate(simplified)
        guard traditional.normalized.isEmpty || traditional.normalized != simplified.normalized else {
            throw ValidationError.duplicate
        }
        self.init(
            traditional: traditional.display, simplified: simplified.display,
            normalizedTraditional: traditional.normalized, normalizedSimplified: simplified.normalized
        )
    }

    private init(traditional: String, simplified: String,
                 normalizedTraditional: String, normalizedSimplified: String) {
        self.traditional = traditional
        self.simplified = simplified
        self.normalizedTraditional = normalizedTraditional
        self.normalizedSimplified = normalizedSimplified
    }

    func command(normalizedQuery: String) -> LauncherResult? {
        guard !normalizedQuery.isEmpty else { return nil }
        if normalizedQuery == normalizedTraditional { return .convertToTraditional }
        if normalizedQuery == normalizedSimplified { return .convertToSimplified }
        return nil
    }

    private static func validate(_ value: String) throws -> (display: String, normalized: String) {
        guard !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }) else { throw ValidationError.controlCharacters }
        let display = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let normalized = SearchEngine.normalize(display)
        guard display.utf8.count <= maximumBytes, normalized.utf8.count <= maximumBytes else {
            throw ValidationError.tooLong
        }
        return (display, normalized)
    }

    private enum CodingKeys: String, CodingKey { case traditional, simplified }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            traditional: container.decode(String.self, forKey: .traditional),
            simplified: container.decode(String.self, forKey: .simplified)
        )
    }
}
