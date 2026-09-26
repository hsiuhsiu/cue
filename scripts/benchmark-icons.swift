import AppKit
import CueCore
import Foundation

/// Standalone synchronous icon benchmark. This creates no windows and changes no app state.
/// Build/run through benchmark-icons.sh to keep generated files outside the app's build tree.
@main
enum IconBenchmark {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let all = SearchEngine.search(AppIndex.scan(), query: "")
        let limit = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? all.count
        let applications = Array(all.prefix(limit))
        let workspace = NSWorkspace.shared
        var cached: [String: NSImage] = [:]

        func milliseconds(_ operation: () -> Void) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }

        func summarize(_ name: String, _ samples: [Double]) -> [String: Any] {
            let sorted = samples.sorted()
            return [
                "phase": name,
                "count": samples.count,
                "total_ms": samples.reduce(0, +),
                "median_ms": sorted[sorted.count / 2],
                "p95_ms": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
                "max_ms": sorted.last!,
            ]
        }

        func rasterize(_ image: NSImage) {
            // A 32-point icon on a 2x display. Explicit rasterization includes lazy
            // representation selection and decode that icon(forFile:) can defer.
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }

        guard !applications.isEmpty else { fatalError("No applications found") }
        var reports: [[String: Any]] = []
        for phase in ["first-in-process", "warm-workspace"] {
            var retrieval: [Double] = []
            for application in applications {
                retrieval.append(milliseconds {
                    cached[application.id] = workspace.icon(forFile: application.url.path)
                })
            }
            reports.append(summarize("\(phase)-retrieve", retrieval))
            let drawing = applications.map { application in
                milliseconds {
                    autoreleasepool { rasterize(cached[application.id]!) }
                }
            }
            reports.append(summarize("\(phase)-rasterize", drawing))
        }

        // Prevent optimizing cached lookups away; report only this lookup path,
        // which intentionally excludes any rendering and is repeated for precision.
        var checksum = 0.0
        let cachedLookup = milliseconds {
            for _ in 0..<1000 {
                for application in applications {
                    checksum += cached[application.id]!.size.width
                }
            }
        }
        reports.append([
            "phase": "app-dictionary-hit", "count": applications.count * 1000,
            "total_ms": cachedLookup, "per_batch_ms": cachedLookup / 1000,
            "checksum": checksum,
        ])
        let output: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "indexed_applications": all.count,
            "measured_applications": applications.count,
            "raster_pixels": 64,
            "note": "First in this process only; filesystem and OS icon caches are not flushed. CPU work, not input-to-display latency.",
            "reports": reports,
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
