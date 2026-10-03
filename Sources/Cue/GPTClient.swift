import Combine
import CueCore
import Foundation

enum GPTClientError: Error, Equatable, Sendable {
    case networkDisabled, missingAPIKey, invalidInput, invalidModel
    case authentication, rateLimited, modelUnavailable, serviceUnavailable
    case invalidResponse, incomplete, refused, connection, keychain
}

enum GPTTransportEvent: Sendable {
    case response(statusCode: Int, url: URL, mimeType: String?)
    case data(Data)
}

struct GPTTransportStream: Sendable {
    let events: AsyncThrowingStream<GPTTransportEvent, Error>
    let cancel: @Sendable () -> Void
}

/// Explicit, one-shot requests only. Constructing this client never reads a key or starts networking.
@MainActor
final class GPTClient {
    typealias Transport = @Sendable (URLRequest) async throws -> GPTTransportStream
    nonisolated static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    nonisolated static let maximumResponseBytes = 1_048_576

    private let policy: NetworkPolicy
    private let keyReader: @Sendable () async throws -> String?
    private let transport: Transport
    private var observation: AnyCancellable?
    private var operation: Task<Void, Error>?
    private var generation = 0

    init(policy: NetworkPolicy,
         keyReader: @escaping @Sendable () async throws -> String? = GPTClient.readKey,
         transport: @escaping Transport = GPTClient.fetch) {
        self.policy = policy
        self.keyReader = keyReader
        self.transport = transport
        observation = policy.changes.sink { [weak self] allowed in
            if !allowed { MainActor.assumeIsolated { self?.cancel() } }
        }
    }

    func cancel() {
        generation += 1
        operation?.cancel()
        operation = nil
    }

    func stream(input: String, mode: GPTMode, configuration: GPTConfiguration,
                onDelta: @escaping @MainActor (String) -> Void) async throws {
        cancel()
        guard policy.allowsNetwork else { throw GPTClientError.networkDisabled }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.utf8.count <= GPTConfiguration.maximumInputBytes else { throw GPTClientError.invalidInput }
        guard GPTConfiguration.isValidModelID(configuration.model) else { throw GPTClientError.invalidModel }
        let requestID = generation
        let work = Task { [weak self, keyReader, transport] in
            try Task.checkCancellation()
            let key: String?
            do { key = try await keyReader() }
            catch {
                try Task.checkCancellation()
                throw GPTClientError.keychain
            }
            guard let self else { throw CancellationError() }
            try self.checkCurrent(requestID)
            guard let key, !key.isEmpty else { throw GPTClientError.missingAPIKey }
            let request = try Self.request(input: input, mode: mode, configuration: configuration, key: key)
            // No suspension between the authoritative gate and entering the cancellable transport.
            try self.checkCurrent(requestID)
            let stream = try await transport(request)
            defer { stream.cancel() }
            try self.checkCurrent(requestID)
            try await withTaskCancellationHandler {
                try await Self.consume(stream.events) { [weak self] delta in
                    guard let self else { throw CancellationError() }
                    try await self.deliver(delta, requestID: requestID, onDelta: onDelta)
                }
            } onCancel: { stream.cancel() }
            try self.checkCurrent(requestID)
        }
        operation = work
        do {
            try await withTaskCancellationHandler {
                try await work.value
                try Task.checkCancellation()
            } onCancel: { work.cancel() }
            if generation == requestID { operation = nil }
        } catch {
            if generation == requestID { operation = nil }
            if !policy.allowsNetwork { throw GPTClientError.networkDisabled }
            if Task.isCancelled || work.isCancelled || generation != requestID { throw CancellationError() }
            if let error = error as? GPTClientError { throw error }
            throw GPTClientError.connection
        }
    }

    private func checkCurrent(_ requestID: Int) throws {
        guard policy.allowsNetwork else { throw GPTClientError.networkDisabled }
        try Task.checkCancellation()
        guard generation == requestID else { throw CancellationError() }
    }

    private func deliver(_ delta: String, requestID: Int,
                         onDelta: @MainActor (String) -> Void) throws {
        try checkCurrent(requestID)
        onDelta(delta)
    }

    nonisolated private static func readKey() async throws -> String? {
        try await GPTKeychain.shared.read()
    }

