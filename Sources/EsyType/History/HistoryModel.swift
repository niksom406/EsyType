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

    /// Saved as "not inserted" first, before pasting, so nothing is lost; `markInserted` follows a good paste.
    @discardableResult
    func save(_ text: String, language: String, durationMs: Int, modelID: String, appBundleID: String?) -> Task<Int64?, Never>? {
        guard Self.days >= 0, let store else { return nil }
        let app = UserDefaults.standard.bool(forKey: Pref.saveSourceApp) ? appBundleID : nil
        return Task {
            defer { reload() }
            do {
                return try await store.add(text: text, language: language, durationMs: durationMs, modelID: modelID,
                                           appBundleID: app, inserted: false).id
            } catch {
                self.error = "The last dictation couldn’t be saved to history."
                return nil
            }
        }
    }

    func markInserted(_ saved: Task<Int64?, Never>?) {
        Task {
            guard let id = await saved?.value else { return }
            try? await store?.setInserted(id: id, true)
            reload()
        }
    }

    func update(_ entry: HistoryEntry, text: String) {
        Task {
            try? await store?.update(id: entry.id, text: text)
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
