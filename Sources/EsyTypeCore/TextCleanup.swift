import Foundation

/// Which cleanup rules run. Each can be switched off in Text Cleanup.
public struct CleanupOptions: Equatable, Sendable {
    public var fillers = true
    public var repeatedWords = true
    public var repeatedPhrases = true
    public var punctuation = true
    public var capitalisation = true

    public init(fillers: Bool = true, repeatedWords: Bool = true, repeatedPhrases: Bool = true,
                punctuation: Bool = true, capitalisation: Bool = true) {
        self.fillers = fillers
        self.repeatedWords = repeatedWords
        self.repeatedPhrases = repeatedPhrases
        self.punctuation = punctuation
        self.capitalisation = capitalisation
    }

    public static let none = CleanupOptions(fillers: false, repeatedWords: false, repeatedPhrases: false,
                                            punctuation: false, capitalisation: false)
}

/// Deterministic tidy-up of Whisper output: rules only, no model. Removes noise and fixes layout; never rewords.
public enum TextCleanup {
    /// Whisper's spelling hint. A full punctuated sentence: the bare word "EsyType" made Whisper drop full stops
    /// (2 of 5 clips, 2026-11-22), and Whisper copies the hint's style.
    public static let whisperPrompt = "Hello, welcome to EsyType."

