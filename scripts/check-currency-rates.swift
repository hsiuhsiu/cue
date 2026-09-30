import Combine
import CueCore
import Foundation

private final class RateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    private var stepAfterRead: TimeInterval = 0
    init(_ date: Date) { self.date = date }
    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        let result = date
        date = date.addingTimeInterval(stepAfterRead)
        stepAfterRead = 0
        return result
    }
    func advance(_ seconds: TimeInterval) { lock.lock(); date = date.addingTimeInterval(seconds); lock.unlock() }
    func advanceAfterNextRead(_ seconds: TimeInterval) { lock.lock(); stepAfterRead = seconds; lock.unlock() }
}

/// Suspended responses deliberately ignore cancellation to exercise the
/// controller's generation guard separately from URLSession cancellation.
private actor RateTransport {
    private var response: CurrencyRatesController.Response
    private var suspended = false
    private var error = false
    private var pending: [Int: CheckedContinuation<CurrencyRatesController.Response, Error>] = [:]
    private(set) var requests: [URLRequest] = []
    private(set) var cancellations = 0
    init(_ response: CurrencyRatesController.Response) { self.response = response }

    func configure(_ response: CurrencyRatesController.Response? = nil, suspended: Bool = false, error: Bool = false) {
        if let response { self.response = response }
        self.suspended = suspended
        self.error = error
    }
    func send(_ request: URLRequest) async throws -> CurrencyRatesController.Response {
        let id = requests.count
        requests.append(request)
        return try await withTaskCancellationHandler {
            if suspended {
                return try await withCheckedThrowingContinuation { pending[id] = $0 }
            }
            if error { throw URLError(.notConnectedToInternet) }
            return response
        } onCancel: {
            Task { await self.cancelled() }
        }
    }
    private func cancelled() { cancellations += 1 }
    func complete(_ id: Int, response: CurrencyRatesController.Response? = nil) {
        pending.removeValue(forKey: id)?.resume(returning: response ?? self.response)
    }
}

