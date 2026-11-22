import Foundation

/// A saved text: saying `trigger` types `text` (which may span several lines).
public struct Snippet: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: String
    public var text: String
    public var category: String
    /// "" = any language, otherwise a Whisper language code such as "en", "hi" or "mr".
    public var language: String
    public var enabled: Bool
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), name: String = "", trigger: String, text: String, category: String = "",
                language: String = "", enabled: Bool = true, created: Date = Date(), modified: Date? = nil) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.text = text
        self.category = category
        self.language = language
        self.enabled = enabled
        self.created = created
        self.modified = modified ?? created
    }

    public var key: String { PhraseMatcher.key(trigger) }
    var scope: String { "\(key)\u{1F}\(language)" }
}

public enum SnippetError: Error, Equatable, LocalizedError {
    case emptyTrigger, emptyText, multilineTrigger, tooLong, badLanguage
    case duplicateTrigger(usedBy: String)

    public var errorDescription: String? {
        switch self {
        case .emptyTrigger: "Enter the phrase you’ll say."
        case .emptyText: "Enter the text to type."
        case .multilineTrigger: "Keep the trigger phrase on one line."
        case .tooLong: "The trigger can be up to \(SnippetLibrary.maxTrigger) characters and the text up to \(SnippetLibrary.maxText)."
        case .badLanguage: "Use a language code such as en, hi or mr, or leave it empty for any language."
        case .duplicateTrigger(let name): "“\(name)” already uses that trigger phrase."
        }
    }
}

/// The user's snippets and every operation on them. No storage and no UI, so it can be tested alone.
public struct SnippetLibrary: Equatable, Sendable {
    public static let maxTrigger = 100, maxText = 5_000, maxName = 100
    public internal(set) var snippets: [Snippet]

    public init(_ snippets: [Snippet] = []) { self.snippets = snippets }

    public var activeCount: Int { snippets.filter(\.enabled).count }
    public var categories: [String] { Array(Set(snippets.map(\.category).filter { !$0.isEmpty })).sorted() }
    public var languages: [String] { Array(Set(snippets.map(\.language))).sorted() }

    public mutating func add(_ snippet: Snippet, now: Date = Date()) throws {
        var snippet = try Self.validated(snippet)
        try checkTrigger(snippet)
        (snippet.created, snippet.modified) = (now, now)
        snippets.append(snippet)
    }

    public mutating func update(_ snippet: Snippet, now: Date = Date()) throws {
        var snippet = try Self.validated(snippet)
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        try checkTrigger(snippet)
        snippet.created = snippets[index].created
        snippet.modified = now
        snippets[index] = snippet
    }

    public mutating func delete(id: UUID) { snippets.removeAll { $0.id == id } }

    public mutating func setEnabled(id: UUID, _ enabled: Bool, now: Date = Date()) {
        guard let index = snippets.firstIndex(where: { $0.id == id }), snippets[index].enabled != enabled else { return }
        snippets[index].enabled = enabled
        snippets[index].modified = now
    }

    public func search(_ query: String, category: String? = nil, language: String? = nil) -> [Snippet] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return snippets.filter { snippet in
            (category == nil || snippet.category == category) && (language == nil || snippet.language == language)
                && (query.isEmpty || [snippet.name, snippet.trigger, snippet.text, snippet.category]
                    .contains { $0.localizedStandardContains(query) })
        }
    }

    /// Enabled snippets sharing a trigger and language: it's unclear which one was meant, so none of them expands.
    /// (Adding or editing refuses duplicates; this catches hand-edited files.)
    public var ambiguous: Set<UUID> {
        Set(Dictionary(grouping: snippets.filter(\.enabled), by: \.scope).values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    private func checkTrigger(_ snippet: Snippet) throws {
        if let other = snippets.first(where: { $0.id != snippet.id && $0.scope == snippet.scope }) {
            throw SnippetError.duplicateTrigger(usedBy: other.name)
        }
    }

    static func validated(_ snippet: Snippet) throws -> Snippet {
        var snippet = snippet
        snippet.trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        snippet.name = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        snippet.category = snippet.category.trimmingCharacters(in: .whitespacesAndNewlines)
        snippet.language = snippet.language.trimmingCharacters(in: .whitespaces).lowercased()
        if snippet.language == "any" { snippet.language = "" }
        guard !snippet.trigger.isEmpty else { throw SnippetError.emptyTrigger }
        guard !snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SnippetError.emptyText }
        guard !snippet.trigger.contains(where: \.isNewline) else { throw SnippetError.multilineTrigger }
        guard snippet.trigger.count <= maxTrigger, snippet.text.count <= maxText,
              snippet.name.count <= maxName, snippet.category.count <= maxName else { throw SnippetError.tooLong }
        guard snippet.language.isEmpty || snippet.language.wholeMatch(of: /[a-z]{2,3}/) != nil else { throw SnippetError.badLanguage }
        if snippet.name.isEmpty { snippet.name = snippet.trigger }
        return snippet
    }
}

