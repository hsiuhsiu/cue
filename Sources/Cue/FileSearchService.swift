import CoreServices
import CueCore
import Darwin
import Foundation

@MainActor
protocol FileSearching: AnyObject {
    func search(
        _ term: String, limit: Int,
        completion: @escaping @MainActor (FileSearchResponse) -> Void
    )
    func cancel()
}

/// A small injectable boundary for lifecycle tests; production uses Spotlight only.
protocol FileSearchBackend: Sendable {
    func search(
        _ term: String, limit: Int,
        completion: @escaping @Sendable (FileSearchResponse) -> Void
    )
    func cancel()
}

@MainActor
final class SpotlightFileSearchService: FileSearching {
    private let backend: any FileSearchBackend
    private var generation: UInt64 = 0

    init(backend: any FileSearchBackend = SpotlightFileSearchBackend()) {
        self.backend = backend
    }

    deinit { backend.cancel() }

    func search(
        _ term: String, limit: Int,
        completion: @escaping @MainActor (FileSearchResponse) -> Void
    ) {
        generation &+= 1
        let expectedGeneration = generation
        guard !term.isEmpty, limit > 0,
              term.utf8.prefix(FileSearchQuery.maximumTermUTF8Count + 1).count
                <= FileSearchQuery.maximumTermUTF8Count else {
            backend.cancel()
            completion(FileSearchResponse(results: []))
            return
        }
        backend.search(term, limit: min(limit, 9)) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                completion(response)
            }
        }
    }

    func cancel() {
        generation &+= 1
        backend.cancel()
    }
}

/// Query lifecycle and metadata decoding are confined to this background queue.
/// The lock protects only a tiny generation counter, allowing already superseded
/// enqueued requests to be discarded before they start any Spotlight work.
final class SpotlightFileSearchBackend: FileSearchBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.cue.file-search", qos: .userInitiated)
    private let generationLock = NSLock()
    private let scopePaths: [String]?
    private var generation: UInt64 = 0
    private var session: SpotlightFileSearchSession?

    /// Explicit paths are used only by isolated metadata smoke tests. Production
    /// always uses Spotlight's indexed-local-computer scope.
    init(scopePaths: [String]? = nil) { self.scopePaths = scopePaths }

    func search(
        _ term: String, limit: Int,
        completion: @escaping @Sendable (FileSearchResponse) -> Void
    ) {
        let request = advanceGeneration()
        queue.async { [self] in
            guard isCurrent(request) else { return }
            session?.cancel()
            session = nil
            // Apple's computer-indexed scope also includes a remote home. Deny
            // that edge case before creating any metadata request. The check
            // reads only the kernel's cached mount table, never a remote file.
            if scopePaths == nil, !SpotlightLocalScopePolicy.currentHomeIsLocal() {
                completion(FileSearchResponse(results: [], error: .unavailable))
                return
            }
            let next = SpotlightFileSearchSession(
                term: term, limit: limit, queue: queue, scopePaths: scopePaths,
                isCurrent: { [weak self] in self?.isCurrent(request) == true }
            ) { [weak self] response in
                guard let self, self.isCurrent(request) else { return }
                self.session = nil
                completion(response)
            }
            session = next
            next.start()
        }
    }

    func cancel() {
        let request = advanceGeneration()
        queue.async { [self] in
            guard isCurrent(request) else { return }
            session?.cancel()
            session = nil
        }
    }

    private func advanceGeneration() -> UInt64 {
        generationLock.withLock {
            generation &+= 1
            return generation
        }
    }

    private func isCurrent(_ request: UInt64) -> Bool {
        generationLock.withLock { generation == request }
    }
}

/// MDQuery provides an engine-side result cap, unlike NSMetadataQuery. Separate
/// exact/prefix/substring requests ensure broad substring matches cannot crowd
/// every exact match out of the capped candidate set. No live watcher is retained.
private final class SpotlightFileSearchSession {
    static let candidateLimit = 128

