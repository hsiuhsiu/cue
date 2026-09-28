import Foundation

/// Developer-only reference/corpus runner; no GUI, clipboard or network access.
@main
struct VerifyChineseConversion {
    static func main() throws {
        let started = ContinuousClock.now
        let converter = try ChineseConverter(resourceURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let loaded = ContinuousClock.now
        if CommandLine.arguments[2] == "--benchmark" {
            let short = "软件开发使用鼠标、打印机、内存和数据库。头发发展，干燥干杯干活。"
            let long = String(repeating: short, count: 1_000)
            for text in [short, long] {
                var samples: [Double] = []
                var bytes = 0
                for _ in 0..<100 {
                    let start = ContinuousClock.now
                    bytes += try converter.convert(text, to: .traditionalTaiwan).utf8.count
                    let duration = start.duration(to: .now).components
                    samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
                }
                samples.sort()
                print("input=\(text.utf8.count) bytes, median=\(samples[50]) ms, p95=\(samples[95]) ms, checksum=\(bytes)")
            }
            print("cold converter construction: \(started.duration(to: loaded))")
            return
        }
        let target = ChineseConversionTarget(rawValue: CommandLine.arguments[2])!
        let input = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
        let output = try input.components(separatedBy: "\n").map { try converter.convert($0, to: target) }.joined(separator: "\n")
        try output.write(toFile: CommandLine.arguments[4], atomically: true, encoding: .utf8)
        print("Converted \(input.utf8.count) input bytes; construction \(started.duration(to: loaded)); total \(started.duration(to: .now))")
    }
}
