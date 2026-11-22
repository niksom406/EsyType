import Foundation
import Testing
@testable import EsyTypeCore

private func temporaryStore() throws -> (HistoryStore, URL) {
    let url = FileManager.default.temporaryDirectory.appending(path: "EsyTypeTests-\(UUID().uuidString)/history.sqlite")
    return (try HistoryStore(url: url), url)
}

@Test func addsSearchesAndOrdersNewestFirst() async throws {
    let (store, url) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let start = Date(timeIntervalSince1970: 1_000_000)
    try await store.add(text: "Buy milk and bread", language: "en", durationMs: 2_100, modelID: "small-q8",
                        appBundleID: "com.apple.Notes", at: start)
    try await store.add(text: "मुझे कल फ़ोन करना", language: "hi", durationMs: 3_000, modelID: "small-q8",
                        appBundleID: nil, at: start.addingTimeInterval(60))
    try await store.add(text: "It's 50% done; don't 'quote' me", language: "en", durationMs: 1_000, modelID: "base-q8",
                        appBundleID: nil, at: start.addingTimeInterval(120))

    #expect(try await store.entries().map(\.language) == ["en", "hi", "en"])
    #expect(try await store.entries(search: "MILK").first?.appBundleID == "com.apple.Notes") // case-insensitive
    #expect(try await store.entries(search: "फ़ोन").count == 1) // Devanagari
    #expect(try await store.entries(search: "50% done; don't 'q").count == 1) // SQL characters are just text
    #expect(try await store.entries(search: "%").count == 1)
    #expect(try await store.entries(search: "nothing like this").isEmpty)
    #expect(try await store.entries(limit: 2).count == 2)
}

@Test func deletesOneAllAndOlderEntries() async throws {
    let (store, url) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let now = Date()
    let old = try await store.add(text: "old", language: "en", durationMs: 1, modelID: "m", appBundleID: nil,
                                  at: now.addingTimeInterval(-40 * 86_400))
    let recent = try await store.add(text: "recent", language: "en", durationMs: 1, modelID: "m", appBundleID: nil, at: now)
    try await store.add(text: "another", language: "en", durationMs: 1, modelID: "m", appBundleID: nil, at: now)

    try await store.deleteOlder(than: now.addingTimeInterval(-30 * 86_400))
    #expect(try await store.entries().contains { $0.id == old.id } == false)
    try await store.delete(id: recent.id)
    #expect(try await store.entries().map(\.text) == ["another"])
    try await store.deleteAll()
    #expect(try await store.entries().isEmpty)
}

@Test func historyFileIsPrivateAndSurvivesReopening() async throws {
    let (store, url) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try await store.add(text: "kept", language: "en", durationMs: 1, modelID: "m", appBundleID: nil)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
    #expect(try await HistoryStore(url: url).entries().map(\.text) == ["kept"])
}