    private let term: String
    private let limit: Int
    private let queue: DispatchQueue
    private let completion: @Sendable (FileSearchResponse) -> Void
    private let scopePaths: [String]?
    private let isCurrent: @Sendable () -> Bool
    private var queries: [MDQuery] = []
    private var pending = Set<UInt>()
    private var candidates: [FileSearchResult] = []
    private var decodedPaths = Set<String>()
    private var finished = false
    private var timeout: DispatchWorkItem?

    init(
        term: String, limit: Int, queue: DispatchQueue, scopePaths: [String]?,
        isCurrent: @escaping @Sendable () -> Bool,
        completion: @escaping @Sendable (FileSearchResponse) -> Void
    ) {
        self.term = term
        self.limit = limit
        self.queue = queue
        self.scopePaths = scopePaths
        self.isCurrent = isCurrent
        self.completion = completion
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard isCurrent() else { cancel(); return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for expression in SpotlightFileSearchExpression.queries(for: term) {
            guard isCurrent() else { cancel(); return }
            guard let query = MDQueryCreate(
                kCFAllocatorDefault, expression as CFString, nil,
                [kMDItemFSName!, kMDItemPath!] as CFArray
            ) else {
                finish(error: .unavailable)
                return
            }
            // Indexed local volumes only: no filesystem fallback and no network scope.
            let scopes: CFArray = scopePaths.map { $0 as CFArray }
                ?? ([kMDQueryScopeComputerIndexed!] as CFArray)
            MDQuerySetSearchScope(query, scopes, 0)
            MDQuerySetMaxCount(query, Self.candidateLimit)
            MDQuerySetDispatchQueue(query, queue)
            let pointer = Unmanaged.passUnretained(query).toOpaque()
            pending.insert(UInt(bitPattern: pointer))
            queries.append(query)
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetLocalCenter(), observer,
                { _, observer, _, object, _ in
                    guard let observer, let object else { return }
                    Unmanaged<SpotlightFileSearchSession>.fromOpaque(observer)
                        .takeUnretainedValue().didFinish(queryPointer: object)
                },
                kMDQueryDidFinishNotification, pointer, .deliverImmediately
            )
        }
        // Register every pending query first; an immediate completion must not
        // make the first query appear to be the entire session.
        for query in queries {
            guard isCurrent() else { cancel(); return }
            guard MDQueryExecute(query, 0) else {
                finish(error: .unavailable)
                return
            }
        }
        guard !finished else { return }
        let timeout = DispatchWorkItem { [weak self] in self?.finish(error: .unavailable) }
        self.timeout = timeout
        // A missing/unresponsive metadata service must not leave a permanent
        // spinner. This does not delay successful results or debounce typing.
        queue.asyncAfter(deadline: .now() + 10, execute: timeout)
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished else { return }
        finished = true
        tearDown()
    }

