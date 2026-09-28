import Foundation

/// A user-added browser choice. Resolve its bundle identifier on the current Mac
/// only when needed; app locations can differ between machines and installations.
public struct WebSearchBrowser: Codable, Hashable, Sendable, Identifiable {
    public static let maximumAddedBrowsers = 8

    public let bundleIdentifier: String
    public let name: String
    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// Builds search destinations locally; creating a URL never sends a request.
public enum WebSearch {
    /// Use the original text, rather than the launcher's normalized matching key.
    /// Call when the search action is executed, not while the user is typing.
    public static func googleURL(for query: String) -> URL? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // URLComponents permits literal + in a query, but Google interprets it
        // as a space when decoding form-style query parameters.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
