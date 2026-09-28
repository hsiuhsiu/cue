import Foundation
import CueCore
import Darwin

// Deliberately exclude AppKit icon construction, loading, and drawing from CPU
// timings. The actual LauncherModel is compiled unchanged alongside this file.
@MainActor
final class AppIconCache {
    func invalidate() {}
}

private struct Sample {
    let query: String
    let milliseconds: Double
    let threadCPUMilliseconds: Double
}

/// Contention from synthetic indexing and atomic file writes, never real user data.
private final class BackgroundWork: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private(set) var iterations = 0
    private let finished = DispatchSemaphore(value: 0)
    private let started = DispatchSemaphore(value: 0)
    private let file: URL

    init(directory: URL) {
        file = directory.appendingPathComponent("synthetic-background.json")
    }

    func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            let payload = Data(repeating: 65, count: 4 * 1_024 * 1_024)
            started.signal()
            while lock.withLock({ !stopped }) {
                let applications = AdaptiveSearchBenchmark.applications(count: 1_000)
                precondition(applications.count == 1_000)
                try? payload.write(to: file, options: .atomic)
                iterations += 1
            }
            finished.signal()
        }
        started.wait()
    }

    func stop() {
        lock.withLock { stopped = true }
        finished.wait()
    }
}

@main
enum AdaptiveSearchBenchmark {
    static let queries = [
        "s", "sa", "saf", "safa", "safari", "t", "te", "ter", "term", "terminal",
        "v", "vs", "vsc", "c", "co", "cod", "code", "trm", "sfr", "chrome",
        "mon", "index", "reindex", "更新", "備", "音樂", "cafe", "xyzzy",
        "developer utilities", "\t  CODE  ",
    ]

    static func applications(count: Int) -> [IndexedApplication] {
        let names = [
            "Safari", "Terminal", "Visual Studio Code", "Code Editor", "Activity Monitor",
            "Calendar", "System Settings", "Google Chrome", "Microsoft Excel", "Adobe Photoshop",
            "Café Editor", "備忘錄", "音樂", "更新工具", "Developer Utilities",
        ]
        return (0..<count).map { index in
            IndexedApplication(
                name: "\(names[index % names.count]) \(index)",
                url: URL(fileURLWithPath: "/SyntheticCueSearch/\(index).app"),
                bundleIdentifier: "invalid.cue.benchmark.app\(index)"
            )
        }
    }

    private static func measure(_ query: String, operation: () -> Int) -> (Sample, Int) {
        // CPU counters sit outside the wall interval. A slow wall sample with
        // ordinary thread CPU time points to scheduling/contention, not extra
        // synchronous work in the search implementation.
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let start = DispatchTime.now().uptimeNanoseconds
        let count = operation()
        let wallNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        let cpuNanoseconds = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart
        return (
            Sample(query: query, milliseconds: Double(wallNanoseconds) / 1_000_000,
                   threadCPUMilliseconds: Double(cpuNanoseconds) / 1_000_000),
            count
        )
    }

    private static func summary(_ samples: [Sample]) -> [String: Any] {
        let ordered = samples.sorted { $0.milliseconds < $1.milliseconds }
        func percentile(_ fraction: Double) -> Double {
            ordered[min(ordered.count - 1, max(0, Int(ceil(fraction * Double(ordered.count))) - 1))].milliseconds
        }
        return [
            "samples": samples.count,
            "p50_ms": percentile(0.50), "p95_ms": percentile(0.95),
            "p99_ms": percentile(0.99), "max_ms": ordered.last!.milliseconds,
            "slowest_query": ordered.last!.query,
            "slowest_thread_cpu_ms": ordered.last!.threadCPUMilliseconds,
        ]
    }

    private static func perQuery(_ samples: [Sample]) -> [String: Any] {
        Dictionary(grouping: samples, by: \.query).mapValues(summary)
    }