    private func didFinish(queryPointer: UnsafeRawPointer) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished, pending.remove(UInt(bitPattern: queryPointer)) != nil,
              let query = queries.first(where: {
                  Unmanaged.passUnretained($0).toOpaque() == queryPointer
              }) else { return }
        guard isCurrent() else { cancel(); return }
        MDQueryDisableUpdates(query)
        let count = min(MDQueryGetResultCount(query), Self.candidateLimit)
        for index in 0..<count {
            // cancel() is enqueued on this same serial queue. Check the tiny
            // generation token directly too, so a new keystroke can stop a
            // metadata batch instead of waiting for all 128 items to decode.
            guard isCurrent() else {
                MDQueryEnableUpdates(query)
                cancel()
                return
            }
            guard let rawItem = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(rawItem).takeUnretainedValue()
            // Path/name are already in MDQuery's sorting-attribute cache. Read
            // them there first instead of asking MDItem to fetch them again.
            guard let metadataPath = cachedString(kMDItemPath, query: query, index: index)
                    ?? (MDItemCopyAttribute(item, kMDItemPath) as? String) else { continue }
            // APFS metadata may use the backing Data-volume alias. Normalize
            // before filtering and de-duplication without touching the filesystem.
            let path = FileSearchRanking.canonicalPath(metadataPath)
            guard !decodedPaths.contains(path),
                  FileSearchRanking.isUserFacingPath(path) else { continue }
            // Exact/prefix/substring queries deliberately overlap. Only decode
            // visibility/content type and construct a URL once per file.
            guard !SpotlightFileSearchVisibility.isHidden(
                MDItemCopyAttribute(item, kMDItemFSInvisible)
            ) else { continue }
            guard let name = cachedString(kMDItemFSName, query: query, index: index)
                    ?? (MDItemCopyAttribute(item, kMDItemFSName) as? String) else { continue }
            decodedPaths.insert(path)
            let contentTypes = MDItemCopyAttribute(item, kMDItemContentTypeTree) as? [String] ?? []
            let isDirectory = contentTypes.contains("public.folder")
            let url = URL(fileURLWithPath: path, isDirectory: isDirectory)
            candidates.append(FileSearchResult(
                url: url, name: name,
                parentPath: url.deletingLastPathComponent().path,
                isDirectory: isDirectory
            ))
        }
        MDQueryEnableUpdates(query)
        if pending.isEmpty { finish() }
    }

    private func finish(error: FileSearchFailure? = nil) {
        guard !finished else { return }
        guard isCurrent() else { cancel(); return }
        finished = true
        let results = FileSearchRanking.results(from: candidates, term: term, limit: limit)
        tearDown()
        completion(FileSearchResponse(results: results, error: error))
    }

    private func tearDown() {
        timeout?.cancel()
        timeout = nil
        // Stop may synchronously post a final notification, so unregister first.
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetLocalCenter(), Unmanaged.passUnretained(self).toOpaque()
        )
        for query in queries { MDQueryStop(query) }
        queries.removeAll()
        pending.removeAll()
        candidates.removeAll()
        decodedPaths.removeAll()
    }

    private func cachedString(_ attribute: CFString, query: MDQuery, index: Int) -> String? {
        guard let raw = MDQueryGetAttributeValueOfResultAtIndex(query, attribute, index) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? String
    }
}

enum SpotlightFileSearchExpression {
    static func queries(for term: String) -> [String] {
        let literal = escape(term)
        return [literal, literal + "*", "*" + literal + "*"].map {
            "(kMDItemFSName == \"\($0)\"cd)"
        }
    }

    private static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count + 8)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\", "\"", "'", "*", "?": result.append("\\")
            default: break
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}

enum SpotlightFileSearchVisibility {
    /// FSInvisible can be absent from Spotlight's searchable attributes even
    /// when MDItem can read it. Never put it in the filename predicate: doing so
    /// silently drops otherwise matching files. Missing visibility means visible.
    static func isHidden(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue == true }
}

enum SpotlightLocalScopePolicy {
    struct Mount: Sendable {
        let path: String
        let isLocal: Bool
    }

    static func homeIsLocal(_ home: String, mounts: [Mount]) -> Bool {
        guard home.hasPrefix("/") else { return false }
        let containingMount = mounts.filter {
            $0.path == "/" || home == $0.path || home.hasPrefix($0.path + "/")
        }.max { $0.path.utf8.count < $1.path.utf8.count }
        return containingMount?.isLocal == true
    }

    static func currentHomeIsLocal() -> Bool {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0, count <= 1_024 else { return false }
        var buffer = Array<statfs>(repeating: statfs(), count: Int(count) + 8)
        let readCount = buffer.withUnsafeMutableBufferPointer {
            getfsstat($0.baseAddress, Int32($0.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        guard readCount > 0, readCount <= buffer.count else { return false }
        let mounts = buffer.prefix(Int(readCount)).map { entry -> Mount in
            var path = entry.f_mntonname
            let name = withUnsafeBytes(of: &path) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            return Mount(path: name, isLocal: (entry.f_flags & UInt32(MNT_LOCAL)) != 0)
        }
        return homeIsLocal(NSHomeDirectory(), mounts: mounts)
    }
}
