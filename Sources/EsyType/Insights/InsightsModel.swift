import EsyTypeCore
import Foundation
import Observation

/// Insights' daily numbers (saved, no text) and the last dictation (memory only) for the Dictation screen.
@MainActor @Observable
final class InsightsModel {
    struct LastDictation {
        let app: String
        let spokenSeconds: Double
        let typingSeconds: Double
        let cleaned: Bool
        let text: String
    }

    private(set) var log: InsightsLog
    private(set) var last: LastDictation?
    @ObservationIgnored private let store: InsightsStore

    init(store: InsightsStore = InsightsStore()) {
        self.store = store
        log = store.load()
    }

    func record(_ dictation: LastDictation, bundleID: String?) {
        last = dictation
        log.record(words: InsightsLog.wordCount(dictation.text), spokenMs: Int(dictation.spokenSeconds * 1000),
                   processingMs: Int(dictation.typingSeconds * 1000), bundleID: bundleID, at: Date())
        try? store.save(log) // numbers only; a failed save just means today's numbers aren't kept
    }
}
