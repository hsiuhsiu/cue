import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Removes a bounded set of known tracking query parameters without fetching a URL.
public enum LinkCleaner {
    public static let maximumInputBytes = 64 * 1024

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidURL
        case inputTooLarge
    }

    public struct Result: Equatable, Sendable {
        public let url: String
        public let removedParameterCount: Int
        public let isProtected: Bool

        public init(url: String, removedParameterCount: Int, isProtected: Bool = false) {
            self.url = url
            self.removedParameterCount = removedParameterCount
            self.isProtected = isProtected
        }
    }

    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "twclid", "ttclid", "mc_cid", "mc_eid",
    ]

    // A signature can cover the entire query, including tracking-looking fields.
    // Do not try to infer a signing algorithm or repair a signature locally.
    private static let signatureNames: Set<String> = [
        "x-amz-signature", "x-goog-signature", "signature", "sig", "oauth_signature", "hmac",
    ]

    public static func clean(_ text: String) throws -> Result {
        guard text.utf8.count <= maximumInputBytes else { throw Error.inputTooLarge }
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty,
              !original.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }),
              !original.contains("\\"),
              hasValidPercentEscapes(original),
              let components = URLComponents(string: original),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, isValidHost(host),
              (components.port.map { (0...65_535).contains($0) } ?? true),
              components.url != nil else { throw Error.invalidURL }

        // Use Foundation only to validate. Rebuilding from URLComponents could
        // normalize the host, path, escapes, empty values, or query delimiters.
        let fragmentStart = original.firstIndex(of: "#") ?? original.endIndex
        let beforeFragment = original[..<fragmentStart]
        guard let queryStart = beforeFragment.firstIndex(of: "?") else {
            return Result(url: original, removedParameterCount: 0)
        }
        let query = beforeFragment[original.index(after: queryStart)...]
        let fields = query.split(separator: "&", omittingEmptySubsequences: false)
        var retained: [Substring] = []
        retained.reserveCapacity(fields.count)
        var removed = 0
        for field in fields {
            // Some servers treat literal semicolons as query separators, while
            // others treat them as value bytes. Preserve this ambiguous field.
            // A signature behind such a separator still protects the whole URL.
            if field.contains(";") {
                if field.split(separator: ";", omittingEmptySubsequences: false).contains(where: {
                    parameterName($0).map(signatureNames.contains) == true
                }) {
                    return Result(url: original, removedParameterCount: 0, isProtected: true)
                }
                retained.append(field)
                continue
            }
            // Invalid UTF-8 escapes may be meaningful opaque bytes to the site;
            // preserve those names. Only malformed %HH syntax is rejected above.
            guard let name = parameterName(field) else {
                retained.append(field)
                continue
            }
            if signatureNames.contains(name) {
                return Result(url: original, removedParameterCount: 0, isProtected: true)
            }
            if trackingNames.contains(name) || (name.hasPrefix("utm_") && name.utf8.count > 4) {
                removed += 1
            } else {
                retained.append(field)
            }
        }
        guard removed > 0 else { return Result(url: original, removedParameterCount: 0) }
        let retainedQuery = retained.isEmpty ? "" : "?" + retained.joined(separator: "&")
        let cleaned = String(original[..<queryStart]) + retainedQuery + original[fragmentStart...]
        return Result(url: cleaned, removedParameterCount: removed)
    }

    private static func parameterName(_ field: Substring) -> String? {
        String(field.prefix { $0 != "=" }).removingPercentEncoding?.lowercased()
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              !host.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }) else { return false }
        guard host.hasPrefix("[") else { return !host.contains("[") && !host.contains("]") }
        guard host.hasSuffix("]") else { return false }
        let literal = host.dropFirst().dropLast()
        let address = literal.prefix { $0 != "%" }
        // IPv6 zone identifiers, when present, must not be empty. The original
        // URL spelling (including a percent-encoded zone separator) is retained.
        if let zoneStart = literal.firstIndex(of: "%"), literal.index(after: zoneStart) == literal.endIndex {
            return false
        }
        var parsed = in6_addr()
        return address.withCString { inet_pton(AF_INET6, $0, &parsed) } == 1
    }

    private static func hasValidPercentEscapes(_ text: String) -> Bool {
        var bytes = text.utf8.makeIterator()
        while let byte = bytes.next() {
            if byte == 0x25 {
                guard let first = bytes.next(), let second = bytes.next(),
                      isHexDigit(first), isHexDigit(second) else { return false }
            }
        }
        return true
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }
}
