import Combine
import CueCore
import Foundation

/// One public daily USD table. Amounts and search text never enter this request.
@MainActor
final class CurrencyRatesController {
    enum State: Equatable {
        case idle, loading, ready(CurrencyRateSnapshot), failed
    }

    struct Response: Sendable {
        let data: Data
        let statusCode: Int
        let url: URL
    }

    typealias Transport = @Sendable (URLRequest) async throws -> Response
    nonisolated static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!
    nonisolated static let maximumResponseBytes = 256 * 1_024
    nonisolated static let defaultCacheFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.yyhsiu.cue/Currency/rates.json")

    private(set) var state: State = .idle
    var onChange: (() -> Void)?
    var allowsNetwork: Bool { policy.allowsNetwork }

    private let policy: NetworkPolicy
    private let cache: CurrencyRateCache
    private let clock: @Sendable () -> Date
    private let transport: Transport
    private var observation: AnyCancellable?
    private var task: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var generation = 0
    private var active = false
    private var stopped = false
    private var didReadCache = false
    private var cached: CurrencyRateSnapshot?
    private var automaticRetryAt: Date?
    private var explicitRetryAt: Date?

    init(policy: NetworkPolicy, cacheFile: URL? = defaultCacheFile,
         clock: @escaping @Sendable () -> Date = { Date() },
         transport: @escaping Transport = CurrencyRatesController.fetch) {
        self.policy = policy
        self.cache = CurrencyRateCache(file: cacheFile)
        self.clock = clock
        self.transport = transport
        observation = policy.changes.sink { [weak self] _ in
            // NetworkPolicy sends synchronously from its main-actor setter.
            MainActor.assumeIsolated { self?.policyChanged() }
        }
    }

    func setActive(_ active: Bool) {
        guard !stopped else { return }
        self.active = active
        if active { begin() }
        else { cancel(); publish(.idle) }
    }

    func retry() {
        guard !stopped, active, allowsNetwork, task == nil,
              explicitRetryAt.map({ clock() >= $0 }) ?? true else { return }
        begin(explicit: true)
    }

    func stop() {
        stopped = true
        active = false
        observation?.cancel()
        observation = nil
        cancel()
        publish(.idle)
    }

    private func policyChanged() {
        if !allowsNetwork {
            cancel()
            let wasIdle = state == .idle
            publish(.idle)
            // A complete query may already be idle because networking was off.
            if wasIdle { onChange?() }
        } else if active {
            begin()
        } else {
            onChange?()
        }
    }

    private func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        expiryTask?.cancel()
        expiryTask = nil
    }

    private func publish(_ value: State) {
        guard value != state else { return }
        state = value
        onChange?()
    }

    private func isCurrent(_ request: Int) -> Bool {
        !stopped && active && allowsNetwork && generation == request
    }

    private func begin(explicit: Bool = false) {
        guard !stopped, active, allowsNetwork, task == nil else { return }
        let now = clock()
        if !explicit, let cached, CurrencyRateData.isFresh(cached, at: now) {
            if case .ready = state {} else { publish(.ready(cached)) }
            scheduleExpiry(cached)
            return
        }
        if !explicit, let automaticRetryAt, now < automaticRetryAt {
            publish(.failed)
            return
        }
        expiryTask?.cancel()
        expiryTask = nil
        generation += 1
        let requestID = generation
        let readCache = !didReadCache && !explicit
        task = Task { [weak self, cache, clock, transport] in
            if readCache {
                let saved = await cache.load(at: clock())
                guard !Task.isCancelled, let self, self.isCurrent(requestID) else { return }
                self.didReadCache = true
                if let saved, CurrencyRateData.isFresh(saved, at: clock()) {
                    self.cached = saved
                    self.task = nil
                    self.publish(.ready(saved))
                    self.scheduleExpiry(saved)
                    return
                }
            }
            guard !Task.isCancelled, let self, self.isCurrent(requestID) else { return }
            // There is no await between the authoritative gate and entering the
            // cancellable transport. URLSession receives task cancellation too.
            var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                     timeoutInterval: 15)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpShouldHandleCookies = false
            self.explicitRetryAt = clock().addingTimeInterval(5)
            do {
                try Task.checkCancellation()
                let response = try await transport(request)
                try Task.checkCancellation()
                let receivedAt = clock()
                let snapshot = try await Task.detached(priority: .utility) {
                    try CurrencyRateData.decode(response, at: receivedAt)
                }.value
                guard !Task.isCancelled, self.isCurrent(requestID) else { return }
                guard CurrencyRateData.isFresh(snapshot, at: clock()) else { throw CurrencyRateData.Failure.invalid }
                self.cached = snapshot
                self.task = nil
                self.automaticRetryAt = nil
                self.publish(.ready(snapshot))
                self.scheduleExpiry(snapshot)
                await cache.save(snapshot)
            } catch {
                guard !Task.isCancelled, self.isCurrent(requestID) else { return }
                self.task = nil
                let now = clock()
                let limited = (error as? CurrencyRateData.Failure) == .rateLimited
                self.automaticRetryAt = now.addingTimeInterval(limited ? 1_200 : 300)
                self.explicitRetryAt = now.addingTimeInterval(limited ? 1_200 : 5)
                self.publish(.failed)
            }
        }
        publish(.loading)
    }

    private func scheduleExpiry(_ snapshot: CurrencyRateSnapshot) {
        guard expiryTask == nil, active, allowsNetwork else { return }
        let delay = max(0, min(snapshot.nextUpdateAt.timeIntervalSince(clock()), 172_800))
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.expiryTask = nil
            self.begin()
        }
    }

    nonisolated static func fetch(_ request: URLRequest) async throws -> Response {
        try Task.checkCancellation()
        let transfer = CurrencyRateTransfer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { transfer.start(request, continuation: $0) }
        } onCancel: {
            transfer.cancel()
        }
    }
}