@main struct CheckCurrencyRates {
    @MainActor static var checks = 0
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor static func eventually(_ message: String, _ condition: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await condition() { check(true, message); return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(false, message)
    }

    static func payload(at date: Date, changes: [String: Any] = [:]) throws -> Data {
        var json: [String: Any] = [
            "result": "success", "base_code": "USD",
            "time_last_update_unix": date.addingTimeInterval(-60).timeIntervalSince1970,
            "time_next_update_unix": date.addingTimeInterval(3_600).timeIntervalSince1970,
            "rates": ["USD": 1, "TWD": 32.25, "EUR": 0.92],
            "provider": "https://www.exchangerate-api.com"
        ]
        json.merge(changes) { _, replacement in replacement }
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    static func response(at date: Date, changes: [String: Any] = [:], status: Int = 200,
                         url: URL = CurrencyRatesController.endpoint) throws -> CurrencyRatesController.Response {
        .init(data: try payload(at: date, changes: changes), statusCode: status, url: url)
    }

    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cue-currency-rates-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "com.yyhsiu.cue.tests.currency-rates.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        try await checkLifecycle(policy, directory: directory)
        try await checkInvalidDiskCache(policy, directory: directory)
        try await checkCancellation(policy)
        try await checkFailures(policy)
        try await checkValidation(policy)
        try await checkDecodeExpiry(policy)
        print("Currency rates passed: \(checks) checks; isolated transport, default-off gating, cancellation/generation, bounded validated data, private fresh cache, and retry limits. No live network or production preferences/cache.")
    }

    @MainActor static func checkLifecycle(_ policy: NetworkPolicy, directory: URL) async throws {
        policy.setAllowsNetwork(false)
        let clock = RateClock(date)
        let transport = RateTransport(try response(at: date))
        let file = directory.appendingPathComponent("private/rates.json")
        let controller = CurrencyRatesController(policy: policy, cacheFile: file, clock: clock.now,
                                                  transport: { try await transport.send($0) })
        defer { controller.stop() }
        var publications = 0
        controller.onChange = {
            publications += 1
            if controller.state == .loading { controller.setActive(true) }
        }
        check(controller.state == .idle && !controller.allowsNetwork, "Construction is idle with the source-build offline policy")
        controller.setActive(true)
        controller.retry()
        await Task.yield()
        check(await transport.requests.isEmpty && controller.state == .idle && !FileManager.default.fileExists(atPath: file.path),
              "An active query and retry cannot request or create a cache while networking is off")
        controller.setActive(false)
        policy.setAllowsNetwork(true)
        await Task.yield()
        check(await transport.requests.isEmpty && controller.state == .idle,
              "Enabling networking does not fetch in the background without an active currency query")
        controller.setActive(true)
        check(controller.state == .loading, "An explicit active query receives immediate progress feedback")
        for _ in 0..<200 { controller.setActive(true) }
        await eventually("One active request produces validated ready rates") {
            if case .ready = controller.state { return true }; return false
        }
        check(await transport.requests.count == 1, "Amount changes and reentrant loading callbacks do not start duplicate requests")
        guard case .ready(let rates) = controller.state else { fatalError("Missing ready rates") }
        check(rates.base == "USD" && rates.rates["USD"] == 1 && rates.rates["TWD"] == Decimal(string: "32.25"),
              "The table preserves decimal rates and required USD base metadata")
        let requests = await transport.requests
        check(requests.allSatisfy { $0.url == CurrencyRatesController.endpoint && $0.httpMethod == "GET"
              && $0.httpBody == nil && $0.url?.query == nil && !$0.httpShouldHandleCookies },
              "Every request is a fixed cookie-free USD GET with no amounts, expressions, or currency query")
        await eventually("Only validated rates are persisted asynchronously") { FileManager.default.fileExists(atPath: file.path) }
        let cachedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        check(Set(cachedJSON.keys) == Set(["base", "rates", "updatedAt", "nextUpdateAt"]),
              "The cache contains only rate metadata, never a raw feed or search history")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        check(permissions?.intValue == 0o600, "The persisted currency cache is private to its owner")
        let beforeChanges = publications
        var samples: [Double] = []
        for _ in 0..<1_000 {
            let start = DispatchTime.now().uptimeNanoseconds
            controller.setActive(true)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        samples.sort()
        let readyRequestCount = await transport.requests.count
        check(publications == beforeChanges && readyRequestCount == 1,
              "A ready table is reused without network work or repeated UI publications")
        print(String(format: "Fresh-rate active-query checks (1,000): p50 %.4f ms, p99 %.4f, max %.4f. Timestamp/cache control only; excludes conversion and visible rendering.", samples[499], samples[989], samples[999]))
        policy.setAllowsNetwork(false)
        check(controller.state == .idle && !controller.allowsNetwork,
              "Disabling networking synchronously removes visible rates even when the table is cached")
        policy.setAllowsNetwork(true)
        check(controller.state == .ready(rates), "Re-enabling an active query can reuse a still-fresh memory table")
        check(await transport.requests.count == 1, "An offline/online toggle does not refetch a fresh daily table")
        controller.stop()

        let disk = CurrencyRatesController(policy: policy, cacheFile: file, clock: clock.now,
                                           transport: { try await transport.send($0) })
        defer { disk.stop() }
        disk.setActive(true)
        await eventually("A fresh on-disk table loads asynchronously") { disk.state == .ready(rates) }
        check(await transport.requests.count == 1, "A fresh disk cache avoids an HTTP request")
        policy.setAllowsNetwork(false)
        check(disk.state == .idle, "Disk-cached results are also hidden immediately offline")
        disk.setActive(false)
        clock.advance(3_601)
        await transport.configure(try response(at: clock.now()), suspended: true)
        policy.setAllowsNetwork(true)
        disk.setActive(true)
        await eventually("An expired table triggers one refresh") { await transport.requests.count == 2 }
        check(disk.state == .loading, "An expired table is not shown as a current result while refreshing")
        await transport.complete(1)
        await eventually("Fresh replacement rates become ready") {
            if case .ready = disk.state { return true }; return false
        }
        disk.stop()
        disk.setActive(true)
        disk.retry()
        policy.setAllowsNetwork(false)
        policy.setAllowsNetwork(true)
        check(await transport.requests.count == 2 && disk.state == .idle, "Stopping permanently cancels observation and prevents future work")
    }

    @MainActor static func checkInvalidDiskCache(_ policy: NetworkPolicy, directory: URL) async throws {
        policy.setAllowsNetwork(true)
        let file = directory.appendingPathComponent("invalid-cache/rates.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stale: [String: Any] = [
            "base": "USD", "rates": ["USD": 1, "TWD": 32],
            "updatedAt": date.addingTimeInterval(-90_000).timeIntervalSince1970,
            "nextUpdateAt": date.addingTimeInterval(-1).timeIntervalSince1970
        ]
        for (name, bytes) in [("malformed", Data("broken local cache".utf8)),
                              ("stale", try JSONSerialization.data(withJSONObject: stale))] {
            try bytes.write(to: file, options: .atomic)
            let transport = RateTransport(try response(at: date))
            await transport.configure(error: true)
            let controller = CurrencyRatesController(policy: policy, cacheFile: file, clock: { date },
                                                      transport: { try await transport.send($0) })
            controller.setActive(true)
            await eventually("A \(name) disk cache attempts refresh and handles failure") { controller.state == .failed }
            check(await transport.requests.count == 1, "A \(name) disk cache cannot masquerade as current offline rates")
            check(try Data(contentsOf: file) == bytes, "Failed refresh never persists a malformed or stale replacement")
            controller.stop()
        }
    }

    @MainActor static func checkCancellation(_ policy: NetworkPolicy) async throws {
        policy.setAllowsNetwork(true)
        let clock = RateClock(date)
        let transport = RateTransport(try response(at: date))
        await transport.configure(suspended: true)
        let controller = CurrencyRatesController(policy: policy, cacheFile: nil, clock: clock.now,
                                                  transport: { try await transport.send($0) })
        defer { controller.stop() }
        controller.setActive(true)
        policy.setAllowsNetwork(false)
        await Task.yield()
        check(await transport.requests.isEmpty, "Disabling before the scheduled task runs prevents transport creation")
        policy.setAllowsNetwork(true)
        await eventually("An online active query starts a cancellable transfer") { await transport.requests.count == 1 }
        policy.setAllowsNetwork(false)
        check(controller.state == .idle, "OFF clears in-flight progress synchronously")
        await eventually("OFF cancels the active transport task") { await transport.cancellations == 1 }
        policy.setAllowsNetwork(true)
        await eventually("A later online invocation starts its own generation") { await transport.requests.count == 2 }
        let newer = try response(at: date, changes: ["rates": ["USD": 1, "TWD": 33]])
        await transport.complete(1, response: newer)
        await eventually("The latest generation publishes its own table") {
            if case .ready(let rates) = controller.state { return rates.rates["TWD"] == 33 }; return false
        }
        await transport.complete(0)
        try await Task.sleep(for: .milliseconds(20))
        if case .ready(let rates) = controller.state {
            check(rates.rates["TWD"] == 33, "A late response from the cancelled generation cannot replace newer rates")
        } else { check(false, "A stale completion must not alter ready state") }
        clock.advance(3_601)
        controller.setActive(true)
        await eventually("The next expired request begins") { await transport.requests.count == 3 }
        controller.setActive(false)
        check(controller.state == .idle, "Leaving currency input clears loading immediately")
        await eventually("Leaving currency input cancels its pending transfer") { await transport.cancellations == 2 }
        await transport.complete(2, response: try response(at: clock.now()))
        try await Task.sleep(for: .milliseconds(20))
        check(controller.state == .idle, "A late completion after leaving currency input stays hidden")
    }

    @MainActor static func checkFailures(_ policy: NetworkPolicy) async throws {
        policy.setAllowsNetwork(true)
        let clock = RateClock(date)
        let transport = RateTransport(try response(at: date))
        await transport.configure(error: true)
        let controller = CurrencyRatesController(policy: policy, cacheFile: nil, clock: clock.now,
                                                  transport: { try await transport.send($0) })
        defer { controller.stop() }
        controller.setActive(true)
        await eventually("Network errors become a retryable failed state") { controller.state == .failed }
        for _ in 0..<200 { controller.setActive(true); controller.retry() }
        check(await transport.requests.count == 1, "Fast typing and repeated retry cannot create a failure request storm")
        clock.advance(6)
        controller.setActive(true)
        check(await transport.requests.count == 1, "Automatic refresh respects its longer failure cooldown")
        await transport.configure(try response(at: clock.now()))
        controller.retry()
        await eventually("An explicit retry bypasses the automatic cooldown after its short safety floor") {
            if case .ready = controller.state { return true }; return false
        }
        check(await transport.requests.count == 2, "The explicit retry issues exactly one fresh request")
        controller.stop()

        let limitedTransport = RateTransport(try response(at: clock.now(), status: 429))
        let limited = CurrencyRatesController(policy: policy, cacheFile: nil, clock: clock.now,
                                               transport: { try await limitedTransport.send($0) })
        defer { limited.stop() }
        limited.setActive(true)
        await eventually("HTTP 429 becomes a failed state") { limited.state == .failed }
        clock.advance(301)
        limited.retry()
        limited.setActive(true)
        check(await limitedTransport.requests.count == 1, "The provider's 20-minute limit applies to both automatic and explicit retries")
        clock.advance(900)
        await limitedTransport.configure(try response(at: clock.now()))
        limited.retry()
        await eventually("Retry works once the rate-limit period has elapsed") {
            if case .ready = limited.state { return true }; return false
        }
    }

    @MainActor static func checkValidation(_ policy: NetworkPolicy) async throws {
        policy.setAllowsNetwork(true)
        let oversized = Data(repeating: 32, count: CurrencyRatesController.maximumResponseBytes + 1)
        let invalid: [(String, CurrencyRatesController.Response)] = [
            ("HTTP failure", try response(at: date, status: 500)),
            ("redirect", try response(at: date, status: 302)),
            ("unexpected origin", try response(at: date, url: URL(string: "https://example.test/rates")!)),
            ("provider error", try response(at: date, changes: ["result": "error"])),
            ("wrong base", try response(at: date, changes: ["base_code": "EUR"])),
            ("missing USD", try response(at: date, changes: ["rates": ["TWD": 32]])),
            ("wrong USD", try response(at: date, changes: ["rates": ["USD": 2, "TWD": 32]])),
            ("zero rate", try response(at: date, changes: ["rates": ["USD": 1, "TWD": 0]])),
            ("negative rate", try response(at: date, changes: ["rates": ["USD": 1, "TWD": -32]])),
            ("invalid currency code", try response(at: date, changes: ["rates": ["USD": 1, "Bad Code": 32]])),
            ("future observation", try response(at: date, changes: ["time_last_update_unix": date.addingTimeInterval(1).timeIntervalSince1970])),
            ("old observation", try response(at: date, changes: ["time_last_update_unix": date.addingTimeInterval(-172_801).timeIntervalSince1970])),
            ("expired update", try response(at: date, changes: ["time_next_update_unix": date.timeIntervalSince1970])),
            ("implausible interval", try response(at: date, changes: ["time_next_update_unix": date.addingTimeInterval(172_800).timeIntervalSince1970])),
            ("invalid JSON", .init(data: Data("not json".utf8), statusCode: 200, url: CurrencyRatesController.endpoint)),
            ("oversized data", .init(data: oversized, statusCode: 200, url: CurrencyRatesController.endpoint))
        ]
        for (name, response) in invalid {
            let transport = RateTransport(response)
            let controller = CurrencyRatesController(policy: policy, cacheFile: nil, clock: { date },
                                                      transport: { try await transport.send($0) })
            controller.setActive(true)
            await eventually("\(name) is rejected without producing a conversion table") { controller.state == .failed }
            check(await transport.requests.count == 1, "\(name) does not trigger an automatic retry loop")
            controller.stop()
        }
    }

    @MainActor static func checkDecodeExpiry(_ policy: NetworkPolicy) async throws {
        policy.setAllowsNetwork(true)
        let clock = RateClock(date)
        let response = try response(at: date, changes: ["time_next_update_unix": date.addingTimeInterval(1).timeIntervalSince1970])
        let transport = RateTransport(response)
        await transport.configure(suspended: true)
        let controller = CurrencyRatesController(policy: policy, cacheFile: nil, clock: clock.now,
                                                  transport: { try await transport.send($0) })
        defer { controller.stop() }
        controller.setActive(true)
        await eventually("The decode-expiry fixture starts") { await transport.requests.count == 1 }
        clock.advanceAfterNextRead(2)
        await transport.complete(0)
        await eventually("A table that expires during decode leaves loading and reports failure") { controller.state == .failed }
        clock.advance(6)
        await transport.configure(try self.response(at: clock.now()))
        controller.retry()
        await eventually("Decode-time expiry does not leave a completed task blocking retries") {
            if case .ready = controller.state { return true }; return false
        }
    }
}
