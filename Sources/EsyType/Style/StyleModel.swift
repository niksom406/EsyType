import EsyTypeCore
import Foundation
import Observation

/// Style settings (per-app styles, the default, the Custom switches), kept in preferences as JSON.
@MainActor @Observable
final class StyleModel {
    nonisolated static let key = "styleSettings"
    var settings: StyleSettings { didSet { save() } }

    init() { settings = Self.current }

    /// Read fresh for each dictation, so a change in the Style page applies straight away.
    nonisolated static var current: StyleSettings {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(StyleSettings.self, from: $0) } ?? StyleSettings()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