/// Shared response/cache validation happens on workers, never while typing.
private enum CurrencyRateData {
    enum Failure: Error, Equatable { case invalid, rateLimited }
    private struct Feed: Decodable {
        let result: String
        let base_code: String
        let rates: [String: Decimal]
        let time_last_update_unix: Double
        let time_next_update_unix: Double
    }

    struct Saved: Codable {
        let base: String
        let rates: [String: Decimal]
        let updatedAt: Date
        let nextUpdateAt: Date

        init(_ snapshot: CurrencyRateSnapshot) {
            base = snapshot.base
            rates = snapshot.rates
            updatedAt = snapshot.updatedAt
            nextUpdateAt = snapshot.nextUpdateAt
        }

        var snapshot: CurrencyRateSnapshot {
            CurrencyRateSnapshot(base: base, rates: rates, updatedAt: updatedAt, nextUpdateAt: nextUpdateAt)
        }
    }

    static func decode(_ response: CurrencyRatesController.Response, at now: Date) throws -> CurrencyRateSnapshot {
        guard response.url == CurrencyRatesController.endpoint else { throw Failure.invalid }
        if response.statusCode == 429 { throw Failure.rateLimited }
        guard response.statusCode == 200, response.data.count <= CurrencyRatesController.maximumResponseBytes else {
            throw Failure.invalid
        }
        let feed = try JSONDecoder().decode(Feed.self, from: response.data)
        guard feed.result == "success", feed.time_last_update_unix.isFinite, feed.time_next_update_unix.isFinite else {
            throw Failure.invalid
        }
        let snapshot = CurrencyRateSnapshot(base: feed.base_code, rates: feed.rates,
                                            updatedAt: Date(timeIntervalSince1970: feed.time_last_update_unix),
                                            nextUpdateAt: Date(timeIntervalSince1970: feed.time_next_update_unix))
        guard validate(snapshot, at: now) else { throw Failure.invalid }
        return snapshot
    }

    static func isFresh(_ snapshot: CurrencyRateSnapshot, at now: Date) -> Bool {
        snapshot.updatedAt <= now && snapshot.updatedAt >= now.addingTimeInterval(-172_800)
            && snapshot.nextUpdateAt > now && snapshot.nextUpdateAt <= snapshot.updatedAt.addingTimeInterval(172_800)
    }

    static func validate(_ snapshot: CurrencyRateSnapshot, at now: Date) -> Bool {
        guard snapshot.base == "USD", snapshot.rates["USD"] == 1,
              !snapshot.rates.isEmpty, snapshot.rates.count <= 512, isFresh(snapshot, at: now) else { return false }
        return snapshot.rates.allSatisfy { code, rate in
            code.utf8.count == 3 && code.utf8.allSatisfy { (65...90).contains($0) }
                && !rate.isNaN && rate > 0 && NSDecimalNumber(decimal: rate).doubleValue.isFinite
        }
    }
}

private actor CurrencyRateCache {
    private let file: URL?
    init(file: URL?) { self.file = file }

    func load(at now: Date) -> CurrencyRateSnapshot? {
        guard let file else { return nil }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  size.intValue <= CurrencyRatesController.maximumResponseBytes else { return nil }
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= CurrencyRatesController.maximumResponseBytes else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let saved = try decoder.decode(CurrencyRateData.Saved.self, from: bytes)
            return CurrencyRateData.validate(saved.snapshot, at: now) ? saved.snapshot : nil
        } catch { return nil }
    }

    func save(_ snapshot: CurrencyRateSnapshot) {
        guard let file else { return }
        do {
            let parent = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let bytes = try encoder.encode(CurrencyRateData.Saved(snapshot))
            guard bytes.count <= CurrencyRatesController.maximumResponseBytes else { return }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { /* A read-only/full cache cannot prevent an in-memory conversion. */ }
    }
}

/// A bounded ephemeral transfer. Reject redirects and stop reading at 256 KiB
/// rather than buffering an unbounded response before validation.
private final class CurrencyRateTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CurrencyRatesController.Response, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var finished = false

    func start(_ request: URLRequest, continuation: CheckedContinuation<CurrencyRatesController.Response, Error>) {
        lock.lock()
        let alreadyFinished = finished
        lock.unlock()
        guard !alreadyFinished else { continuation.resume(throwing: CancellationError()); return }
        // Session construction stays outside the lock: cancelling from the main
        // actor must never wait for Foundation to initialize its networking stack.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        lock.lock()
        guard !finished else {
            lock.unlock()
            session.invalidateAndCancel()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<CurrencyRatesController.Response, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        data = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == CurrencyRatesController.endpoint,
              response.expectedContentLength <= Int64(CurrencyRatesController.maximumResponseBytes) else {
            completionHandler(.cancel)
            finish(.failure(CurrencyRateData.Failure.invalid))
            return
        }
        lock.lock()
        self.response = http
        let finished = self.finished
        lock.unlock()
        completionHandler(finished ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let excessive = data.count > CurrencyRatesController.maximumResponseBytes - self.data.count
        if !excessive { self.data.append(data) }
        lock.unlock()
        if excessive { finish(.failure(CurrencyRateData.Failure.invalid)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let response = self.response
        let data = self.data
        lock.unlock()
        guard let response, let url = response.url else { finish(.failure(CurrencyRateData.Failure.invalid)); return }
        finish(.success(.init(data: data, statusCode: response.statusCode, url: url)))
    }
}
