import Darwin
import Foundation

/// Bounded IO on an actor executor, never from a key event or a render callback.
public actor CommandHistoryStore {
    public enum Failure: Error { case unavailable }
    public static let maximumFileBytes = 4 * 1_024 * 1_024
    private let fileURL: URL
    private var history = CommandHistory()
    private var loaded = false
    private var dirty = false
    private var writer: Task<Void, Never>?

    public init(fileURL: URL) { self.fileURL = fileURL }
    deinit { writer?.cancel() }

    public func load(now: Date = Date()) -> CommandHistory {
        if !loaded {
            history = (try? read()) ?? CommandHistory()
            loaded = true
        }
        let previous = history
        history.prune(now: now)
        if history != previous { dirty = true; scheduleWrite() }
        return history
    }

    public func record(_ entry: CommandHistoryEntry, now: Date = Date()) -> CommandHistory {
        _ = load(now: now)
        history.record(entry, now: now)
        dirty = true
        scheduleWrite()
        return history
    }

    public func remove(_ id: UUID, now: Date = Date()) -> CommandHistory {
        _ = load(now: now)
        history.remove(id)
        dirty = true
        scheduleWrite()
        return history
    }

    public func clear() -> CommandHistory {
        loaded = true
        history.clear()
        dirty = true
        scheduleWrite()
        return history
    }

    public func flush() throws {
        writer?.cancel()
        writer = nil
        guard dirty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(File(version: 1, history: history))
        guard data.count <= Self.maximumFileBytes else { throw Failure.unavailable }
        try write(data)
        dirty = false
    }

    private func scheduleWrite() {
        guard writer == nil else { return }
        writer = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            await self?.completeWrite()
        }
    }

    private func completeWrite() {
        guard !Task.isCancelled else { return }
        try? flush()
    }

    private struct File: Codable { let version: Int; let history: CommandHistory }

    private func read() throws -> CommandHistory {
        let fd = Darwin.open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= Self.maximumFileBytes else { throw Failure.unavailable }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0, data.count + count <= Self.maximumFileBytes else { throw Failure.unavailable }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let file = try decoder.decode(File.self, from: data)
        guard file.version == 1 else { throw Failure.unavailable }
        return file.history
    }

    private func write(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard chmod(directory.path, 0o700) == 0 else { throw Failure.unavailable }
        let temporary = directory.appendingPathComponent(".History-\(UUID()).tmp")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(fd); Darwin.unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.unavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0, Darwin.rename(temporary.path, fileURL.path) == 0 else { throw Failure.unavailable }
    }
}
