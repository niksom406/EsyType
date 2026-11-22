import EsyTypeCore
import Foundation
import Observation

/// App-wide model state for the UI. All file work happens in `ModelStore`.
@MainActor @Observable
final class ModelLibrary {
    private(set) var installed: [InstalledModel] = []
    /// Fraction downloaded (0...1) for each download in progress. 1 means it is being verified.
    private(set) var progress: [String: Double] = [:]
    private(set) var errors: [String: String] = [:]
    @ObservationIgnored private let store = ModelStore()
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init() { Task { await refresh() } }

    func isInstalled(_ model: ModelInfo) -> Bool { installed.contains { $0.id == model.id } }

    @ObservationIgnored private let recommended = Recommender.recommend(for: HardwareDetector.current()).model

    var recommendedModel: ModelInfo { recommended }

    /// The model dictation uses: the one chosen in Settings, else the recommended one, else any installed one.
    var activeModel: ModelInfo? {
        let chosen = ModelCatalog.all.first { $0.id == UserDefaults.standard.string(forKey: Pref.modelID) }
        return [chosen, recommended].compactMap { $0 }.first(where: isInstalled) ?? ModelCatalog.all.first(where: isInstalled)
    }

    func refresh() async { installed = await store.installed() }

    /// Starts a download. Only call this from a button the user pressed.
    func download(_ model: ModelInfo) {
        guard tasks[model.id] == nil, !isInstalled(model) else { return }
        errors[model.id] = nil
        progress[model.id] = 0
        tasks[model.id] = Task {
            do {
                try await store.download(model) { bytes in
                    Task { @MainActor [weak self] in
                        guard let self, self.tasks[model.id] != nil else { return } // ignore updates after the end
                        self.progress[model.id] = Double(bytes) / Double(model.bytes)
                    }
                }
            } catch where !Task.isCancelled {
                errors[model.id] = error.localizedDescription
            } catch {} // cancelled by the user: the partial file is kept for resume
            await refresh()
            tasks[model.id] = nil
            progress[model.id] = nil
        }
    }

    func cancel(_ model: ModelInfo) { tasks[model.id]?.cancel() }

    func remove(_ model: ModelInfo) async {
        do {
            try await store.remove(model)
            errors[model.id] = nil
        } catch {
            errors[model.id] = error.localizedDescription
        }
        await refresh()
    }
}
