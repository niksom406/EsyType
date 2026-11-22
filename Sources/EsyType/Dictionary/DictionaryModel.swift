import EsyTypeCore
import Foundation
import Observation
import os

/// The personal dictionary shared by Settings and dictation. Every change is saved straight away.
@MainActor @Observable
final class DictionaryModel {
    private(set) var dictionary: PersonalDictionary
    /// Shown in Settings, e.g. when a damaged file was set aside.
    var notice: String?
    @ObservationIgnored private let store: DictionaryStore
    /// Counts only: entries can hold names and business terms (CLAUDE.md: no user content in logs).
    private static let log = Logger(subsystem: "co.uk.esyai.esytype", category: "dictionary")

    init(store: DictionaryStore = DictionaryStore()) {
        self.store = store
        let (dictionary, recovered) = store.load()
        self.dictionary = dictionary
        if recovered {
            notice = "Your dictionary file was damaged. It was kept next to the new one as dictionary.damaged-….json."
        }
        Self.log.notice("Dictionary loaded: \(dictionary.entries.count) entries, \(dictionary.activeCount) active\(recovered ? ", damaged file set aside" : "", privacy: .public)")
    }

    var engine: DictionaryEngine { DictionaryEngine(dictionary) }

    /// Applies `body` and saves. Returns an error message instead of changing anything if it fails.
    @discardableResult
    func change(_ body: (inout PersonalDictionary) throws -> Void) -> String? {
        var copy = dictionary
        do {
            try body(&copy)
            try store.save(copy)
            dictionary = copy
            Self.log.notice("Dictionary saved: \(copy.entries.count) entries")
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
