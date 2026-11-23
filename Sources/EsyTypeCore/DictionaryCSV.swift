import Foundation

/// The dictionary's CSV columns, import and export. The CSV mechanics are in CSVFile.
public enum DictionaryCSV {
    public static let columns = ["kind", "recognised_text", "replacement_text", "language", "category", "enabled", "description"]
    public static let maxBytes = CSVFile.maxBytes
    public typealias FileError = CSVFile.FileError
    public typealias Row = CSVRow<DictionaryEntry>
    /// The Windows app's names (kind, term, replacement) and the JSON keys.
    static let aliases = ["term": "recognised_text", "spoken": "recognised_text", "replacement": "replacement_text",
                          "note": "description"]

    public static func parse(_ data: Data) throws(FileError) -> [Row] {
        try CSVFile.parse(data, required: ["recognised_text"], aliases: aliases, make: entry)
    }

    public static func parseJSON(_ data: Data) throws(FileError) -> [Row] {
        try CSVFile.parseJSON(data, required: ["recognised_text"], aliases: aliases, make: entry)
    }

    /// One row → an entry. No kind column: a word if there's no replacement (or it's the same), else a correction.
    static func entry(_ value: (String) -> String) -> Result<DictionaryEntry, RowError> {
        guard let enabled = CSVFile.bool(value("enabled")) else { return .failure(RowError(reason: "“enabled” must be true or false.")) }
        let term = value("recognised_text"), replacement = value("replacement_text")
        let kind: DictionaryEntry.Kind
        switch value("kind").trimmingCharacters(in: .whitespaces).lowercased() {
        case "word": kind = .word
        case "correction": kind = .correction
        case "": kind = replacement.isEmpty || replacement == term ? .word : .correction
        default: return .failure(RowError(reason: "“kind” must be word or correction."))
        }
        let entry = DictionaryEntry(kind: kind, spoken: term, replacement: replacement.isEmpty ? term : replacement,
                                    language: value("language"), category: value("category"),
                                    enabled: enabled, note: value("description"))
        do { return .success(try PersonalDictionary.validated(entry)) } catch {
            return .failure(RowError(reason: error.localizedDescription))
        }
    }

    public static func export(_ entries: [DictionaryEntry]) -> Data {
        CSVFile.export(header: columns, rows: entries.map {
            [$0.kind.rawValue, $0.spoken, $0.replacement, $0.language, $0.category, $0.enabled ? "true" : "false", $0.note]
        })
    }

    /// The Windows JSON shape: kind, term, replacement, plus the Mac's extra fields.
    public static func exportJSON(_ entries: [DictionaryEntry]) -> Data {
        CSVFile.exportJSON(entries.map {
            ["kind": $0.kind.rawValue, "term": $0.spoken, "replacement": $0.replacement, "language": $0.language,
             "category": $0.category, "enabled": $0.enabled, "description": $0.note]
        })
    }
}

extension PersonalDictionary {
    /// Same words + language: identical → skipped, different → update; never applied without the user's say-so.
    public func plan(_ rows: [DictionaryCSV.Row]) -> ImportPlan<DictionaryEntry> {
        ImportPlan(rows: rows, existing: entries, scope: \.scope, same: {
            $0.replacement == $1.replacement && $0.category == $1.category && $0.enabled == $1.enabled && $0.note == $1.note
                && $0.kind == $1.kind
        }, keeping: { existing, new in
            var updated = new
            updated.id = existing.id
            return updated
        })
    }

    public mutating func apply(_ plan: ImportPlan<DictionaryEntry>, updateExisting: Bool) {
        entries += plan.additions
        guard updateExisting else { return }
        for update in plan.updates {
            if let index = entries.firstIndex(where: { $0.id == update.id }) { entries[index] = update }
        }
    }
}

/// The dictionary file: ~/Library/Application Support/EsyType/dictionary.json, readable only by the user.
public struct DictionaryStore: Sendable {
    private let file: ListFile<DictionaryEntry>
    public var url: URL { file.url }

    public init(url: URL = ListFile<DictionaryEntry>.inSupportFolder("dictionary.json")) { file = ListFile(url) }

    /// A damaged file is moved aside (never deleted) and an empty dictionary is used; `recovered` says so.
    public func load() -> (dictionary: PersonalDictionary, recovered: Bool) {
        let (items, recovered) = file.load()
        return (PersonalDictionary(items.compactMap { try? PersonalDictionary.validated($0) }), recovered)
    }

    public func save(_ dictionary: PersonalDictionary) throws { try file.save(dictionary.entries) }
}

extension DictionaryCSV {
    /// Settings ▸ Dictionary ▸ Save Template. Every row is marked as a sample; nothing is added to the user's dictionary.
    public static let sampleEntries: [DictionaryEntry] = [
        ("open ai", "OpenAI", "en", "Brand"), ("git hub", "GitHub", "en", "Brand"), ("esy ai", "EsyAI", "", "Brand"),
        ("post gres", "Postgres", "en", "Technical"), ("kuber netes", "Kubernetes", "en", "Technical"),
        ("a p i", "API", "en", "Abbreviation"), ("e t a", "ETA", "en", "Abbreviation"),
        ("shawn", "Sean", "en", "Name"), ("catherine", "Kathryn", "en", "Name"),
        ("व्हाट्सएप", "WhatsApp", "hi", "Brand"), ("ईज़ी टाइप", "EsyType", "hi", "Brand"),
        ("डॉक्टर साहब", "डॉ. साहब", "hi", "Abbreviation"),
        ("इझी टाइप", "EsyType", "mr", "Brand"), ("पुणे महानगरपालिका", "पुणे महानगरपालिका (PMC)", "mr", "Abbreviation"),
    ].map { DictionaryEntry(spoken: $0.0, replacement: $0.1, language: $0.2, category: $0.3,
                            note: "SAMPLE entry: edit or delete before importing") }
}
