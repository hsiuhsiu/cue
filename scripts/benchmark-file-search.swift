import CueCore
import Foundation

@main struct BenchmarkFileSearch {
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    static func main() {
        let clock = ContinuousClock()
        // Deterministic, synthetic metadata only. Match the production bound of
        // three 128-candidate queries, including overlap between query tiers.
        let names = ["report", "Report", "REPORT", "report-alpha.txt", "report-zeta.pdf",
                     "report-café.txt", "report-cafe.txt", "annual report.pdf", "報告.txt",
                     "年度報告.pdf", "Café.txt", "cafe.txt", "a*b?.txt", "unrelated.txt"]
        let candidates = (0..<384).map { index in
            let folder = "/Users/cue-fixture/Documents/Folder-\((index * 37) % 23)"
            let name = names[(index * 11) % names.count]
            return FileSearchResult(
                url: URL(fileURLWithPath: folder).appendingPathComponent(name), name: name,
                parentPath: folder
            )
        }
        let terms = ["report", "報告", "cafe", "*b?", "missing"]
        var checksum = 0
        for term in terms {
            let firstStart = clock.now
            let first = FileSearchRanking.results(from: candidates, term: term, limit: 9)
            let cold = milliseconds(firstStart.duration(to: clock.now))
            for _ in 0..<12 {
                checksum += FileSearchRanking.results(from: candidates, term: term, limit: 9).count
            }
            var samples: [Double] = []
            for _ in 0..<180 {
                let start = clock.now
                let results = FileSearchRanking.results(from: candidates, term: term, limit: 9)
                samples.append(milliseconds(start.duration(to: clock.now)))
                checksum += results.count
            }
            samples.sort()
            print(String(format: "Ranking %@: first %.3f ms, median %.3f ms, p95 %.3f ms, p99 %.3f ms, rows %d",
                         term, cold, samples[samples.count / 2], samples[Int(Double(samples.count) * 0.95)],
                         samples[Int(Double(samples.count) * 0.99)], first.count))
        }
        // Identities are consumed repeatedly by selection, shortcuts and view
        // diffing. Keep this separate from background ranking measurements.
        let visible = FileSearchRanking.results(from: candidates, term: "report", limit: 9)
        let identityStart = clock.now
        for _ in 0..<20_000 {
            for result in visible { checksum &+= result.id.utf8.count }
        }
        print(String(format: "Visible file identities, 20,000 x 9 reads: %.3f ms", milliseconds(identityStart.duration(to: clock.now))))
        print("Synthetic checksum: \(checksum)")
    }
}
