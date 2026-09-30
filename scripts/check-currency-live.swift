import CueCore
import Foundation

private actor LiveRateDiagnostics {
    private(set) var requests = 0
    private(set) var status: Int?
    private(set) var transportError: String?

    func requestStarted() { requests += 1 }
    func received(_ status: Int) { self.status = status }
    func failed(_ error: Error) {
        let error = error as NSError
        transportError = "\(error.domain) code \(error.code)"
    }
}

/// Opt-in smoke test only. Default regression tests never use this transport.
@main struct CheckCurrencyLive {
    @MainActor static func main() async {
        let domain = "com.yyhsiu.cue.tests.currency-live.\(UUID())"
        guard let defaults = UserDefaults(suiteName: domain) else { fatalError("Cannot create isolated live-check preferences") }
        defer { defaults.removePersistentDomain(forName: domain) }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: true)
        policy.setAllowsNetwork(true)
        let diagnostics = LiveRateDiagnostics()
        let controller = CurrencyRatesController(policy: policy, cacheFile: nil, transport: { request in
            guard request.url == CurrencyRatesController.endpoint, request.httpMethod == "GET",
                  request.httpBody == nil, request.url?.query == nil else { throw URLError(.badURL) }
            await diagnostics.requestStarted()
            do {
                let response = try await CurrencyRatesController.fetch(request)
                await diagnostics.received(response.statusCode)
                return response
            } catch {
                await diagnostics.failed(error)
                throw error
            }
        })
        defer { controller.stop() }
        controller.setActive(true)
        for _ in 0..<250 {
            switch controller.state {
            case .ready(let snapshot):
                let now = Date()
                guard snapshot.base == "USD", snapshot.rates["USD"] == 1,
                      let twd = snapshot.rates["TWD"], twd > 0, !twd.isNaN,
                      snapshot.updatedAt <= now, snapshot.updatedAt >= now.addingTimeInterval(-172_800),
                      snapshot.nextUpdateAt > now, await diagnostics.requests == 1,
                      let query = ConversionQuery.parse("1 USD to TWD"),
                      let result = UnitConversion.convertCurrency(query, rates: snapshot).first,
                      result.targetID == "TWD" else {
                    print("FAIL: Live response did not satisfy fresh USD/TWD conversion checks.")
                    exit(1)
                }
                print("Rates timestamp: \(ISO8601DateFormatter().string(from: snapshot.updatedAt))")
                print("1 USD ≈ \(result.value) TWD (indicative)")
                return
            case .failed:
                if let error = await diagnostics.transportError {
                    print("FAIL: Live currency transport failed: \(error).")
                } else if let status = await diagnostics.status {
                    print("FAIL: Live currency response was rejected; HTTP status \(status).")
                } else {
                    print("FAIL: Live currency check failed before receiving an HTTP response.")
                }
                exit(1)
            case .idle, .loading:
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        controller.stop()
        print("FAIL: Live currency check exceeded its 25-second response deadline.")
        exit(1)
    }
}
