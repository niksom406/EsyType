import Foundation

/// One personal-dictionary rule: when Whisper writes `spoken`, EsyType types `replacement`.
/// A **word** is spelled exactly as entered whenever it's heard (spoken = replacement); a **correction** maps what
/// the speech engine writes to what you want.
public struct DictionaryEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case word, correction }

    public var id: UUID
    public var kind: Kind
    public var spoken: String
    public var replacement: String
    /// "" = any language, otherwise a Whisper language code such as "en", "hi" or "mr".
    public var language: String
    public var category: String
    public var enabled: Bool
    public var note: String

    public init(id: UUID = UUID(), kind: Kind = .correction, spoken: String, replacement: String, language: String = "",
                category: String = "", enabled: Bool = true, note: String = "") {
        self.id = id
        self.kind = kind
        self.spoken = spoken
        self.replacement = replacement
        self.language = language
        self.category = category
        self.enabled = enabled
        self.note = note
    }

    /// `spoken` ignoring case, spacing and Unicode composition: two entries with the same key and language
    /// are duplicates or conflicts.
    public var key: String { PhraseMatcher.key(spoken) }

    /// Also matched for a word: "EsyType" as Whisper often splits it, "esy type".
    var splitKey: String? {
        guard kind == .word else { return nil }
        let split = PhraseMatcher.key(spoken.replacing(/(\p{Ll})(\p{Lu})/) { "\($0.output.1) \($0.output.2)" })
        return split == key ? nil : split
    }

    enum CodingKeys: String, CodingKey { case id, kind, spoken, replacement, language, category, enabled, note }

    // Entries saved before words existed have no kind: they are corrections.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .correction
        spoken = try c.decode(String.self, forKey: .spoken)
        replacement = try c.decode(String.self, forKey: .replacement)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    var scope: String { "\(key)\u{1F}\(language)" }
}

public enum DictionaryError: Error, Equatable, LocalizedError {
    case emptyField
    case duplicate
    case tooLong
    case badLanguage
    case multiline

    public var errorDescription: String? {
        switch self {
        case .emptyField: "Fill in both the spoken text and the replacement."
        case .duplicate: "That entry already exists."
        case .tooLong: "Keep each text under \(PersonalDictionary.maxLength) characters."
        case .badLanguage: "Use a language code such as en, hi or mr, or leave it empty for any language."
        case .multiline: "Keep the spoken text and the replacement on one line."
        }
    }
}

/// The user's dictionary: the list and every operation on it. No storage and no UI, so it can be tested alone.
public struct PersonalDictionary: Equatable, Sendable {
    public static let maxLength = 200
    public internal(set) var entries: [DictionaryEntry]

    public init(_ entries: [DictionaryEntry] = []) { self.entries = entries }

    public var activeCount: Int { entries.filter(\.enabled).count }
    public var categories: [String] { Array(Set(entries.map(\.category).filter { !$0.isEmpty })).sorted() }
    public var languages: [String] { Array(Set(entries.map(\.language))).sorted() }

    public mutating func add(_ entry: DictionaryEntry) throws {
        let entry = try Self.validated(entry)
        guard !entries.contains(where: { $0.scope == entry.scope && $0.replacement == entry.replacement }) else {
            throw DictionaryError.duplicate
        }
        entries.append(entry)
    }

    public mutating func update(_ entry: DictionaryEntry) throws {
        let entry = try Self.validated(entry)
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        guard !entries.contains(where: { $0.id != entry.id && $0.scope == entry.scope && $0.replacement == entry.replacement })
        else { throw DictionaryError.duplicate }
        entries[index] = entry
    }

    public mutating func delete(id: UUID) { entries.removeAll { $0.id == id } }

    public mutating func setEnabled(id: UUID, _ enabled: Bool) {
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].enabled = enabled }
    }

    /// Entries matching `query` in any text field, optionally one category and one language ("" = any-language entries).
    public func search(_ query: String, category: String? = nil, language: String? = nil) -> [DictionaryEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            (category == nil || entry.category == category) && (language == nil || entry.language == language)
                && (query.isEmpty || [entry.spoken, entry.replacement, entry.category, entry.note]
                    .contains { $0.localizedStandardContains(query) })
        }
    }

    /// Enabled entries ignored because an earlier enabled entry has the same words and language but another
    /// replacement. The earlier entry wins, so the result never depends on chance. Maps loser → winner.
    public var conflicts: [UUID: DictionaryEntry] {
        var winners: [String: DictionaryEntry] = [:], losers: [UUID: DictionaryEntry] = [:]
        for entry in entries where entry.enabled {
            if let winner = winners[entry.scope] {
                if winner.replacement != entry.replacement { losers[entry.id] = winner }
            } else {
                winners[entry.scope] = entry
            }
        }
        return losers
    }

    static func validated(_ entry: DictionaryEntry) throws -> DictionaryEntry {
        var entry = entry
        entry.spoken = entry.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.kind == .word { entry.replacement = entry.spoken } // a word is written as entered
        entry.replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.language = entry.language.trimmingCharacters(in: .whitespaces).lowercased()
        entry.category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.language == "any" { entry.language = "" }
        guard !entry.spoken.isEmpty, !entry.replacement.isEmpty else { throw DictionaryError.emptyField }
        guard [entry.spoken, entry.replacement, entry.category, entry.note].allSatisfy({ $0.count <= maxLength })
        else { throw DictionaryError.tooLong }
        guard !entry.spoken.contains(where: \.isNewline), !entry.replacement.contains(where: \.isNewline)
        else { throw DictionaryError.multiline }
        guard entry.language.isEmpty || entry.language.wholeMatch(of: /[a-z]{2,3}/) != nil else { throw DictionaryError.badLanguage }
        return entry
    }
}
