import Foundation
import CoreFoundation

/// A presentation version, separate from the monotonically increasing build
/// number used by the updater. Read bundle metadata when presenting settings
/// or exporting diagnostics, never as part of launcher input or search.
public struct AppVersion: Equatable, Sendable {
    public enum Channel: String, Sendable {
        case stable
        case beta
        case dev
    }

    public let baseVersion: String?
    public let buildNumber: String?
    public let channel: Channel?
    public let prereleaseNumber: String?
    private let hasPrereleaseMetadata: Bool

    /// Invalid or absent presentation metadata deliberately has no version
    /// label. The UI can then use its localized "Development build" fallback.
    public var displayVersion: String? {
        guard let baseVersion, let channel else { return nil }
        switch channel {
        case .stable:
            return hasPrereleaseMetadata ? nil : baseVersion
        case .beta, .dev:
            guard let prereleaseNumber else { return nil }
            return "\(baseVersion)-\(channel.rawValue).\(prereleaseNumber)"
        }
    }

    public init(bundle: Bundle = .main) {
        let rawChannel = bundle.object(forInfoDictionaryKey: "CueBuildChannel")
        self.init(
            baseVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            // Only an absent channel identifies a legacy stable bundle. A
            // present value of the wrong plist type is invalid, not stable.
            channel: rawChannel.map { $0 as? String ?? "" },
            prereleaseNumber: Self.prereleaseString(
                bundle.object(forInfoDictionaryKey: "CuePrereleaseNumber")
            )
        )
    }

    public init(
        baseVersion: String?,
        buildNumber: String? = nil,
        channel: String? = nil,
        prereleaseNumber: String? = nil
    ) {
        self.baseVersion = baseVersion.flatMap { Self.isBaseVersion($0) ? $0 : nil }
        self.buildNumber = buildNumber.flatMap { Self.isPositiveInteger($0) ? $0 : nil }
        if let channel {
            self.channel = Channel(rawValue: channel)
        } else {
            self.channel = .stable
        }
        self.prereleaseNumber = prereleaseNumber.flatMap { Self.isPositiveInteger($0) ? $0 : nil }
        self.hasPrereleaseMetadata = prereleaseNumber != nil
    }

    private static func prereleaseString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)) {
            return number.stringValue
        }
        // Preserve the presence of malformed metadata so a stable bundle with
        // a stray prerelease value cannot silently acquire a stable label.
        return ""
    }

    private static func isBaseVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 3 && components.allSatisfy { isUnsignedInteger($0) }
    }

    private static func isPositiveInteger(_ value: String) -> Bool {
        isUnsignedInteger(value[...]) && value != "0"
    }

    private static func isUnsignedInteger(_ value: Substring) -> Bool {
        let bytes = value.utf8
        guard let first = bytes.first, bytes.count <= 10 else { return false }
        if first == 48 && bytes.count != 1 { return false }
        guard bytes.allSatisfy({ (48...57).contains($0) }), let integer = Int(value) else { return false }
        return integer <= 2_147_483_647
    }
}
