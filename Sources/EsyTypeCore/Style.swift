import Foundation

/// How dictated text is finished in each app (the Windows "Style" feature). Rules change spellings, contractions,
/// stock phrases and the final full stop; they never change tone or rewrite sentences. English only.
public enum WritingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, professional, formal, casual, concise, custom
    public var id: Self { self }

    public var title: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .standard: "Nothing beyond Clean."
        case .professional: "Spoken forms written out (“gonna” → “going to”, “yeah” → “yes”); ends with a full stop."
        case .formal: "Professional, plus contractions with one meaning expanded (“don’t” → “do not”)."
        case .casual: "No full stop at the end of a one-sentence message, as in chat."
        case .concise: "Stock phrases shortened (“in order to” → “to”); “basically,” and similar dropped."
        case .custom: "Your own choice of the switches below."
        }
    }
}

/// Full stop at the end: as Whisper wrote it, always, or never. `chat` drops it only from a one-sentence message.
public enum FullStop: String, Codable, CaseIterable, Identifiable, Sendable {
    case asSpoken, always, never, chat
    public var id: Self { self }
    public var title: String {
        switch self {
        case .asSpoken: "As spoken"
        case .always: "Always"
        case .never: "Never"
        case .chat: "Not on one-sentence messages"
        }
    }
}

public struct StyleRules: Codable, Equatable, Sendable {
    public var spokenForms = false
    public var expandContractions = false
    public var shortenPhrases = false
    public var dropFillerAdverbs = false
    public var fullStop = FullStop.asSpoken

    public init(spokenForms: Bool = false, expandContractions: Bool = false, shortenPhrases: Bool = false,
                dropFillerAdverbs: Bool = false, fullStop: FullStop = .asSpoken) {
        self.spokenForms = spokenForms
        self.expandContractions = expandContractions
        self.shortenPhrases = shortenPhrases
        self.dropFillerAdverbs = dropFillerAdverbs
        self.fullStop = fullStop
    }

    public static func preset(_ style: WritingStyle, custom: StyleRules) -> StyleRules {
        switch style {
        case .standard: StyleRules()
        case .professional: StyleRules(spokenForms: true, fullStop: .always)
        case .formal: StyleRules(spokenForms: true, expandContractions: true, fullStop: .always)
        case .casual: StyleRules(fullStop: .chat)
        case .concise: StyleRules(shortenPhrases: true, dropFillerAdverbs: true)
        case .custom: custom
        }
    }
}

/// One app's style. `app` is the bundle identifier (never window titles).
public struct AppStyle: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var app: String
    public var style: WritingStyle
    public var id: String { app }

    public init(app: String, style: WritingStyle) {
        self.app = app
        self.style = style
    }
}

public struct StyleSettings: Codable, Equatable, Sendable {
    public var otherApps = WritingStyle.standard
    public var apps: [AppStyle]
    public var custom = StyleRules()

    /// The Windows defaults: mail and documents professional, chat casual.
    public static let defaultApps: [AppStyle] = ([
        ("com.apple.mail", .professional), ("com.microsoft.Outlook", .professional), ("com.microsoft.Word", .professional),
        ("com.apple.iWork.Pages", .professional), ("com.tinyspeck.slackmacgap", .casual), ("com.microsoft.teams2", .casual),
        ("net.whatsapp.WhatsApp", .casual), ("com.hnc.Discord", .casual), ("ru.keepcoder.Telegram", .casual),
        ("com.apple.MobileSMS", .casual),
    ] as [(String, WritingStyle)]).map { AppStyle(app: $0.0, style: $0.1) }

    public init(otherApps: WritingStyle = .standard, apps: [AppStyle] = StyleSettings.defaultApps, custom: StyleRules = StyleRules()) {
        self.otherApps = otherApps
        self.apps = apps
        self.custom = custom
    }

    public func style(for app: String?) -> WritingStyle { apps.first { $0.app == app }?.style ?? otherApps }
    public func rules(for app: String?) -> StyleRules { StyleRules.preset(style(for: app), custom: custom) }
}

public enum StyleEngine {
    /// The sentence the Style page uses to show each style (the Windows example).
    public static let sample = "Yeah I'm gonna send it tomorrow in order to check, basically."

    static let spokenForms: [(String, String)] = [
        ("gonna", "going to"), ("wanna", "want to"), ("gotta", "got to"), ("kinda", "kind of"), ("sorta", "sort of"),
        ("lemme", "let me"), ("gimme", "give me"), ("outta", "out of"), ("lotta", "lot of"), ("gotcha", "got you"),
        ("dunno", "don't know"), ("y'all", "you all"), ("'cause", "because"), ("cuz", "because"),
        ("yeah", "yes"), ("yep", "yes"), ("yup", "yes"), ("nope", "no"),
    ]

