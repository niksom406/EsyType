import EsyTypeCore
import Foundation
import Observation

/// Scratchpad notes, saved as you type or dictate.
@MainActor @Observable
final class NotesModel {
    private(set) var notes: [Note]
    var selection: UUID?
    @ObservationIgnored private let store: NotesStore

    init(store: NotesStore = NotesStore()) {
        self.store = store
        notes = store.load().sorted { $0.modified > $1.modified }
        selection = notes.first?.id
    }

    var selected: Note? { notes.first { $0.id == selection } }

    func newNote() {
        let note = Note()
        notes.insert(note, at: 0)
        selection = note.id
        save()
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modified = Date()
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selection == id { selection = notes.first?.id }
        save()
    }

    func deleteAll() {
        notes = []
        selection = nil
        save()
    }

    private func save() { try? store.save(notes) }
}
