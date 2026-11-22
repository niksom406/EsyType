import Foundation

/// Exact whole-phrase replacement, shared by the personal dictionary and snippets. No fuzzy matching.
public enum PhraseMatcher {
    /// A phrase ignoring case, spacing and Unicode composition: equal keys are the same trigger.
    public static func key(_ phrase: String) -> String {
        phrase.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Replaces every rule's phrase (`key`) in `text` with its `replacement`, in one left-to-right pass:
    /// - any capitalisation; a space in a phrase matches any run of whitespace;
    /// - whole words only: a match never touches a letter, combining mark, digit or underscore, in any script;
    /// - where phrases overlap, the longest wins, then the earlier rule in `rules`;
    /// - replaced text is never matched again (no recursion).
    public static func replace(in text: String, rules: [(key: String, replacement: String)]) -> (text: String, count: Int) {
        guard !rules.isEmpty, !text.isEmpty else { return (text, 0) }
        let text = text.precomposedStringWithCanonicalMapping
        let ordered = rules.enumerated().sorted { a, b in
            let (wa, wb) = (a.element.key.split(separator: " ").count, b.element.key.split(separator: " ").count)
            if wa != wb { return wa > wb }
            if a.element.key.count != b.element.key.count { return a.element.key.count > b.element.key.count }
            return a.offset < b.offset
        }.map(\.element)
        let alternatives = ordered.map { rule in
            "(" + rule.key.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s+") + ")"
        }
        let pattern = "(?<![\\p{L}\\p{M}\\p{N}_])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{M}\\p{N}_])"
        // shortcut: the pattern is rebuilt per dictation (well under a millisecond for hundreds of rules); cache it for thousands.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (text, 0) }
        let source = text as NSString
        var output = "", last = 0, count = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            // The first group that matched is the rule (the order above decides overlaps).
            guard let index = (1...ordered.count).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
            output += source.substring(with: NSRange(location: last, length: match.range.location - last))
            output += ordered[index - 1].replacement
            last = match.range.location + match.range.length
            count += 1
        }
        output += source.substring(from: last)
        return (output, count)
    }
}
