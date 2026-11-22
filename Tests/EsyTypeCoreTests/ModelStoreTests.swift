import CryptoKit
import Foundation
import Testing
@testable import EsyTypeCore

/// A temp folder holding a 300 KB fixture "model" and an empty Models directory.
private struct Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "EsyTypeTests-\(UUID().uuidString)")
    let body = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    var source: URL { root.appending(path: "source.bin") }
    var models: URL { root.appending(path: "Models") }
    var model: ModelInfo { model(sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()) }

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body.write(to: source)
    }

    func model(sha256: String, bytes: Int64? = nil) -> ModelInfo {
        ModelInfo(id: "fixture", name: "Fixture", quantisation: "Q8_0", file: "fixture.bin",
                  bytes: bytes ?? Int64(body.count), sha256: sha256)
    }

    func store(_ configuration: URLSessionConfiguration = .ephemeral) -> ModelStore {
        ModelStore(directory: models, configuration: configuration, retryDelays: [.zero, .zero])
    }

    var part: URL { models.appending(path: ".partial/fixture.bin.part") }
    var installedFile: URL { models.appending(path: "fixture.bin") }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private final class Counter: @unchecked Sendable { var last: Int64 = 0 }

@Test func downloadsVerifiesAndInstalls() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let store = fixture.store()
    let counter = Counter()
    try await store.download(fixture.model, from: fixture.source) { counter.last = $0 }

    #expect(try Data(contentsOf: fixture.installedFile) == fixture.body)
    #expect(await store.installed().map(\.id) == ["fixture"])
    #expect(!FileManager.default.fileExists(atPath: fixture.part.path))
    #expect(counter.last == Int64(fixture.body.count))
    try await store.download(fixture.model, from: fixture.source) // already installed: no-op
}

@Test func corruptDownloadIsRejectedAndDeleted() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let store = fixture.store()
    await #expect(throws: ModelError.checksumMismatch) {
        try await store.download(fixture.model(sha256: String(repeating: "0", count: 64)), from: fixture.source)
    }
    #expect(await store.installed().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.part.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.installedFile.path))
}

@Test func oversizedDownloadIsRejectedAndDeleted() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    await #expect(throws: ModelError.self) { // stops at the first chunk past 1000 bytes
        try await fixture.store().download(fixture.model(sha256: fixture.model.sha256, bytes: 1000), from: fixture.source)
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.part.path))
}

@Test func serverIgnoringRangeStartsOver() async throws {
    let fixture = try Fixture() // file:// ignores Range, like a server answering 200
    defer { fixture.cleanUp() }
    try FileManager.default.createDirectory(at: fixture.part.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0xFF, count: 1000).write(to: fixture.part) // stale garbage
    try await fixture.store().download(fixture.model, from: fixture.source)
    #expect(try Data(contentsOf: fixture.installedFile) == fixture.body)
}

@Test func removeDeletesOnlyThatModel() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let store = fixture.store()
    try await store.download(fixture.model, from: fixture.source)
    try await store.remove(fixture.model)
    #expect(await store.installed().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.installedFile.path))
    #expect(FileManager.default.fileExists(atPath: fixture.source.path))
    #expect(FileManager.default.fileExists(atPath: fixture.models.appending(path: "registry.json").path))
}

@Test func catalogueURLsUseThePinnedRevision() {
    for model in ModelCatalog.all {
        #expect(model.url.absoluteString ==
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/\(model.file)")
    }
}

// MARK: HTTP behaviour through a stubbed protocol (no network)

private final class StubHTTP: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var failuresLeft = 0
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) static var ranges: [String?] = []

    static func reset(body: Data) {
        self.body = body
        failuresLeft = 0
        delay = 0
        ranges = []
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHTTP.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range")
        Self.ranges.append(range)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            if Self.failuresLeft > 0 {
                Self.failuresLeft -= 1
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            var data = Self.body
            var status = 200
            if let range, let start = Int(range.dropFirst("bytes=".count).dropLast()) {
                data = data.subdata(in: start..<data.count)
                status = 206
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

@Suite(.serialized) struct HTTPDownloads {
    let url = URL(string: "https://example.invalid/fixture.bin")!

    @Test func resumesAPartialFileWithARangeRequest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        StubHTTP.reset(body: fixture.body)
        try FileManager.default.createDirectory(at: fixture.part.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.body.prefix(120_000).write(to: fixture.part)

        try await fixture.store(StubHTTP.configuration).download(fixture.model, from: url)
        #expect(StubHTTP.ranges == ["bytes=120000-"])
        #expect(try Data(contentsOf: fixture.installedFile) == fixture.body)
    }

    @Test func retriesTransientFailures() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        StubHTTP.reset(body: fixture.body)
        StubHTTP.failuresLeft = 2
        try await fixture.store(StubHTTP.configuration).download(fixture.model, from: url)
        #expect(StubHTTP.ranges.count == 3)
        #expect(await fixture.store().installed().count == 1)
    }

    @Test func givesUpAfterTheLastRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        StubHTTP.reset(body: fixture.body)
        StubHTTP.failuresLeft = 3
        await #expect(throws: URLError.self) {
            try await fixture.store(StubHTTP.configuration).download(fixture.model, from: url)
        }
        #expect(StubHTTP.ranges.count == 3)
    }

    @Test func rejectsASecondDownloadOfTheSameModel() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        StubHTTP.reset(body: fixture.body)
        StubHTTP.delay = 0.3
        let store = fixture.store(StubHTTP.configuration)
        let model = fixture.model
        let url = url
        let first = Task { try await store.download(model, from: url) }
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: ModelError.alreadyDownloading) { try await store.download(model, from: url) }
        await #expect(throws: ModelError.alreadyDownloading) { try await store.remove(model) }
        try await first.value
    }

    @Test func cancellingReleasesTheDownloadGuard() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        StubHTTP.reset(body: fixture.body)
        StubHTTP.delay = 0.5
        let store = fixture.store(StubHTTP.configuration)
        let model = fixture.model
        let url = url
        let task = Task { try await store.download(model, from: url) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(await store.installed().isEmpty)
        StubHTTP.delay = 0
        try await store.download(model, from: url) // the guard was released
        #expect(await store.installed().count == 1)
    }
}