/// Expands trigger phrases in a finished transcript. Runs after the dictionary, so snippet text is never changed
/// by dictionary rules, and in one pass, so a snippet's text never triggers another snippet.
public struct SnippetEngine: Sendable {
    private let library: SnippetLibrary

    public init(_ library: SnippetLibrary) { self.library = library }

    public func expand(_ text: String, language: String) -> (text: String, expansions: Int) {
        let ambiguous = library.ambiguous
        var chosen: [String: Snippet] = [:]
        for snippet in library.snippets where snippet.enabled && !ambiguous.contains(snippet.id)
            && (snippet.language.isEmpty || snippet.language == language) {
            if let current = chosen[snippet.key], !current.language.isEmpty || snippet.language.isEmpty { continue }
            chosen[snippet.key] = snippet // a snippet for this language overrides an "any language" one
        }
        let rules = library.snippets.filter { chosen[$0.key]?.id == $0.id }.map { ($0.key, $0.text) }
        let result = PhraseMatcher.replace(in: text, rules: rules)
        return (result.text, result.count)
    }
}

// MARK: CSV and storage

public enum SnippetCSV {
    public static let columns = ["name", "trigger_phrase", "replacement_text", "category", "language", "enabled",
                                 "created_at", "modified_at"]
    public typealias Row = CSVRow<Snippet>

    public static func parse(_ data: Data, now: Date = Date()) throws(CSVFile.FileError) -> [Row] {
        try CSVFile.parse(data, required: ["trigger_phrase", "replacement_text"]) { value in
            guard let enabled = CSVFile.bool(value("enabled")) else { return .failure(RowError(reason: "“enabled” must be true or false.")) }
            let created = date(value("created_at")) ?? now
            let snippet = Snippet(name: value("name"), trigger: value("trigger_phrase"), text: value("replacement_text"),
                                  category: value("category"), language: value("language"), enabled: enabled,
                                  created: created, modified: date(value("modified_at")) ?? created)
            do { return .success(try SnippetLibrary.validated(snippet)) } catch {
                return .failure(RowError(reason: error.localizedDescription))
            }
        }
    }

    public static func export(_ snippets: [Snippet]) -> Data {
        CSVFile.export(header: columns, rows: snippets.map {
            [$0.name, $0.trigger, $0.text, $0.category, $0.language, $0.enabled ? "true" : "false", stamp($0.created), stamp($0.modified)]
        })
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
    static func stamp(_ date: Date) -> String { formatter().string(from: date) }
    static func date(_ text: String) -> Date? { text.isEmpty ? nil : formatter().date(from: text) }
}

extension SnippetLibrary {
    /// Same trigger + language: identical → skipped, different → update (only if the user ticks it).
    public func plan(_ rows: [SnippetCSV.Row]) -> ImportPlan<Snippet> {
        ImportPlan(rows: rows, existing: snippets, scope: \.scope, same: {
            $0.name == $1.name && $0.text == $1.text && $0.category == $1.category && $0.enabled == $1.enabled
        }, keeping: { existing, new in
            var updated = new
            updated.id = existing.id
            updated.created = existing.created
            return updated
        })
    }

    public mutating func apply(_ plan: ImportPlan<Snippet>, updateExisting: Bool, now: Date = Date()) {
        snippets += plan.additions
        guard updateExisting else { return }
        for var update in plan.updates {
            guard let index = snippets.firstIndex(where: { $0.id == update.id }) else { continue }
            update.modified = now
            snippets[index] = update
        }
    }
}

/// ~/Library/Application Support/EsyType/snippets.json, readable only by the user.
public struct SnippetStore: Sendable {
    private let file: ListFile<Snippet>
    public var url: URL { file.url }

    public init(url: URL = ListFile<Snippet>.inSupportFolder("snippets.json")) { file = ListFile(url) }

    public func load() -> (library: SnippetLibrary, recovered: Bool) {
        let (items, recovered) = file.load()
        return (SnippetLibrary(items.compactMap { try? SnippetLibrary.validated($0) }), recovered)
    }

    public func save(_ library: SnippetLibrary) throws { try file.save(library.snippets) }
}
