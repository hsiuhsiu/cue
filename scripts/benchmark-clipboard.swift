import Foundation
import CueCore

/// Synthetic persisted history only; never reads the system clipboard or Cue's real store.
@main
struct ClipboardSearchBenchmark {
    static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    // Nearest-rank percentiles, including the first query; no warm-up phase.
    static func percentile(_ samples: [Double], _ percent: Double) -> Double {
        let sorted = samples.sorted()
        return sorted[min(sorted.count - 1, max(0, Int(ceil(percent * Double(sorted.count))) - 1))]
    }

    static func summary(_ samples: [Double]) -> [String: Double] {
        ["median_ms": percentile(samples, 0.50), "p95_ms": percentile(samples, 0.95),
         "p99_ms": percentile(samples, 0.99), "max_ms": samples.max() ?? 0,
         "mean_ms": samples.reduce(0, +) / Double(samples.count)]
    }

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "native architecture"
        #endif
    }

    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueClipboardSearchBenchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let count = ClipboardStore.maximumEntries
        let maximumBytes = ClipboardStore.maximumTotalBytes
        let size = maximumBytes / count
        let remainder = maximumBytes % count
        var records: [[String: Any]] = []
        for index in 0..<count {
            let targetBytes = size + (index < remainder ? 1 : 0)
            let prefix = "Entry \(index) group\(index % 10) synthetic clipboard data. "
            let paragraph = "Ordinary text and links for deterministic testing. 正體中文剪貼簿歷史測試。 Café Résumé ＡＰＰＬＥ. https://example.invalid/docs/item-\(index)\n"
            let remaining = targetBytes - prefix.utf8.count
            var text = prefix + String(repeating: paragraph, count: remaining / paragraph.utf8.count)
            text += String(repeating: "x", count: targetBytes - text.utf8.count)
            precondition(text.utf8.count == targetBytes)
            records.append([
                "id": UUID().uuidString, "text": text,
                "copiedAt": now.addingTimeInterval(-Double(index)).timeIntervalSince1970 * 1_000,
            ])
        }
        let encoded = try JSONSerialization.data(withJSONObject: ["version": 1, "entries": records])
        try encoded.write(to: fileURL)
        let store = ClipboardStore(fileURL: fileURL)
        let loadStart = DispatchTime.now().uptimeNanoseconds
        let loaded = try await store.load(retention: .forever, now: now)
        let loadMS = milliseconds(since: loadStart)
        precondition(loaded.count == count)
        precondition(loaded.reduce(0) { $0 + $1.text.utf8.count } == maximumBytes)

        var timings: [Double] = []
        var byCategory: [String: [Double]] = [:]
        var counts: [String: Int] = [:]
        var firstQueries: [[String: Any]] = []
        for index in 0..<100 {
            let category: String
            let query: String
            switch index % 10 {
            case 0: category = "english_nonmatch"; query = "unmatched-needle-\(index)"
            case 1: category = "chinese_nonmatch"; query = "完全找不到的內容\(index)"
            case 2: category = "english_group"; query = "GROUP\(index / 10)"
            case 3: category = "chinese_match"; query = index < 50 ? "正體中文" : "剪貼簿歷史"
            case 4: category = "english_folded"; query = index < 50 ? "cafe resume apple" : "ＣＡＦÉ"
            case 5: category = "url_match"; query = "https://example.invalid/docs/item-\(index * 4)"
            case 6: category = "english_whitespace"; query = "  DETERMINISTIC  TESTING  "
            case 7: category = "mixed_nonmatch"; query = "剪貼簿 missing \(index)"
            case 8: category = "entry_match"; query = "entry \(index * 4) "
            default: category = "empty_query"; query = index < 50 ? "" : " \n\t "
            }
            let start = DispatchTime.now().uptimeNanoseconds
            let results = await store.search(query: query)
            let elapsed = milliseconds(since: start)
            timings.append(elapsed)
            byCategory[category, default: []].append(elapsed)
            counts[category, default: 0] += results.count
            if index < 10 {
                firstQueries.append(["category": category, "ms": elapsed, "matches": results.count])
            }
        }
        let output: [String: Any] = [
            "build": "swiftc -O, Swift 6, \(architecture)",
            "entries": loaded.count, "text_utf8_bytes": maximumBytes,
            "encoded_json_bytes": encoded.count,
            "load_decode_normalize_preview_ms": loadMS,
            "query_count": timings.count, "search": summary(timings),
            "by_category": byCategory.mapValues(summary), "matches_summed_by_category": counts,
            "first_ten_queries": firstQueries,
            "timing_scope": "MainActor await -> actor search -> return; no UI rendering; no warm-up queries",
        ]
        let outputData = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: outputData, as: UTF8.self))
    }
}
