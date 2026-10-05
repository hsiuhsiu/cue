import CoreServices
import CueCore
import Foundation

private final class FakeFileSearchBackend: FileSearchBackend, @unchecked Sendable {
    struct Request {
        let term: String
        let limit: Int
        let completion: @Sendable (FileSearchResponse) -> Void
    }
    private let lock = NSLock()
    private var requests: [Request] = []
    private var cancellationCount = 0

    var count: Int { lock.withLock { requests.count } }
    var cancellations: Int { lock.withLock { cancellationCount } }
    func request(_ index: Int) -> Request { lock.withLock { requests[index] } }
    func search(_ term: String, limit: Int, completion: @escaping @Sendable (FileSearchResponse) -> Void) {
        lock.withLock { requests.append(Request(term: term, limit: limit, completion: completion)) }
    }
    func cancel() { lock.withLock { cancellationCount += 1 } }
    func finish(_ index: Int, _ response: FileSearchResponse) { request(index).completion(response) }
}

@main struct CheckFileSearchService {
    @MainActor static var checks = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    @MainActor static func eventually(_ message: String, _ condition: () -> Bool) async {
        for _ in 0..<12_000 {
            if condition() { check(true, message); return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(false, message)
    }

    @MainActor static func main() async throws {
        try checkExpressions()
        checkMetadataPaths()
        checkScopePolicy()
        await checkLifecycle()
        try await checkScopedMetadata()
        if let scope = ProcessInfo.processInfo.environment["CUE_FILE_SEARCH_FIXTURE_SCOPE"] {
            await checkIndexedFixtures(scope: scope)
        }
        print("Passed \(checks) isolated file-search backend checks (synthetic data and one empty temporary scope).")
    }

    @MainActor static func checkExpressions() throws {
        let terms = ["report", "正體中文", "a*b?.txt", #"say "hello""#, #"x\y"#,
                     "a'b", #"x") || (kMDItemFSName == "*") || (""#, "(budget)[2026].pdf"]
        for term in terms {
            let expressions = SpotlightFileSearchExpression.queries(for: term)
            check(expressions.count == 3, "exact/prefix/substring queries")
            for expression in expressions {
                check(MDQueryCreate(kCFAllocatorDefault, expression as CFString, nil, nil) != nil,
                      "Spotlight accepts escaped literal syntax")
                check(!expression.contains("kMDItemTextContent"), "filename-only query")
                check(!expression.contains("kMDItemFSInvisible"), "missing visibility metadata cannot exclude indexed filenames")
            }
        }
        let literal = SpotlightFileSearchExpression.queries(for: "*?")[0]
        check(literal.contains(#"\*\?"#), "user wildcard characters are escaped")
        check(!SpotlightFileSearchVisibility.isHidden(nil), "missing visibility metadata remains visible")
        check(!SpotlightFileSearchVisibility.isHidden(NSNumber(value: false)), "visible boolean metadata remains visible")
        check(!SpotlightFileSearchVisibility.isHidden(NSNumber(value: 0)), "visible numeric metadata remains visible")
        check(SpotlightFileSearchVisibility.isHidden(NSNumber(value: true)), "hidden boolean metadata is excluded")
        check(SpotlightFileSearchVisibility.isHidden(NSNumber(value: 1)), "hidden numeric metadata is excluded")
    }

    @MainActor static func checkScopePolicy() {
        let localRoot = SpotlightLocalScopePolicy.Mount(path: "/", isLocal: true)
        let remoteHome = SpotlightLocalScopePolicy.Mount(path: "/Users/fixture", isLocal: false)
        let remoteSibling = SpotlightLocalScopePolicy.Mount(path: "/Users/fixture-other", isLocal: false)
        check(SpotlightLocalScopePolicy.homeIsLocal("/Users/fixture", mounts: [localRoot]), "local home allows indexed-computer scope")
        check(!SpotlightLocalScopePolicy.homeIsLocal("/Users/fixture", mounts: [localRoot, remoteHome]), "remote home overrides local root")
        check(!SpotlightLocalScopePolicy.homeIsLocal("/Users/fixture/Documents", mounts: [remoteHome, localRoot]), "nested remote home remains denied")
        check(SpotlightLocalScopePolicy.homeIsLocal("/Users/fixture", mounts: [localRoot, remoteSibling]), "mount prefix uses a path boundary")
        check(!SpotlightLocalScopePolicy.homeIsLocal("/Users/fixture", mounts: []), "missing mount data denies query")
        check(!SpotlightLocalScopePolicy.homeIsLocal("relative", mounts: [localRoot]), "unknown home location denies query")
    }

    @MainActor static func checkMetadataPaths() {
        let parent = "/Users/fixture/Documents"
        let backingParent = "/System/Volumes/Data" + parent
        let metadataPath = backingParent + "/report.txt"
        let canonicalPath = FileSearchRanking.canonicalPath(metadataPath)
        check(canonicalPath == parent + "/report.txt", "APFS metadata uses the visible document path")
        check(FileSearchRanking.isUserFacingPath(canonicalPath), "APFS user document survives system filtering")
        let visible = fixture("report.txt")
        let backing = FileSearchResult(url: URL(fileURLWithPath: metadataPath), name: "report.txt", parentPath: backingParent)
        check(backing == visible, "APFS alias normalizes opening URL, parent label and identity")
        check(FileSearchRanking.results(from: [visible, backing], term: "report", limit: 9) == [visible],
              "overlapping metadata aliases produce one numbered result")
        for path in ["/System/Library/report.txt", "/Library/report.txt", "/Users/fixture/Library/report.txt",
                     "/Users/fixture/.hidden/report.txt", "/Applications/Fixture.app/Contents/report.txt"] {
            check(!FileSearchRanking.isUserFacingPath("/System/Volumes/Data" + path),
                  "Data-volume aliases preserve system, hidden and bundle-resource exclusions")
        }
        let custom = "/System/Volumes/Data/Custom/report.txt"
        check(FileSearchRanking.canonicalPath(custom) == custom && !FileSearchRanking.isUserFacingPath(custom),
              "unknown Data-volume roots are not rewritten to unrelated visible paths")
    }

    @MainActor static func checkLifecycle() async {
        let backend = FakeFileSearchBackend()
        var service: SpotlightFileSearchService? = SpotlightFileSearchService(backend: backend)
        var delivered: [String] = []
        let old = FileSearchResponse(results: [fixture("old.txt")])
        let new = FileSearchResponse(results: [fixture("new.txt")])
        service?.search("old", limit: 9) { _ in delivered.append("old") }
        service?.search("new", limit: 99) { response in
            check(response == new, "current response is retained")
            delivered.append("new")
        }
        check(backend.request(1).limit == 9, "service clamps limit before backend work")
        backend.finish(0, old)
        backend.finish(1, new)
        await eventually("current completion delivered") { delivered.count == 1 }
        check(delivered == ["new"], "stale completion is discarded")

        service?.search("cancel", limit: 9) { _ in delivered.append("cancel") }
        service?.cancel()
        backend.finish(2, old)
        service?.search("", limit: 9) { response in
            check(response.results.isEmpty, "empty term resolves locally")
        }
        service?.search(String(repeating: "a", count: 1_025), limit: 9) { response in
            check(response.results.isEmpty, "oversize term resolves locally")
        }
        service?.search("zero", limit: 0) { response in
            check(response.results.isEmpty, "zero limit resolves locally")
        }
        check(backend.count == 3, "invalid terms never reach metadata backend")
        let cancellationCount = backend.cancellations
        service = nil
        check(backend.cancellations == cancellationCount + 1, "service deinit cancels backend")
        try? await Task.sleep(for: .milliseconds(5))
        check(delivered == ["new"], "cancel/deinit prevent delivery")

        let rapid = SpotlightFileSearchService(backend: backend)
        for index in 0..<100 {
            rapid.search("query-\(index)", limit: 9) { _ in delivered.append("query-\(index)") }
        }
        for index in 3..<103 { backend.finish(index, new) }
        await eventually("latest rapid query delivered") { delivered.count == 2 }
        check(delivered.last == "query-99", "rapid typing publishes only current query")
        rapid.cancel()
    }

    @MainActor static func checkScopedMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-file-search-empty-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = SpotlightFileSearchBackend(scopePaths: [directory.path])
        let service = SpotlightFileSearchService(backend: backend)
        var response: FileSearchResponse?
        let start = ContinuousClock.now
        service.search("cue-no-existing-file-\(UUID())", limit: 9) { response = $0 }
        await eventually("actual background Spotlight completes inside empty temporary scope") { response != nil }
        check(response?.error == nil, "empty-scope metadata query completes without error")
        check(response?.results == [], "empty temporary directory returns no user files")
        print("Scoped Spotlight completion: \(start.duration(to: .now))")
        response = nil
        for index in 0..<100 {
            service.search("cancelled-\(index)", limit: 9) { _ in
                check(false, "superseded Spotlight requests must not publish")
            }
        }
        service.cancel()
        service.search("final-\(UUID())", limit: 9) { response = $0 }
        await eventually("latest query survives a rapid cancellation burst") { response != nil }
        check(response?.error == nil && response?.results.isEmpty == true, "latest scoped query result")
        service.cancel()
    }

    /// Optional opt-in for an explicitly generated, indexed fixture directory.
    /// This never creates fixtures from or searches the user's own documents.
    @MainActor static func checkIndexedFixtures(scope: String) async {
        let service = SpotlightFileSearchService(backend: SpotlightFileSearchBackend(scopePaths: [scope]))
        var positiveResults: [FileSearchResult] = []
        for _ in 0..<3 {
            var response: FileSearchResponse?
            service.search("cue-file-search-fixture", limit: 9) { response = $0 }
            await eventually("indexed synthetic fixture query completes") { response != nil }
            check(response?.error == nil, "indexed fixture metadata query completes without error")
            positiveResults = response?.results ?? []
            if !positiveResults.isEmpty { break }
            try? await Task.sleep(for: .seconds(1))
        }
        check(!positiveResults.isEmpty, "production service finds an indexed generated filename fixture")
        check(positiveResults.allSatisfy { $0.parentPath == scope && $0.name.contains("cue-file-search-fixture") },
              "positive query stays in its generated fixture scope")
        print("Production Spotlight returned \(positiveResults.count) indexed generated filename fixture(s).")
        service.cancel()
    }

    static func fixture(_ name: String) -> FileSearchResult {
        FileSearchResult(url: URL(fileURLWithPath: "/Users/fixture/Documents/\(name)"), name: name,
                         parentPath: "/Users/fixture/Documents")
    }
}