    #if ADAPTIVE_SEARCH
    private static func fullUsage(applications: [IndexedApplication]) -> SearchUsage {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var history = SearchUsage()
        let identifiers = (0..<SearchUsage.maximumResults).map { index in
            index < applications.count
                ? LauncherResult.application(applications[index]).id
                : "app:/SyntheticCueSearch/Absent\(index).app"
        }
        // Last benchmark query normalizes to "code", already present earlier.
        let distinctQueries = Array(queries.dropLast())
        for index in 0..<SearchUsage.maximumQueries {
            let query = index < distinctQueries.count ? distinctQueries[index] : "synthetic query \(index)"
            for offset in 0..<SearchUsage.maximumResultsPerQuery {
                history.record(
                    resultID: identifiers[(index * SearchUsage.maximumResultsPerQuery + offset) % identifiers.count],
                    query: query, at: now
                )
            }
        }
        precondition(history.resultCount == SearchUsage.maximumResults)
        precondition(history.queryCount == SearchUsage.maximumQueries)
        return history
    }
    #endif

    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueAdaptiveSearchBenchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checksum = 0
        var reports: [[String: Any]] = []
        for count in [500, 1_000] {
            let applications = applications(count: count)
            #if ADAPTIVE_SEARCH
            let history = fullUsage(applications: applications)
            let snapshotStart = DispatchTime.now().uptimeNanoseconds
            let maximumUsage = history.snapshot(at: Date(timeIntervalSince1970: 1_800_000_000))
            let snapshotMS = Double(DispatchTime.now().uptimeNanoseconds - snapshotStart) / 1_000_000
            let scenarios: [(String, SearchUsageSnapshot)] = [("empty", .empty), ("maximum", maximumUsage)]
            #else
            let scenarios = [("baseline", 0)]
            #endif
            for (scenario, usage) in scenarios {
                #if ADAPTIVE_SEARCH
                let search: (String) -> [LauncherResult] = { LauncherResult.search(applications, query: $0, usage: usage) }
                let createModel = { LauncherModel(applications: applications, usage: usage) }
                #else
                _ = usage
                let search: (String) -> [LauncherResult] = { LauncherResult.search(applications, query: $0) }
                let createModel = { LauncherModel(applications: applications) }
                #endif
                for background in [false, true] {
                    let work = background ? BackgroundWork(directory: directory) : nil
                    work?.start()
                    let first = measure("s") { search("s").count }
                    checksum &+= first.1
                    var coreSamples: [Sample] = []
                    for _ in 0..<100 {
                        for query in queries {
                            let result = measure(query) { search(query).count }
                            coreSamples.append(result.0)
                            checksum &+= result.1
                        }
                    }
                    var modelMisses: [Sample] = []
                    for _ in 0..<100 {
                        let model = createModel()
                        model.onChange = { [weak model] in checksum &+= model?.results.count ?? 0 }
                        for query in queries {
                            let result = measure(query) {
                                model.setQuery(query)
                                return model.results.count
                            }
                            modelMisses.append(result.0)
                            checksum &+= result.1
                        }
                    }
                    let cached = createModel()
                    for query in queries { cached.setQuery(query) }
                    cached.onChange = { [weak cached] in checksum &+= cached?.results.count ?? 0 }
                    var modelHits: [Sample] = []
                    for _ in 0..<100 {
                        for query in queries {
                            let result = measure(query) {
                                cached.setQuery(query)
                                return cached.results.count
                            }
                            modelHits.append(result.0)
                            checksum &+= result.1
                        }
                    }
                    work?.stop()
                    reports.append([
                        "applications": count, "usage": scenario, "background_work": background,
                        "background_iterations": work?.iterations ?? 0,
                        "first_core_query_ms": first.0.milliseconds,
                        "core_uncached": summary(coreSamples),
                        "core_by_query": perQuery(coreSamples),
                        "model_cache_miss": summary(modelMisses),
                        "model_cache_hit": summary(modelHits),
                    ])
                }
            }
            #if ADAPTIVE_SEARCH
            // Replace a model-owned maximum snapshot so the timed adoption also
            // includes releasing the old score dictionaries and cached results.
            var adoptionSamples: [Sample] = []
            for _ in 0..<100 {
                let model = LauncherModel(applications: applications, usage: history.snapshot(at: Date(timeIntervalSince1970: 1_800_000_000)))
                for query in queries { model.setQuery(query) }
                model.updateUsage(history.snapshot(at: Date(timeIntervalSince1970: 1_800_000_001)))
                let sample = measure("s") {
                    model.setQuery("s")
                    return model.results.count
                }
                adoptionSamples.append(sample.0)
                checksum &+= sample.1
            }
            reports.append(["applications": count, "maximum_usage_snapshot_ms": snapshotMS,
                            "usage_results": history.resultCount, "usage_queries": history.queryCount,
                            "usage_results_per_query": SearchUsage.maximumResultsPerQuery,
                            "model_snapshot_adoption": summary(adoptionSamples)])
            #endif
        }
        #if ADAPTIVE_SEARCH
        let mode = "adaptive"
        #else
        let mode = "baseline"
        #endif
        let report: [String: Any] = [
            "mode": mode,
            "build": "swiftc -O, Swift 6, native architecture",
            "index": "deterministic synthetic applications only",
            "timing_scope": "Core search and synchronous LauncherModel.setQuery, no input event delivery, icon work, drawing, activation or app launch",
            "reports": reports, "checksum": checksum,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
