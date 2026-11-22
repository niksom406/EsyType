import AppKit
import EsyTypeCore
import Observation

/// History for the UI. Applies the retention setting before every read and after every save.
@MainActor @Observable
final class HistoryModel {
    private(set) var entries: [HistoryEntry] = []
    private(set) var error: String?
    var search = "" { didSet { reload() } }
    @ObservationIgnored private let store: HistoryStore?
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(url: URL = HistoryStore.defaultURL) {
        do {
            store = try HistoryStore(url: url)
        } catch {
            store = nil
            self.error = "History couldn’t be opened, so dictations aren’t being saved."
        }
        reload()
    }

    private static var days: Int { UserDefaults.standard.integer(forKey: Pref.historyDays) }

    func save(_ text: String, language: String, durationMs: Int, modelID: String, appBundleID: String?) {
        guard Self.days >= 0, let store else { return }
        let app = UserDefaults.standard.bool(forKey: Pref.saveSourceApp) ? appBundleID : nil
        Task {
            do {
                try await store.add(text: text, language: language, durationMs: durationMs, modelID: modelID, appBundleID: app)
            } catch {
                self.error = "The last dictation couldn’t be saved to history."
            }
            reload()
        }
    }

    func reload() {
        loading?.cancel()
        let search = search, days = Self.days
        loading = Task {
            guard let store else { return }
            if days > 0 { try? await store.deleteOlder(than: Date.now.addingTimeInterval(-Double(days) * 86_400)) }
            let found = (try? await store.entries(search: search)) ?? []
            if !Task.isCancelled { entries = found } // a newer search may have started
        }
    }

    func delete(_ entry: HistoryEntry) {
        Task {
            try? await store?.delete(id: entry.id)
            reload()
        }
    }

    func clearAll() {
        Task {
            try? await store?.deleteAll()
            reload()
        }
    }
}
