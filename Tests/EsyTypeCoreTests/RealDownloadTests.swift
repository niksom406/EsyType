import Foundation
import Testing
@testable import EsyTypeCore

/// Downloads real models into ~/Library/Application Support/EsyType/Models. Opt-in only:
/// `ESYTYPE_REAL_DOWNLOAD=1 Scripts/test.sh --filter realDownloads`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ESYTYPE_REAL_DOWNLOAD"] != nil),
      .timeLimit(.minutes(30)))
func realDownloadsFromHuggingFace() async throws {
    let store = ModelStore()
    // Resume over the real network: stop Turbo Q8 part-way, then finish it.
    let model = ModelCatalog.turboQ8
    let part = store.directory.appending(path: ".partial/\(model.file).part")
    let first = Task { try await store.download(model) }
    try await Task.sleep(for: .seconds(2))
    first.cancel()
    _ = await first.result
    let partial = ModelStore.size(of: part)
    print("RESUME partial=\(partial) of \(model.bytes)")

    for model in ModelCatalog.all { try await store.download(model) }
    let installed = await store.installed().map(\.id)
    #expect(Set(installed) == Set(ModelCatalog.all.map(\.id)))
    #expect(partial > 0 && partial < model.bytes)
}