    /// Only contractions with one meaning ("it's" can be "it is" or "it has", so it stays).
    static let contractions: [(String, String)] = [
        ("I'm", "I am"), ("don't", "do not"), ("doesn't", "does not"), ("didn't", "did not"), ("can't", "cannot"),
        ("won't", "will not"), ("isn't", "is not"), ("aren't", "are not"), ("wasn't", "was not"), ("weren't", "were not"),
        ("haven't", "have not"), ("hasn't", "has not"), ("hadn't", "had not"), ("couldn't", "could not"),
        ("wouldn't", "would not"), ("shouldn't", "should not"), ("mustn't", "must not"), ("you're", "you are"),
        ("we're", "we are"), ("they're", "they are"), ("I've", "I have"), ("you've", "you have"), ("we've", "we have"),
        ("they've", "they have"), ("I'll", "I will"), ("you'll", "you will"), ("we'll", "we will"),
        ("they'll", "they will"), ("let's", "let us"),
    ]

    static let stockPhrases: [(String, String)] = [
        ("in order to", "to"), ("due to the fact that", "because"), ("at this point in time", "now"),
        ("at the present time", "now"), ("in the event that", "if"), ("for the purpose of", "for"),
        ("in spite of the fact that", "although"), ("with regard to", "about"), ("a large number of", "many"),
        ("in the near future", "soon"), ("prior to", "before"), ("as a matter of fact", "in fact"),
    ]

    public static func apply(_ text: String, rules: StyleRules, language: String) -> String {
        guard language == "en", !text.isEmpty else { return text }
        var result = text
        if rules.spokenForms {
            // "Yeah I'm…" → "Yes, I'm…": a sentence-opening yes/no gets the comma it's missing.
            result = result.replacing(/(?i)(^|[.!?]\s+)(yeah|yep|yup|nope)(?=\s+\w)/) { match in
                let word = match.output.2.lowercased() == "nope" ? "No" : "Yes"
                return "\(match.output.1)\(word),"
            }
            result = replaceWords(result, spokenForms)
        }
        if rules.expandContractions { result = replaceWords(result, contractions) }
        if rules.shortenPhrases { result = replaceWords(result, stockPhrases) }
        if rules.dropFillerAdverbs {
            result = result
                .replacing(/(?i),\s*(?:basically|actually|literally|honestly)(?=\s*[.!?]|$)/, with: "")
                .replacing(/(?i),\s*(?:basically|actually|literally|honestly),/, with: ",")
                .replacing(/(?i)(^|[.!?]\s+)(?:basically|actually|literally|honestly),\s*(\p{L})/) { match in
                    "\(match.output.1)\(match.output.2.uppercased())"
                }
        }
        return applyFullStop(result, rules.fullStop)
    }

    /// Whole words, any capitalisation; a capitalised match keeps its capital ("Gonna" → "Going to").
    static func replaceWords(_ text: String, _ pairs: [(String, String)]) -> String {
        var result = text
        for (from, to) in pairs.sorted(by: { $0.0.count > $1.0.count }) {
            // Either apostrophe matches (' or ’); the text keeps whichever it had outside the replaced words.
            let escaped = NSRegularExpression.escapedPattern(for: from).replacingOccurrences(of: " ", with: "\\s+")
                .replacingOccurrences(of: "'", with: "['’]")
            guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}'’])\(escaped)(?![\\p{L}\\p{N}'’])",
                                                       options: .caseInsensitive) else { continue }
            let source = result as NSString
            var output = "", last = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: source.length)) {
                let found = source.substring(with: match.range)
                output += source.substring(with: NSRange(location: last, length: match.range.location - last))
                let capital = found.first?.isUppercase == true && to.first?.isLowercase == true && from != "I'm"
                output += capital ? to.prefix(1).uppercased() + to.dropFirst() : to
                last = NSMaxRange(match.range)
            }
            result = output + source.substring(from: last)
        }
        return result
    }

    static func applyFullStop(_ text: String, _ rule: FullStop) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return text }
        let oneSentence = trimmed.dropLast().firstMatch(of: /[.!?]\s/) == nil
        switch rule {
        case .asSpoken: return trimmed
        case .always: return last.isLetter || last.isNumber || "\"”')".contains(last) ? trimmed + "." : trimmed
        case .never: return trimmed.hasSuffix(".") && !trimmed.hasSuffix("...") ? String(trimmed.dropLast()) : trimmed
        case .chat: return oneSentence ? applyFullStop(trimmed, .never) : trimmed
        }
    }
}