    /// `language` is Whisper's code for the transcript. Fillers and repeats are English-only: Hindi and Marathi
    /// repeat words on purpose ("धीरे धीरे"), and their hesitation words are also real words.
    public static func clean(_ text: String, options: CleanupOptions, language: String) -> String {
        var (result, protected) = mask(text.replacing(/\[[^\]]*\]/, with: "")) // Whisper markers like [BLANK_AUDIO]
        let english = language == "en"
        if options.fillers, english { result = removeFillers(result) }
        if english, options.repeatedWords || options.repeatedPhrases {
            result = removeRepeats(result, words: options.repeatedWords, phrases: options.repeatedPhrases)
        }
        if result != text { result = closeGaps(result) } // removals leave gaps, even with punctuation rules off
        if options.punctuation { result = fixPunctuation(result) }
        if options.capitalisation { result = capitalise(result.trimmingCharacters(in: .whitespacesAndNewlines), english: english) }
        return unmask(result.trimmingCharacters(in: .whitespacesAndNewlines), protected)
    }

    // MARK: Protected text

    /// Web addresses, emails, paths, code identifiers and numbers like 3.5 are swapped for placeholders, so no
    /// rule can change them, then put back at the end.
    private static var protectedPattern: Regex<Substring> { /(?:https?|ftp):\/\/\S+|www\.\S+|[\w.%+-]+@[\w-]+(?:\.[\w-]+)+|\S*(?:[_\/\\]|::|\(\)|[\p{L}\p{N}]\.[a-z0-9])\S*/ }

    /// Abbreviations whose full stop doesn't end a sentence; masked whole so "e.g. this" keeps its small "t".
    private static var abbreviations: Regex<Substring> { /(?i)\b(?:e\.g\.|i\.e\.|a\.m\.|p\.m\.|etc\.|vs\.|approx\.|mr\.|mrs\.|ms\.|dr\.)/ }

    static func mask(_ text: String) -> (String, [String]) {
        var protected: [String] = []
        let abbreviated = text.replacing(abbreviations) { match in
            protected.append(String(match.output))
            return "\u{E000}\(protected.count - 1)\u{E001}"
        }
        let masked = abbreviated.replacing(protectedPattern) { match in
            // Keep sentence punctuation that ended up stuck to the end of the token outside the placeholder.
            var token = String(match.output)
            var tail = ""
            while let last = token.last, ".,;:!?)".contains(last), token.count > 1 { tail = String(last) + tail; token.removeLast() }
            protected.append(token)
            return "\u{E000}\(protected.count - 1)\u{E001}" + tail
        }
        return (masked, protected)
    }

    static func unmask(_ text: String, _ protected: [String]) -> String {
        text.replacing(/\x{E000}(\d+)\x{E001}/) { protected[Int($0.output.1)!] }
    }

    // MARK: Rules

    /// um, umm, uh, uhh, erm as whole words (not "uh-oh"), with a comma right after them (a full stop stays:
    /// it ends the sentence).
    /// "hmm" only where it stands alone as a hesitation: at the start of a sentence or set off by punctuation.
    static func removeFillers(_ text: String) -> String {
        text.replacing(/(?i)\b(?:u+m+|u+h+|e+r+m+)\b(?!-),?/, with: "")
            .replacing(/(?i)(^|[.!?,]\s*)h+m+\b(?!-)[,.]?/) { $0.output.1 }
    }

    /// Doubles that are usually meant: emphasis ("very very"), grammar ("had had", "that that"), sounds ("ha ha").
    static let intendedDoubles: Set<String> = [
        "very", "really", "so", "no", "yes", "yeah", "bye", "ha", "haha", "hey", "oh", "well", "many", "much",
        "more", "had", "that", "is", "do", "now", "far", "long", "too", "again", "never", "please", "go", "knock",
        "tick", "tock", "blah", "la", "chop", "night", "boo", "bang", "beep", "wow", "out", "over", "round",
    ]

    /// Removes the first copy of an immediately repeated word or phrase (up to 5 words), as in a restart:
    /// "I think, I think we should go" → "I think we should go". Kept on purpose:
    /// - a repeat that ends the sentence ("never give up, never give up."), usually an echo for emphasis;
    /// - three or more in a row ("no no no");
    /// - numbers ("4 4 2"), and the `intendedDoubles` words.
    static func removeRepeats(_ text: String, words: Bool, phrases: Bool) -> String {
        let source = text as NSString
        let tokens = (try? NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}'’]+"))?
            .matches(in: text, range: NSRange(location: 0, length: source.length)).map(\.range) ?? []
        let lower = tokens.map { source.substring(with: $0).lowercased() }
        func gap(_ a: Int, _ b: Int) -> String { // text between token a and token b
            source.substring(with: NSRange(location: NSMaxRange(tokens[a]), length: tokens[b].location - NSMaxRange(tokens[a])))
        }
        func phrase(_ start: Int, _ n: Int) -> ArraySlice<String> { lower[start..<start + n] }
        func joinedBySpaces(_ start: Int, _ n: Int) -> Bool {
            (start..<start + n - 1).allSatisfy { gap($0, $0 + 1).allSatisfy(\.isWhitespace) }
        }
        var removals: [NSRange] = [], i = 0
        while i < tokens.count {
            var removed = false
            for n in stride(from: 5, through: 1, by: -1) where (n == 1 ? words : phrases) && i + 2 * n < tokens.count {
                let a = i, b = i + n, next = i + 2 * n
                guard phrase(a, n) == phrase(b, n), joinedBySpaces(a, n), joinedBySpaces(b, n),
                      gap(b - 1, b).wholeMatch(of: /,?\s+/) != nil,                // nothing but a comma between the copies
                      gap(next - 1, next).allSatisfy(\.isWhitespace),               // and the sentence carries on
                      !(next + n <= tokens.count && phrase(next, n) == phrase(a, n)), // not 3 in a row
                      !(a >= n && phrase(a - n, n) == phrase(a, n))
                else { continue }
                if n == 1, intendedDoubles.contains(lower[a]) || lower[a].contains(where: \.isNumber) { continue }
                removals.append(NSRange(location: tokens[a].location, length: tokens[b].location - tokens[a].location))
                i = b
                removed = true
                break
            }
            if !removed { i += 1 }
        }
        var result = text
        for range in removals.reversed() { result = (result as NSString).replacingCharacters(in: range, with: "") }
        return result
    }

    /// After a removal: runs of spaces become one and stray punctuation at the very start goes.
    static func closeGaps(_ text: String) -> String {
        text.replacing(/[ \t]{2,}/, with: " ").replacing(/^\s*[,.;:]*\s*/, with: "")
    }

    /// Runs of spaces become one, lines keep their breaks (at most one blank line), no spaces at line ends,
    /// no space before punctuation (incl. the Devanagari danda), and no stray punctuation at the very start.
    static func tidySpacing(_ text: String) -> String {
        text.replacing(/[ \t\u{00A0}]+/, with: " ")
            .replacing(/\x20*\n\x20*/, with: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .replacing(/\x20+([,.!?;:।])/) { $0.output.1 }
            .replacing(/^\s*[,.;:]*\s*/, with: "") // left behind when the text began with a filler
    }

    /// One space after , ; ! ? । before a letter; after . only before a capital (so "3.5" and "e.g." never change);
    /// doubled , ; and "..", "?." become one mark; a comma right before a full stop goes. "..." "!!" "?!" stay.
    static func fixPunctuation(_ text: String) -> String {
        // " .see you" (Whisper put the space on the wrong side): the mark goes back onto the word before.
        tidySpacing(text.replacing(/\x20+([.,;!?।])(?=\p{L})/) { "\($0.output.1) " })
            .replacing(/([,;!?।])(?=\p{L})/) { "\($0.output.1) " }
            .replacing(/(\p{Ll}{2})\.(?=\p{Lu})/) { "\($0.output.1). " }
            .replacing(/,{2,}/, with: ",")
            .replacing(/;{2,}/, with: ";")
            .replacing(/(^|[^.])\.\.(?!\.)/) { "\($0.output.1)." }
            .replacing(/[,;:]+([.!?])/) { $0.output.1 }
            .replacing(/([!?])\.(?!\.)/) { $0.output.1 }
    }

    /// Capitalises the first letter of the text, of each sentence and of each line. Only all-lowercase words, so
    /// "iPhone" and "macOS" stay as they are; nothing is ever lowercased. In English, "i" becomes "I".
    static func capitalise(_ text: String, english: Bool) -> String {
        // Abbreviations are masked (see `mask`), so their full stops never count as a sentence end here.
        var result = text.replacing(/(^|[.!?।]\s+|\n)(\p{Ll}[\p{L}\p{M}'’]*)/) { match in
            let before = match.output.1, word = String(match.output.2)
            guard !word.dropFirst().contains(where: \.isUppercase) else { return "\(before)\(word)" }
            return "\(before)\(word.prefix(1).uppercased())\(word.dropFirst())"
        }
        if english { result = result.replacing(/(^|[^\p{L}\p{N}\x{E001}])i(?=['’](?:m|ve|ll|d)\b|[\s,;!?]|$)/) { "\($0.output.1)I" } }
        return result
    }

    /// Adds a space so a new dictation doesn't stick to the text before the cursor ("dog.Please").
    public static func spaced(_ text: String, after previous: Character?) -> String {
        guard let previous, !previous.isWhitespace, !"([{\"'“‘".contains(previous),
              let first = text.first, !first.isWhitespace, !".,!?;:)]}…".contains(first) else { return text }
        return " " + text
    }
}
