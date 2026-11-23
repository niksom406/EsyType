import Foundation

/// Scratchpad notes: saved on this Mac as you write or dictate; History's retention never touches them.
public struct Note: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), text: String = "", created: Date = Date(), modified: Date? = nil) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified ?? created
    }

    /// The first non-empty line, or "New note".
    public var title: String {
        text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : String($0.prefix(60)) } ?? "New note"
    }

    public var words: Int { InsightsLog.wordCount(text) }
}

/// ~/Library/Application Support/EsyType/notes.json (0600). The old single scratchpad.txt becomes the first note.
public struct NotesStore: Sendable {
    private let file: ListFile<Note>
    private let legacy: URL

    public init(url: URL = ListFile<Note>.inSupportFolder("notes.json"),
                legacy: URL = ListFile<Note>.inSupportFolder("scratchpad.txt")) {
        file = ListFile(url)
        self.legacy = legacy
    }

    public func load() -> [Note] {
        let (notes, _) = file.load()
        guard notes.isEmpty, !FileManager.default.fileExists(atPath: file.url.path),
              let old = try? String(contentsOf: legacy, encoding: .utf8), !old.isEmpty else { return notes }
        let migrated = [Note(text: old)]
        try? file.save(migrated) // the old file is left in place, unused
        return migrated
    }

    public func save(_ notes: [Note]) throws { try file.save(notes) }
}
