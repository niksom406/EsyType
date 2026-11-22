import CryptoKit
import Foundation
import os

public enum ModelError: Error, Equatable, LocalizedError {
    case alreadyDownloading
    case notEnoughDisk(shortfallBytes: Int64)
    case server(status: Int)
    case wrongSize(expected: Int64, actual: Int64)
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .alreadyDownloading: "This model is already downloading."
        case .notEnoughDisk(let bytes):
            "Free \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)) more disk space, then try again."
        case .server(let status): "The download server returned error \(status). Try again later."
        case .wrongSize: "The downloaded file was the wrong size, so it was deleted. Try again."
        case .checksumMismatch: "The downloaded file failed its checksum, so it was deleted. Try again."
        }
    }
}

public struct InstalledModel: Codable, Equatable, Sendable {
    public let id: String
    public let file: String
    public let bytes: Int64
    public let sha256: String
    public let installedAt: Date
}

/// Downloads, verifies, installs and removes models in one folder. Only touches files inside `directory`.
public actor ModelStore {
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "EsyType/Models", directoryHint: .isDirectory)
    }

    public nonisolated let directory: URL
    private let session: URLSession
    private let retryDelays: [Duration]
    private var inFlight: Set<String> = []
    private static let log = Logger(subsystem: "co.uk.esyai.esytype", category: "models")

    public init(directory: URL = defaultDirectory, configuration: URLSessionConfiguration = .ephemeral,
                retryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]) {
        self.directory = directory
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1 // PartWriter relies on serial callbacks
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: queue)
        self.retryDelays = retryDelays
    }

    private var registryURL: URL { directory.appending(path: "registry.json") }
    private func fileURL(_ model: ModelInfo) -> URL { directory.appending(path: model.file) }
    private func partURL(_ model: ModelInfo) -> URL { directory.appending(path: ".partial/\(model.file).part") }

    /// Models listed in registry.json whose file is still present at the expected size.
    public func installed() -> [InstalledModel] {
        guard let data = try? Data(contentsOf: registryURL),
              let list = try? Self.decoder.decode([InstalledModel].self, from: data) else { return [] }
        return list.filter { Self.size(of: directory.appending(path: $0.file)) == $0.bytes }
    }

    /// Downloads `model` (resuming any partial file), verifies size and SHA-256, then installs it atomically.
    public func download(_ model: ModelInfo, from url: URL? = nil,
                         progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws {
        if installed().contains(where: { $0.id == model.id }) { return }
        guard inFlight.insert(model.id).inserted else { throw ModelError.alreadyDownloading }
        defer { inFlight.remove(model.id) }

        let part = partURL(model)
        try FileManager.default.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        if Self.size(of: part) > model.bytes { try FileManager.default.removeItem(at: part) }
        let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? 0
        let shortfall = DiskSpace.shortfall(fileBytes: model.bytes - Self.size(of: part), freeBytes: free)
        guard shortfall == 0 else { throw ModelError.notEnoughDisk(shortfallBytes: shortfall) }

        var attempt = 0
        while Self.size(of: part) < model.bytes {
            do {
                try await fetch(url ?? model.url, to: part, expected: model.bytes, progress: progress)
                break // a short response is caught by verify below, not retried forever
            } catch where attempt < retryDelays.count && Self.isTransient(error) {
                Self.log.info("Retrying \(model.id, privacy: .public) after \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            } catch let error as ModelError {
                if case .wrongSize = error { try? FileManager.default.removeItem(at: part) }
                throw error
            }
        }

        try Self.verify(part, model)
        let destination = fileURL(model)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: part, to: destination) // same volume, so an atomic rename
        try saveRegistry(installed().filter { $0.id != model.id }
            + [InstalledModel(id: model.id, file: model.file, bytes: model.bytes, sha256: model.sha256, installedAt: .now)])
    }

    /// Deletes an installed model and any partial download of it.
    public func remove(_ model: ModelInfo) throws {
        guard !inFlight.contains(model.id) else { throw ModelError.alreadyDownloading }
        let remaining = installed().filter { $0.id != model.id }
        for file in [fileURL(model), partURL(model)] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        try saveRegistry(remaining)
    }

    /// Checks exact size and SHA-256. Deletes the file when either is wrong.
    static func verify(_ file: URL, _ model: ModelInfo) throws {
        let actual = size(of: file)
        guard actual == model.bytes else {
            try? FileManager.default.removeItem(at: file)
            throw ModelError.wrongSize(expected: model.bytes, actual: actual)
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == model.sha256 else {
            try? FileManager.default.removeItem(at: file)
            throw ModelError.checksumMismatch
        }
    }

    private func fetch(_ url: URL, to part: URL, expected: Int64,
                       progress: @escaping @Sendable (Int64) -> Void) async throws {
        let existing = Self.size(of: part)
        var request = URLRequest(url: url)
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
        let writer = PartWriter(part: part, existing: existing, expected: expected, progress: progress)
        let task = session.dataTask(with: request)
        task.delegate = writer
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                writer.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func saveRegistry(_ list: [InstalledModel]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(list).write(to: registryURL, options: .atomic)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func size(of file: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func isTransient(_ error: Error) -> Bool {
        if case ModelError.server(let status) = error { return status == 429 || status >= 500 }
        let codes: [URLError.Code] = [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                                      .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed]
        return (error as? URLError).map { codes.contains($0.code) } ?? false
    }
}

/// Appends one response to the `.part` file. A 206 continues it; any other success starts it over.
private final class PartWriter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // Set before the task starts, then touched only on the session's serial delegate queue.
    var continuation: CheckedContinuation<Void, Error>?
    private let part: URL
    private let expected: Int64
    private let progress: @Sendable (Int64) -> Void
    private var received: Int64
    private var lastReported: Int64 = 0
    private var handle: FileHandle?
    private var failure: Error?

    init(part: URL, existing: Int64, expected: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.part = part
        received = existing
        self.expected = expected
        self.progress = progress
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200 // file:// has no status
        do {
            guard status == 200 || status == 206 else { throw ModelError.server(status: status) }
            if status != 206 { received = 0 }
            if !FileManager.default.fileExists(atPath: part.path) {
                FileManager.default.createFile(atPath: part.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: part)
            try handle.truncate(atOffset: UInt64(received))
            self.handle = handle
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            guard received <= expected else { throw ModelError.wrongSize(expected: expected, actual: received) }
            if received - lastReported >= 1_000_000 || received == expected {
                lastReported = received
                progress(received)
            }
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        if let error = failure ?? error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
