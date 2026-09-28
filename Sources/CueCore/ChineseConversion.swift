import Foundation

public enum ChineseConversionTarget: String, CaseIterable, Sendable {
    case traditionalTaiwan
    case simplifiedChina
}

public enum ChineseConversionError: Error, Sendable {
    case invalidResource
    case inputTooLarge
}

/// Offline conversion using OpenCC 1.4.2 dictionary/configuration semantics.
/// Construct lazily on a background executor and reuse this immutable converter.
/// OpenCC data and algorithm attribution: docs/chinese-conversion-data.md.
public final class ChineseConverter: Sendable {
    public static let maximumInputBytes = 256 * 1_024
    private let words: [UInt32]
    private let edgeStart: Int
    private let valueStart: Int
    private let configurations: [String: Configuration]

    private struct Configuration: Decodable, Sendable {
        let normalization: [[Int]]
        let segmentation: Int
        let stages: [[Int]]
    }

    private struct Metadata: Decodable {
        let version: String
        let commit: String
        let configurations: [String: Configuration]
    }

    public init(resourceURL: URL) throws {
        let data = try Data(contentsOf: resourceURL, options: .mappedIfSafe)
        guard data.count >= 24, data.count <= 16 * 1_024 * 1_024,
              data.prefix(8) == Data("CUECC001".utf8) else { throw ChineseConversionError.invalidResource }
        let (metadataSize, nodeCount, edgeCount, valueCount) = data.withUnsafeBytes { bytes in
            (Int(bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian),
             Int(bytes.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian),
             Int(bytes.loadUnaligned(fromByteOffset: 16, as: UInt32.self).littleEndian),
             Int(bytes.loadUnaligned(fromByteOffset: 20, as: UInt32.self).littleEndian))
        }
        guard metadataSize <= 65_536, nodeCount > 0, nodeCount <= 1_000_000,
              edgeCount <= 1_000_000, valueCount <= 1_000_000 else { throw ChineseConversionError.invalidResource }
        let payloadStart = 24 + ((metadataSize + 3) / 4) * 4
        let wordCount = nodeCount * 4 + edgeCount * 2 + valueCount
        guard data.count == payloadStart + wordCount * 4 else { throw ChineseConversionError.invalidResource }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data[24..<(24 + metadataSize)])
        guard metadata.version == "1.4.2",
              metadata.commit == "025f371dc76b598d77384fbdab90c937471844d8",
              Set(metadata.configurations.keys) == Set(ChineseConversionTarget.allCases.map(\.rawValue))
        else { throw ChineseConversionError.invalidResource }
        let words: [UInt32] = data.withUnsafeBytes { bytes in
            (0..<wordCount).map { bytes.loadUnaligned(fromByteOffset: payloadStart + $0 * 4, as: UInt32.self).littleEndian }
        }
        let edgeStart = nodeCount * 4
        let valueStart = edgeStart + edgeCount * 2
        for node in 0..<nodeCount {
            let offset = node * 4
            let first = Int(words[offset]), count = Int(words[offset + 1])
            guard first + count <= edgeCount,
                  Int(words[offset + 2]) + Int(words[offset + 3]) <= valueCount else {
                throw ChineseConversionError.invalidResource
            }
            var previous: UInt32?
            for edge in first..<(first + count) {
                let label = words[edgeStart + edge * 2]
                let child = Int(words[edgeStart + edge * 2 + 1])
                guard Unicode.Scalar(label) != nil, child > node, child < nodeCount,
                      previous == nil || previous! < label else { throw ChineseConversionError.invalidResource }
                previous = label
            }
        }
        guard words[valueStart...].allSatisfy({ Unicode.Scalar($0) != nil }) else {
            throw ChineseConversionError.invalidResource
        }
        for configuration in metadata.configurations.values {
            guard (0..<nodeCount).contains(configuration.segmentation),
                  configuration.normalization.count <= 2, (1...8).contains(configuration.stages.count),
                  (configuration.normalization + configuration.stages).allSatisfy({ group in
                      (1...8).contains(group.count) && group.allSatisfy { (0..<nodeCount).contains($0) }
                  }) else { throw ChineseConversionError.invalidResource }
        }
        self.words = words
        self.edgeStart = edgeStart
        self.valueStart = valueStart
        self.configurations = metadata.configurations
    }

    /// Preserves unmapped Unicode scalars, punctuation, whitespace, emoji and NUL.
    /// Cancellation is checked during scans; it never produces partial output.
    public func convert(_ text: String, to target: ChineseConversionTarget) throws -> String {
        try Task.checkCancellation()
        guard text.utf8.count <= Self.maximumInputBytes else { throw ChineseConversionError.inputTooLarge }
        guard !text.isEmpty else { return text }
        let configuration = configurations[target.rawValue]!
        var normalized = text.unicodeScalars.map(\.value)
        for group in configuration.normalization {
            normalized = try convertSegment(normalized[...], group: group)
        }
        var output: [UInt32] = []
        output.reserveCapacity(normalized.count)
        var cursor = 0
        var unmatchedStart = 0
        var untilCancellationCheck = 0

        func appendSegment(_ range: Range<Int>) throws {
            guard !range.isEmpty else { return }
            var converted = Array(normalized[range])
            for group in configuration.stages {
                try Task.checkCancellation()
                converted = try convertSegment(converted[...], group: group)
            }
            output.append(contentsOf: converted)
        }

        // OpenCC mmseg: longest known phrase; consecutive unmatched scalars stay
        // together. Keep those boundaries through every later conversion stage.
        while cursor < normalized.count {
            untilCancellationCheck -= 1
            if untilCancellationCheck <= 0 { try Task.checkCancellation(); untilCancellationCheck = 1_024 }
            if let match = longestMatch(normalized[...], at: cursor, root: configuration.segmentation) {
                try appendSegment(unmatchedStart..<cursor)
                try appendSegment(cursor..<match.end)
                cursor = match.end
                unmatchedStart = cursor
            } else {
                cursor = Self.unmatchedEnd(normalized[...], at: cursor)
            }
        }
        try appendSegment(unmatchedStart..<normalized.count)
        try Task.checkCancellation()
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(output.count)
        for scalar in output { scalars.append(Unicode.Scalar(scalar)!) }
        return String(scalars)
    }

    private struct Match {
        let end: Int
        let valueOffset: Int
        let valueCount: Int
    }

    private func longestMatch(_ input: ArraySlice<UInt32>, at start: Int, root: Int) -> Match? {
        var node = root
        var cursor = start
        var match: Match?
        while cursor < input.endIndex {
            let offset = node * 4
            var lower = Int(words[offset])
            var upper = lower + Int(words[offset + 1])
            let target = input[cursor]
            let end = upper
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if words[edgeStart + middle * 2] < target { lower = middle + 1 } else { upper = middle }
            }
            guard lower < end, words[edgeStart + lower * 2] == target else { break }
            node = Int(words[edgeStart + lower * 2 + 1])
            cursor += 1
            let length = Int(words[node * 4 + 3])
            if length > 0 {
                match = Match(end: cursor, valueOffset: Int(words[node * 4 + 2]), valueCount: length)
            }
        }
        return match
    }

    private func convertSegment(_ input: ArraySlice<UInt32>, group: [Int]) throws -> [UInt32] {
        var output: [UInt32] = []
        output.reserveCapacity(input.count)
        var cursor = input.startIndex
        var untilCancellationCheck = 0
        while cursor < input.endIndex {
            untilCancellationCheck -= 1
            if untilCancellationCheck <= 0 { try Task.checkCancellation(); untilCancellationCheck = 1_024 }
            // Short-circuit groups prefer the first matching dictionary, even
            // when a later dictionary could match a longer string.
            var match: Match?
            for root in group {
                if let found = longestMatch(input, at: cursor, root: root) { match = found; break }
            }
            if let match {
                let offset = valueStart + match.valueOffset
                output.append(contentsOf: words[offset..<(offset + match.valueCount)])
                cursor = match.end
            } else {
                let end = Self.unmatchedEnd(input, at: cursor)
                output.append(contentsOf: input[cursor..<end])
                cursor = end
            }
        }
        return output
    }

    // OpenCC preserves a complete ideographic description sequence as one
    // unmatched unit; its component characters must not be rewritten separately.
    private static func unmatchedEnd(_ input: ArraySlice<UInt32>, at start: Int) -> Int {
        guard idsArity(input[start]) > 0 else { return start + 1 }
        var scalarCount = 0
        func consume(_ cursor: Int, depth: Int) -> Int? {
            guard cursor < input.endIndex, depth > 0, scalarCount < 64 else { return nil }
            scalarCount += 1
            var end = cursor + 1
            for _ in 0..<idsArity(input[cursor]) {
                guard let next = consume(end, depth: depth - 1) else { return nil }
                end = next
            }
            return end
        }
        return consume(start, depth: 16) ?? start + 1
    }

    private static func idsArity(_ scalar: UInt32) -> Int {
        switch scalar {
        case 0x2FF2, 0x2FF3: 3
        case 0x2FFE, 0x2FFF: 1
        case 0x2FF0...0x2FFF: 2
        default: 0
        }
    }
}
