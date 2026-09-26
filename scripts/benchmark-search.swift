import Foundation

// Build this together with Sources/CueCore/*.swift using swiftc -O or -Onone.
// This measures synchronous core search, excluding UI, app icons and activation.
@main
enum SearchBenchmark {
    static func main() {
        let scanStart = DispatchTime.now().uptimeNanoseconds
        let installed = AppIndex.scan()
        print("scan apps=\(installed.count) ms=\(Double(DispatchTime.now().uptimeNanoseconds - scanStart) / 1_000_000)")
        let names = ["Safari", "Terminal", "Visual Studio Code", "Code Editor", "Activity Monitor", "Calendar", "System Settings", "Google Chrome", "Microsoft Excel", "Adobe Photoshop", "Café Editor", "備忘錄", "音樂", "更新工具", "Developer Utilities"]
        let synthetic = (0..<1_000).map { index in
            IndexedApplication(name: "\(names[index % names.count]) \(index)", url: URL(fileURLWithPath: "/Bench/\(index).app"))
        }
        let queries = ["s", "sa", "saf", "safa", "safari", "t", "te", "ter", "term", "terminal", "v", "vs", "vsc", "c", "co", "cod", "code", "trm", "sfr", "chrome", "mon", "index", "reindex", "更新", "備", "音樂", "cafe", "xyzzy", "developer utilities", "\t  CODE  "]
        var checksum = 0
        for (label, apps) in [("installed", installed), ("synthetic1000", synthetic)] {
            for _ in 0..<20 {
                for query in queries { checksum &+= LauncherResult.search(apps, query: query).count }
            }
            var samples: [Double] = []
            for _ in 0..<100 {
                for query in queries {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let results = LauncherResult.search(apps, query: query)
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    checksum &+= results.count
                    samples.append(elapsed)
                }
            }
            samples.sort()
            print(String(format: "%@ apps=%d samples=%d p50_ms=%.6f p95_ms=%.6f max_ms=%.6f", label, apps.count, samples.count, samples[samples.count / 2], samples[Int(Double(samples.count) * 0.95)], samples.last!))
        }
        print("checksum=\(checksum)")
    }
}
