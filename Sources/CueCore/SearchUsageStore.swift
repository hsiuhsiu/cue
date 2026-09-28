import Darwin
import Foundation

public enum SearchUsageStoreError: Error, Equatable, Sendable {
    /// Does not expose queries, application paths, or the underlying decode error.
    case unavailable
}

/// Owns the bounded usage model and all of its disk access outside the main actor.
/// Search uses a copied snapshot; it never calls this actor on the typing path.
/// Supply a file in Cue's private application-support directory.
public actor SearchUsageStore {
    // Normal files are much smaller; allow JSON's worst-case escaping while the
    // model separately limits result IDs, queries, and query/result associations.
    public static let maximumFileBytes = 4 * 1_024 * 1_024

    private let fileURL: URL
    private var usage = SearchUsage()
    private var isLoaded = false
    private var isDirty = false
    private var pendingWrite: Task<Void, Never>?

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    deinit {
        pendingWrite?.cancel()
    }

    public func load(now: Date = Date()) -> SearchUsageSnapshot {
        loadIfNeeded()
        return usage.snapshot(at: now)
    }

    /// Call only after the selected application or command has succeeded.
    /// Lazy loading and mutation have no suspension points, so an early selection
    /// cannot be overwritten by a late startup read.
    public func record(
        resultID: String, query: String, at date: Date = Date()
    ) -> SearchUsageSnapshot {
        loadIfNeeded()
        let previous = usage
        usage.record(resultID: resultID, query: query, at: date)
        if usage != previous {
            isDirty = true
            scheduleWrite()
        }
        return usage.snapshot(at: date)
    }

    /// Call after the app's queued successful-selection tasks have completed.
    /// A failed write keeps the in-memory changes dirty, allowing a later retry.
    public func flush() throws {
        pendingWrite?.cancel()
        pendingWrite = nil
        try persistPending()
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        // Learning is optional: a missing, oversized, unsupported, or corrupt file
        // must never prevent launching. The next real selection starts a clean file.
        usage = (try? read()) ?? SearchUsage()
        isLoaded = true
    }

    private func scheduleWrite() {
        guard pendingWrite == nil else { return }
        pendingWrite = Task { [weak self] in
            do {
                // This coalesces persistence only, never input, search, or launching.
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            await self?.completeScheduledWrite()
        }
    }

    private func completeScheduledWrite() {
        // Recheck inside the actor: flush may cancel a task already waiting to
        // enter here and schedule a different writer after a new selection.
        guard !Task.isCancelled else { return }
        pendingWrite = nil
        try? persistPending()
    }

    private func read() throws -> SearchUsage {
        // O_NOFOLLOW refuses symlinks; O_NONBLOCK avoids waiting on a substituted
        // named pipe before fstat can reject it. The descriptor also avoids TOCTOU
        // between checking the file and reading it.
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw SearchUsageStoreError.unavailable }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= Self.maximumFileBytes
        else { throw SearchUsageStoreError.unavailable }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw SearchUsageStoreError.unavailable }
            if count == 0 { break }
            // Also cap the read if another process grows the file after fstat.
            guard data.count + count <= Self.maximumFileBytes else {
                throw SearchUsageStoreError.unavailable
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let file = try decoder.decode(UsageFile.self, from: data)
        guard file.version == 1 else { throw SearchUsageStoreError.unavailable }
        guard fchmod(descriptor, 0o600) == 0,
              chmod(fileURL.deletingLastPathComponent().path, 0o700) == 0
        else { throw SearchUsageStoreError.unavailable }
        return file.usage
    }

    private func persistPending() throws {
        guard isDirty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(UsageFile(version: 1, usage: usage))
            guard data.count <= Self.maximumFileBytes else {
                throw SearchUsageStoreError.unavailable
            }
            try atomicWrite(data)
            isDirty = false
        } catch {
            throw SearchUsageStoreError.unavailable
        }
    }

    private func atomicWrite(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directory.path, 0o700) == 0 else { throw SearchUsageStoreError.unavailable }
        let temporary = directory.appendingPathComponent(".SearchUsage-\(UUID().uuidString).tmp")
        // Set 0600 at creation, before writing any private data. Renaming this file
        // is atomic and never follows an existing destination symlink.
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw SearchUsageStoreError.unavailable }
        defer {
            Darwin.close(descriptor)
            Darwin.unlink(temporary.path)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw SearchUsageStoreError.unavailable }
                offset += written
            }
        }
        guard fsync(descriptor) == 0,
              Darwin.rename(temporary.path, fileURL.path) == 0
        else { throw SearchUsageStoreError.unavailable }
    }

    private struct UsageFile: Codable {
        let version: Int
        let usage: SearchUsage
    }
}