    nonisolated static func request(input: String, mode: GPTMode, configuration: GPTConfiguration,
                                    key: String) throws -> URLRequest {
        // Reject header injection and accidentally pasted non-key content without logging it.
        guard !key.isEmpty, key.utf8.count <= 1_024,
              key.utf8.allSatisfy({ (33...126).contains($0) }) else { throw GPTClientError.authentication }
        struct Payload: Encodable {
            struct Reasoning: Encodable { let effort = "none" }
            let model: String
            let instructions: String
            let input: String
            let stream = true
            let store = false
            let max_output_tokens: Int
            let reasoning: Reasoning?
        }
        // Other model IDs stay configurable without sending unsupported reasoning parameters.
        let payload = Payload(model: configuration.model, instructions: configuration.instructions(for: mode),
                              input: input, max_output_tokens: mode == .answer ? 2_048 : 4_096,
                              reasoning: configuration.model == GPTConfiguration.defaultModel ? .init() : nil)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    nonisolated static func consume(_ events: AsyncThrowingStream<GPTTransportEvent, Error>,
                                     onDelta: @escaping @Sendable (String) async throws -> Void) async throws {
        var receivedHeader = false
        var parser = GPTEventParser()
        for try await event in events {
            try Task.checkCancellation()
            switch event {
            case let .response(statusCode, url, mimeType):
                guard !receivedHeader, url == endpoint else { throw GPTClientError.invalidResponse }
                try validateStatus(statusCode)
                guard mimeType?.lowercased() == "text/event-stream" else { throw GPTClientError.invalidResponse }
                receivedHeader = true
            case .data(let data):
                guard receivedHeader else { throw GPTClientError.invalidResponse }
                for delta in try parser.append(data) { try await onDelta(delta) }
                if parser.completed { return }
            }
        }
        try Task.checkCancellation()
        guard receivedHeader else { throw GPTClientError.invalidResponse }
        for delta in try parser.finish() { try await onDelta(delta) }
        guard parser.completed else { throw GPTClientError.incomplete }
    }

    nonisolated static func validateStatus(_ status: Int) throws {
        switch status {
        case 200: break
        case 401, 403: throw GPTClientError.authentication
        case 404: throw GPTClientError.modelUnavailable
        case 429: throw GPTClientError.rateLimited
        case 500...599: throw GPTClientError.serviceUnavailable
        case 400, 422: throw GPTClientError.invalidModel
        default: throw GPTClientError.invalidResponse
        }
    }

    nonisolated static func fetch(_ request: URLRequest) async throws -> GPTTransportStream {
        try Task.checkCancellation()
        let transfer = GPTTransfer()
        return try await withTaskCancellationHandler {
            let events = AsyncThrowingStream<GPTTransportEvent, Error> { continuation in
                continuation.onTermination = { @Sendable _ in transfer.cancel() }
                transfer.start(request, continuation: continuation)
            }
            if Task.isCancelled { transfer.cancel(); throw CancellationError() }
            return GPTTransportStream(events: events, cancel: { transfer.cancel() })
        } onCancel: { transfer.cancel() }
    }
}

/// Bounded SSE parsing outside the main actor. Bytes are decoded only after a full line arrives,
/// so arbitrary URLSession chunk boundaries cannot corrupt multi-byte characters.
struct GPTEventParser {
    private var buffer = Data()
    private var eventData = Data()
    private var byteCount = 0
    private var outputByteCount = 0
    private(set) var completed = false
    private static let maximumLineBytes = 262_144

    mutating func append(_ data: Data) throws -> [String] {
        guard !completed else { return [] }
        guard data.count <= GPTClient.maximumResponseBytes - byteCount else { throw GPTClientError.invalidResponse }
        byteCount += data.count
        buffer.append(data)
        var deltas: [String] = []
        var cursor = buffer.startIndex
        while let newline = buffer[cursor...].firstIndex(of: 10) {
            let lineEnd = newline > cursor && buffer[newline - 1] == 13 ? newline - 1 : newline
            guard lineEnd - cursor <= Self.maximumLineBytes else { throw GPTClientError.invalidResponse }
            try processLine(buffer[cursor..<lineEnd], deltas: &deltas)
            cursor = newline + 1
            if completed { break }
        }
        buffer.removeSubrange(buffer.startIndex..<cursor)
        guard buffer.count <= Self.maximumLineBytes else { throw GPTClientError.invalidResponse }
        return deltas
    }

