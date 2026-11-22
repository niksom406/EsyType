import EsyTypeCore
import Foundation
import Observation
import os

/// The snippets shared by the Snippets screen and dictation. Every change is saved straight away.
@MainActor @Observable
final class SnippetModel {
    private(set) var library: SnippetLibrary
    var notice: String?
    @ObservationIgnored private let store: SnippetStore
    /// Counts only: snippet text can hold addresses and signatures (CLAUDE.md: no user content in logs).
    private static let log = Logger(subsystem: "co.uk.esyai.esytype", category: "snippets")

    init(store: SnippetStore = SnippetStore()) {
        self.store = store
        let (library, recovered) = store.load()
        self.library = library
        if recovered { notice = "Your snippets file was damaged. It was kept next to the new one as snippets.damaged-….json." }
        Self.log.notice("Snippets loaded: \(library.snippets.count) snippets, \(library.activeCount) active\(recovered ? ", damaged file set aside" : "", privacy: .public)")
    }

    var engine: SnippetEngine { SnippetEngine(library) }

    /// Applies `body` and saves. Returns an error message instead of changing anything if it fails.
    @discardableResult
    func change(_ body: (inout SnippetLibrary) throws -> Void) -> String? {
        var copy = library
        do {
            try body(&copy)
            try store.save(copy)
            library = copy
            Self.log.notice("Snippets saved: \(copy.snippets.count)")
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
