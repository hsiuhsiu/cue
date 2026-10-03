import CueCore
import Foundation

private actor Signal {
    private var sent = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func send() { sent = true; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
    func wait() async {
        if sent { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@main
struct CheckGPT {
    @MainActor private static var checks = 0
    @MainActor private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: \(message)") }
        checks += 1
    }

    private static func data(_ type: String, _ fields: [String: Any] = [:]) -> Data {
        var event = fields
        event["type"] = type
        let json = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        return Data("event: \(type)\r\ndata: ".utf8) + json + Data("\r\n\r\n".utf8)
    }
    private static var complete: Data { data("response.completed", ["response": ["status": "completed"]]) }
    private static func response(_ chunks: [Data], status: Int = 200,
                                 url: URL = GPTClient.endpoint, mime: String? = "text/event-stream") -> GPTTransportStream {
        let events = AsyncThrowingStream<GPTTransportEvent, Error> { continuation in
            continuation.yield(.response(statusCode: status, url: url, mimeType: mime))
            for chunk in chunks { continuation.yield(.data(chunk)) }
            continuation.finish()
        }
        return .init(events: events, cancel: {})
    }
    @MainActor private static func failure(_ expected: GPTClientError, _ label: String,
                                          work: () async throws -> Void) async {
        do { try await work(); fatalError("FAIL: \(label) unexpectedly succeeded") }
        catch { check(error as? GPTClientError == expected, "\(label): wrong sanitized error") }
    }
    @MainActor private static func parserFailure(_ expected: GPTClientError, _ bytes: Data, _ label: String) {
        do { var parser = GPTEventParser(); _ = try parser.append(bytes); fatalError("FAIL: \(label)") }
        catch { check(error as? GPTClientError == expected, label) }
    }

    @MainActor static func main() async throws {
        let defaultsName = "CueGPTCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let policy = NetworkPolicy(defaults: defaults, defaultAllowsNetwork: false)
        let keyReads = Counter()
        let requests = Counter()
        let client = GPTClient(policy: policy, keyReader: { keyReads.increment(); return "test-key" }, transport: { _ in
            requests.increment()
            return response([data("response.output_text.delta", ["delta": "你好 👋"]), complete])
        })
        check(keyReads.value == 0 && requests.value == 0, "constructing client is entirely idle")
        await failure(.networkDisabled, "disabled request") {
            try await client.stream(input: "hello", mode: .answer, configuration: .init()) { _ in }
        }
        check(keyReads.value == 0 && requests.value == 0, "disabled startup does not even read Keychain")
        policy.setAllowsNetwork(true)
        var result = ""
        try await client.stream(input: "hello", mode: .answer, configuration: .init()) { result += $0 }
        check(result == "你好 👋", "streamed Unicode text")
        check(requests.value == 1 && keyReads.value == 1, "explicit action makes exactly one request")

        for invalid in ["", " \n", String(repeating: "x", count: GPTConfiguration.maximumInputBytes + 1),
                        String(repeating: "字", count: GPTConfiguration.maximumInputBytes / 3 + 1)] {
            await failure(.invalidInput, "invalid input") {
                try await client.stream(input: invalid, mode: .answer, configuration: .init()) { _ in }
            }
        }
        await failure(.invalidModel, "invalid model") {
            try await client.stream(input: "hello", mode: .answer, configuration: .init(model: "oops\nheader")) { _ in }
        }
        check(requests.value == 1 && keyReads.value == 1, "invalid requests never read Keychain or start transport")

        let payloadRequest = try GPTClient.request(input: "你好", mode: .answer, configuration: .init(), key: "test-key")
        let payload = try JSONSerialization.jsonObject(with: payloadRequest.httpBody!) as! [String: Any]
        check(payloadRequest.url == GPTClient.endpoint && payloadRequest.httpMethod == "POST", "fixed HTTPS endpoint")
        check(payloadRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "key only in header")
        check(payloadRequest.value(forHTTPHeaderField: "Accept") == "text/event-stream", "stream Accept header")
        check(payload["input"] as? String == "你好", "input preserved")
        check(payload["model"] as? String == GPTConfiguration.defaultModel, "recommended model")
        check(payload["store"] as? Bool == false && payload["stream"] as? Bool == true, "stateless streaming")
        check((payload["reasoning"] as? [String: String])?["effort"] == "none", "Luna none reasoning")
        check(payload["max_output_tokens"] as? Int == 2_048, "answer token cap")
        check(payload["tools"] == nil && payload["previous_response_id"] == nil, "no browsing or conversation history")
        check(!payloadRequest.httpShouldHandleCookies && payloadRequest.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData,
              "request disables cookies and caching")
        let custom = try GPTClient.request(input: "hello", mode: .translate,
                                           configuration: .init(model: "custom-model"), key: "test-key")
        let customPayload = try JSONSerialization.jsonObject(with: custom.httpBody!) as! [String: Any]
        check(customPayload["reasoning"] == nil, "custom model does not inherit unsupported reasoning options")
        check(customPayload["max_output_tokens"] as? Int == 4_096, "translation token cap")
        check((customPayload["instructions"] as? String)?.contains("predominantly Chinese") == true, "automatic translation prompt")
        for badKey in ["", "abc\r\nInjected: yes", "a b", "🔑", String(repeating: "a", count: 1_025)] {
            do { _ = try GPTClient.request(input: "hi", mode: .answer, configuration: .init(), key: badKey)
                fatalError("FAIL: key header validation") }
            catch { check(error as? GPTClientError == .authentication, "key header injection rejected") }
        }

        // Every byte boundary, including inside emoji and CRLF separators.
        let wire = Data(": keepalive\r\n\r\n".utf8) + data("response.created")
            + data("response.output_text.delta", ["delta": "正體中文👩‍💻"])
            + data("response.output_text.delta", ["delta": "\nsecond line"])
            + complete
        for split in 0...wire.count {
            var parser = GPTEventParser()
            let first = try parser.append(Data(wire.prefix(split)))
            let last = try parser.append(Data(wire.dropFirst(split)))
            check((first + last).joined() == "正體中文👩‍💻\nsecond line" && parser.completed,
                  "UTF-8 split \(split)")
        }
        var byteParser = GPTEventParser()
        var byteResult = ""
        for byte in wire { byteResult += try byteParser.append(Data([byte])).joined() }
        check(byteResult == "正體中文👩‍💻\nsecond line" && byteParser.completed, "single-byte delivery")
        var multiline = GPTEventParser()
        let multilineData = Data("data: {\"type\":\"response.output_text.delta\",\ndata: \"delta\":\"ok\"}\n\n".utf8)
        let multilineResult = try multiline.append(multilineData)
        check(multilineResult == ["ok"], "multiline SSE data")
        var noFinalNewline = GPTEventParser()
        _ = try noFinalNewline.append(data("response.output_text.delta", ["delta": "ok"]))
        _ = try noFinalNewline.append(Data(complete.dropLast(4)))
        _ = try noFinalNewline.finish()
        check(noFinalNewline.completed, "EOF dispatches final event")
        parserFailure(.invalidResponse, Data("data: not-json\n\n".utf8), "malformed JSON")
        parserFailure(.invalidResponse, Data("data: [DONE]\n\n".utf8), "Chat Completions marker cannot fake success")
        parserFailure(.invalidResponse, complete, "empty completion rejected")
        parserFailure(.invalidResponse, data("response.output_text.delta"), "missing delta rejected")
        parserFailure(.invalidResponse, Data(repeating: 65, count: 262_145), "line bound")
        parserFailure(.invalidResponse, Data(repeating: 65, count: GPTClient.maximumResponseBytes + 1), "wire byte bound")
        parserFailure(.invalidResponse, data("response.output_text.delta", ["delta": String(repeating: "a", count: GPTConfiguration.maximumOutputBytes + 1)]), "output byte bound")
        parserFailure(.refused, data("response.refusal.delta", ["delta": "do not expose raw refusal"]), "refusal sanitized")
        parserFailure(.incomplete, data("response.incomplete"), "incomplete surfaced")
        parserFailure(.rateLimited, data("error", ["code": "insufficient_quota", "message": "private details"]), "quota sanitized")
        parserFailure(.authentication, data("response.failed", ["response": ["error": ["code": "invalid_api_key"]]]), "failure sanitized")

        for (status, error) in [(401, GPTClientError.authentication), (403, .authentication), (404, .modelUnavailable),
                                (429, .rateLimited), (500, .serviceUnavailable), (502, .serviceUnavailable),
                                (400, .invalidModel), (301, .invalidResponse)] {
            let failed = GPTClient(policy: policy, keyReader: { "test-key" }, transport: { _ in response([], status: status) })
            await failure(error, "HTTP \(status)") {
                try await failed.stream(input: "hello", mode: .answer, configuration: .init()) { _ in }
            }
        }
        let missing = GPTClient(policy: policy, keyReader: { nil }, transport: { _ in requests.increment(); return response([]) })
        await failure(.missingAPIKey, "missing key") { try await missing.stream(input: "hi", mode: .answer, configuration: .init()) { _ in } }
        let locked = GPTClient(policy: policy, keyReader: { throw NSError(domain: "sensitive", code: 1) })
        await failure(.keychain, "Keychain failure") { try await locked.stream(input: "hi", mode: .answer, configuration: .init()) { _ in } }
        check(requests.value == 1, "credential failures send nothing")

        let dropped = GPTClient(policy: policy, keyReader: { "test-key" }, transport: { _ in
            response([data("response.output_text.delta", ["delta": "partial"])])
        })
        await failure(.incomplete, "truncated stream") {
            try await dropped.stream(input: "hi", mode: .answer, configuration: .init()) { _ in }
        }
        for stream in [response([], url: URL(string: "https://example.com/redirect")!), response([], mime: "text/html")] {
            let invalid = GPTClient(policy: policy, keyReader: { "test-key" }, transport: { _ in stream })
            await failure(.invalidResponse, "redirect/non-SSE") {
                try await invalid.stream(input: "hi", mode: .answer, configuration: .init()) { _ in }
            }
        }

        // Turning networking off while Keychain is pending must never send later.
        let keyStarted = Signal(), keyRelease = Signal()
        let keyRaceRequests = Counter()
        let keyRace = GPTClient(policy: policy, keyReader: {
            await keyStarted.send(); await keyRelease.wait(); return "test-key"
        }, transport: { _ in keyRaceRequests.increment(); return response([]) })
        let pendingKey = Task { try await keyRace.stream(input: "hi", mode: .answer, configuration: .init()) { _ in } }
        await keyStarted.wait()
        policy.setAllowsNetwork(false)
        await keyRelease.send()
        await failure(.networkDisabled, "disable during Keychain wait") { try await pendingKey.value }
        check(keyRaceRequests.value == 0, "post-Keychain policy check prevents request")
        policy.setAllowsNetwork(true)
        check(keyRaceRequests.value == 0, "enabling network does not auto-retry")

        // Cancel an active stream. A late event cannot publish even if transport ignores cancellation.
        let transportStarted = Signal(), receivedFirst = Signal()
        let cancellations = Counter()
        let pair = AsyncThrowingStream<GPTTransportEvent, Error>.makeStream()
        let streaming = GPTClient(policy: policy, keyReader: { "test-key" }, transport: { _ in
            await transportStarted.send()
            return .init(events: pair.stream, cancel: { cancellations.increment() })
        })
        var visible = ""
        let active = Task { try await streaming.stream(input: "hi", mode: .answer, configuration: .init()) { delta in
            visible += delta
            Task { await receivedFirst.send() }
        } }
        await transportStarted.wait()
        pair.continuation.yield(.response(statusCode: 200, url: GPTClient.endpoint, mimeType: "text/event-stream"))
        pair.continuation.yield(.data(data("response.output_text.delta", ["delta": "first"])))
        await receivedFirst.wait()
        check(visible == "first", "output appears before completion")
        policy.setAllowsNetwork(false)
        pair.continuation.yield(.data(data("response.output_text.delta", ["delta": "late"])))
        pair.continuation.yield(.data(complete))
        pair.continuation.finish()
        await failure(.networkDisabled, "disable active stream") { try await active.value }
        check(visible == "first" && cancellations.value > 0, "disable cancels transport and blocks late output")
        policy.setAllowsNetwork(true)

        let stopStarted = Signal()
        let stopPair = AsyncThrowingStream<GPTTransportEvent, Error>.makeStream()
        let stopCancels = Counter()
        let stoppable = GPTClient(policy: policy, keyReader: { "test-key" }, transport: { _ in
            await stopStarted.send()
            return .init(events: stopPair.stream, cancel: { stopCancels.increment(); stopPair.continuation.finish() })
        })
        let stopped = Task { try await stoppable.stream(input: "hi", mode: .answer, configuration: .init()) { _ in } }
        await stopStarted.wait()
        stoppable.cancel()
        do { try await stopped.value; fatalError("FAIL: Stop") }
        catch { check(error is CancellationError, "Stop uses cancellation, not a failure alert") }
        check(stopCancels.value > 0, "Stop cancels underlying transport")

        // A slow, uncooperative older transport must not overwrite a newer invocation.
        let oldStarted = Signal(), oldRelease = Signal()
        let calls = Counter(), oldCancelled = Counter()
        let oldPair = AsyncThrowingStream<GPTTransportEvent, Error>.makeStream()
        oldPair.continuation.yield(.response(statusCode: 200, url: GPTClient.endpoint, mimeType: "text/event-stream"))
        oldPair.continuation.yield(.data(data("response.output_text.delta", ["delta": "old"])))
        oldPair.continuation.yield(.data(complete))
        oldPair.continuation.finish()
        let superseding = GPTClient(policy: policy, keyReader: { "test-key" }, transport: { _ in
            calls.increment()
            if calls.value == 1 {
                await oldStarted.send(); await oldRelease.wait()
                return .init(events: oldPair.stream, cancel: { oldCancelled.increment() })
            }
            return response([data("response.output_text.delta", ["delta": "new"]), complete])
        })
        var latest = ""
        let old = Task { try await superseding.stream(input: "old question", mode: .answer, configuration: .init()) { latest += $0 } }
        await oldStarted.wait()
        try await superseding.stream(input: "new question", mode: .answer, configuration: .init()) { latest += $0 }
        await oldRelease.send()
        do { try await old.value; fatalError("FAIL: superseded request") }
        catch { check(error is CancellationError, "superseded request is cancelled") }
        check(latest == "new" && oldCancelled.value > 0, "late transport cannot overwrite new output and is released")
        print("PASS: \(checks) GPT checks (requests, streaming, bounds, errors, cancellation, offline transitions)")
    }
}
