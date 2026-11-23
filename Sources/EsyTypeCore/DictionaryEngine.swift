import Foundation

/// Applies the personal dictionary to a transcript, and picks words to hint to Whisper.
/// Exact matching only: no fuzzy or "close enough" replacements.
public struct DictionaryEngine: Sendable {
    /// Hints are a nudge, never a guarantee. Kept short: Whisper's prompt is limited (about 224 tokens).
    public static let maxHints = 20, maxHintCharacters = 200
    private let dictionary: PersonalDictionary
    private let builtIns: Bool
    private let hintsOn: Bool

    /// `builtIns`: also correct the common product names (`BuiltInNames`); `hints`: pass words to Whisper.
    public init(_ dictionary: PersonalDictionary, builtIns: Bool = false, hints: Bool = true) {
        self.dictionary = dictionary
        self.builtIns = builtIns
        hintsOn = hints
    }

    /// The rules for one detected language: enabled, not conflict losers, language-specific over "any language",
    /// in dictionary order (PhraseMatcher puts longer phrases first).
    func rules(for language: String) -> [DictionaryEntry] {
        let losers = dictionary.conflicts
        var chosen: [String: DictionaryEntry] = [:]
        for entry in dictionary.entries where entry.enabled && losers[entry.id] == nil
            && (entry.language.isEmpty || entry.language == language) {
            if let current = chosen[entry.key], !current.language.isEmpty || entry.language.isEmpty { continue }
            chosen[entry.key] = entry
        }
        return dictionary.entries.filter { chosen[$0.key]?.id == $0.id }
    }

    /// Returns the corrected text and how many replacements were made.
    public func apply(to text: String, language: String) -> (text: String, replacements: Int) {
        let own = rules(for: language)
        var pairs = own.flatMap { entry in [(entry.key, entry.replacement)] + (entry.splitKey.map { [($0, entry.replacement)] } ?? []) }
        if builtIns { // your own entries always win
            let taken = Set(pairs.map(\.0))
            pairs += BuiltInNames.rules.filter { !taken.contains($0.key) }.map { ($0.key, $0.replacement) }
        }
        let result = PhraseMatcher.replace(in: text, rules: pairs)
        return (result.text, result.count)
    }

    /// Replacement words to hint to Whisper. `language` nil = auto-detect, when the language is only known
    /// afterwards: then "any language" and English entries, so Devanagari hints can't pull English speech
    /// into Devanagari script.
    public func hints(language: String?) -> [String] {
        var hints: [String] = [], total = 0
        for entry in dictionary.entries where entry.enabled && dictionary.conflicts[entry.id] == nil
            && (entry.language.isEmpty || entry.language == (language ?? "en")) && !hints.contains(entry.replacement) {
            guard hints.count < Self.maxHints, total + entry.replacement.count <= Self.maxHintCharacters else { break }
            hints.append(entry.replacement)
            total += entry.replacement.count + 2
        }
        return hints
    }

    /// The whole Whisper prompt: the built-in sentence, then the hints as one punctuated sentence
    /// (Whisper copies the prompt's style, and bare words cost full stops, see TextCleanup.whisperPrompt).
    public func prompt(language: String?) -> String {
        let hints = hintsOn ? hints(language: language) : []
        return hints.isEmpty ? TextCleanup.whisperPrompt : TextCleanup.whisperPrompt + " " + hints.joined(separator: ", ") + "."
    }
}