    mutating func finish() throws -> [String] {
        guard !completed else { return [] }
        var deltas: [String] = []
        if !buffer.isEmpty {
            try processLine(buffer[...], deltas: &deltas)
            buffer = Data()
        }
        if !eventData.isEmpty { try dispatch(deltas: &deltas) }
        return deltas
    }

    private mutating func processLine(_ line: Data.SubSequence, deltas: inout [String]) throws {
        if line.isEmpty { try dispatch(deltas: &deltas); return }
        guard line.starts(with: [100, 97, 116, 97, 58]) else { return } // data:
        var value = line.dropFirst(5)
        if value.first == 32 { value = value.dropFirst() }
        guard value.count < Self.maximumLineBytes - eventData.count else { throw GPTClientError.invalidResponse }
        if !eventData.isEmpty { eventData.append(10) }
        eventData.append(contentsOf: value)
    }

    private mutating func dispatch(deltas: inout [String]) throws {
        guard !eventData.isEmpty else { return }
        defer { eventData = Data() }
        // Responses uses semantic completion, not Chat Completions' [DONE] marker.
        guard let object = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
              let type = object["type"] as? String else { throw GPTClientError.invalidResponse }
        switch type {
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String,
                  delta.utf8.count <= GPTConfiguration.maximumOutputBytes - outputByteCount else {
                throw GPTClientError.invalidResponse
            }
            outputByteCount += delta.utf8.count
            if !delta.isEmpty { deltas.append(delta) }
        case "response.completed":
            guard let response = object["response"] as? [String: Any],
                  response["status"] as? String == "completed", outputByteCount > 0 else {
                throw GPTClientError.invalidResponse
            }
            completed = true
        case "response.incomplete": throw GPTClientError.incomplete
        case "response.refusal.delta", "response.refusal.done": throw GPTClientError.refused
        case "response.failed", "error":
            let response = object["response"] as? [String: Any]
            let detail = (response?["error"] as? [String: Any]) ?? (object["error"] as? [String: Any]) ?? object
            switch detail["code"] as? String {
            case "rate_limit_exceeded", "insufficient_quota": throw GPTClientError.rateLimited
            case "invalid_api_key", "authentication_error": throw GPTClientError.authentication
            case "model_not_found": throw GPTClientError.modelUnavailable
            case "content_filter", "safety_violation": throw GPTClientError.refused
            default: throw GPTClientError.serviceUnavailable
            }
        default: break // Lifecycle, annotations, and optional metadata do not render content.
        }
    }
}

/// A serial delegate streams bounded chunks from an ephemeral session. No cookies, credential
/// storage, disk cache, redirects, automatic application retries, or request/response logging.
private final class GPTTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<GPTTransportEvent, Error>.Continuation?
    private var session: URLSession?
    private var finished = false
    private var byteCount = 0

    func start(_ request: URLRequest, continuation: AsyncThrowingStream<GPTTransportEvent, Error>.Continuation) {
        lock.lock()
        let finished = self.finished
        lock.unlock()
        guard !finished else { continuation.finish(throwing: CancellationError()); return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        lock.lock()
        guard !self.finished else {
            lock.unlock()
            session.invalidateAndCancel()
            continuation.finish(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        self.session = session
        lock.unlock()
        task.resume()
    }

    func cancel() { finish(CancellationError()) }

    private func finish(_ error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.finish(throwing: error)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse, let url = http.url,
                  url == GPTClient.endpoint,
                  http.expectedContentLength <= Int64(GPTClient.maximumResponseBytes) else {
                throw GPTClientError.invalidResponse
            }
            try GPTClient.validateStatus(http.statusCode)
            guard http.mimeType?.lowercased() == "text/event-stream" else { throw GPTClientError.invalidResponse }
            lock.lock()
            let continuation = self.continuation
            let finished = self.finished
            lock.unlock()
            continuation?.yield(.response(statusCode: http.statusCode, url: url, mimeType: http.mimeType))
            completionHandler(finished ? .cancel : .allow)
        } catch {
            completionHandler(.cancel)
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let excessive = data.count > GPTClient.maximumResponseBytes - byteCount
        if !excessive { byteCount += data.count }
        let continuation = self.continuation
        lock.unlock()
        if excessive { finish(GPTClientError.invalidResponse) }
        else { continuation?.yield(.data(data)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error)
    }
}
