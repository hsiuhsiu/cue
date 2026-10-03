import Foundation
import CueCore
import Darwin

// The real model with synthetic applications, no AppKit drawing or user storage.
@MainActor final class AppIconCache { func invalidate() {} }

@main enum LongQueryBenchmark {
    @MainActor static func main() {
        let apps = (0..<1_000).map { index in
            IndexedApplication(name: "Synthetic Application \(index)",
                url: URL(fileURLWithPath: "/Synthetic/\(index).app"))
        }
        let model = LauncherModel(applications: apps)
        let fixtures = [
            ("268 KB prose", String(repeating: "Text for translation. ", count: 12_200)),
            ("1 MB prose", String(repeating: "Text for translation. ", count: 47_700)),
            ("1 MB whitespace", String(repeating: " ", count: 1_048_576)),
            ("1 MB combining marks", "a" + String(repeating: "\u{301}", count: 524_288)),
        ]
        for (name, query) in fixtures {
            var timings: [Double] = []
            var cpu: [Double] = []
            for _ in 0..<12 {
                model.reset()
                // Distinct text prevents both implementations' query cache from
                // disguising the cost of a new paste.
                let input = query + String(repeating: " ", count: timings.count)
                let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                let start = DispatchTime.now().uptimeNanoseconds
                model.setQuery(input)
                timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                cpu.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1_000_000)
                precondition(model.query == input)
            }
            timings.sort(); cpu.sort()
            print(String(format: "%@ (%d bytes): main-thread median %.3f ms, p95 %.3f ms, max %.3f ms; CPU median %.3f ms",
                name, query.utf8.count, timings[timings.count / 2], timings.last!, timings.last!, cpu[cpu.count / 2]))
        }
        model.reset()
    }
}
