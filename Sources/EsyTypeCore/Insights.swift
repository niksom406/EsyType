import Foundation

/// Which kind of app a dictation went into, from its bundle ID only (never window titles or contents).
public enum AppCategory: String, Codable, CaseIterable, Sendable {
    case aiAssistants = "AI assistants", email = "Email", documents = "Documents", chat = "Chat", other = "Other"

    // shortcut: a fixed list of well-known apps; browsers count as Other (EsyType doesn't read which site is open).
    private static let known: [String: AppCategory] = [
        "com.openai.chat": .aiAssistants, "com.anthropic.claudefordesktop": .aiAssistants, "ai.perplexity.mac": .aiAssistants,
        "com.apple.mail": .email, "com.microsoft.Outlook": .email, "com.readdle.smartemail-Mac": .email,
        "com.superhuman.electron": .email, "it.bloop.airmail2": .email,
        "com.apple.TextEdit": .documents, "com.apple.Notes": .documents, "com.apple.iWork.Pages": .documents,
        "com.microsoft.Word": .documents, "notion.id": .documents, "md.obsidian": .documents, "com.apple.iWork.Keynote": .documents,
        "com.tinyspeck.slackmacgap": .chat, "com.apple.MobileSMS": .chat, "net.whatsapp.WhatsApp": .chat,
        "com.microsoft.teams2": .chat, "com.hnc.Discord": .chat, "ru.keepcoder.Telegram": .chat,
    ]

    public static func of(bundleID: String?) -> AppCategory { bundleID.flatMap { known[$0] } ?? .other }
}

/// One day's totals: numbers only, so Insights survives History being off or trimmed.
public struct DayTotal: Codable, Equatable, Sendable {
    public var day: String // yyyy-MM-dd in the user's time zone
    public var words = 0
    public var spokenMs = 0
    public var processingMs = 0
    public var dictations = 0
    public var wordsByCategory: [String: Int] = [:]

    public init(day: String) { self.day = day }
}

public struct InsightsSummary: Equatable, Sendable {
    public var words = 0
    public var dictations = 0
    public var spokenSeconds = 0.0
    public var processingSeconds = 0.0
    public var since: String?
    /// Words per minute while speaking.
    public var wordsPerMinute: Int { spokenSeconds > 0 ? Int((Double(words) / (spokenSeconds / 60)).rounded()) : 0 }

    /// Typing the same words at `typingWPM`, minus the time spent speaking and waiting for the text. Never negative.
    public func secondsSaved(typingWPM: Double) -> Double {
        max(0, Double(words) / typingWPM * 60 - spokenSeconds - processingSeconds)
    }
}

public struct InsightsLog: Equatable, Sendable {
    public internal(set) var days: [DayTotal]

    public init(_ days: [DayTotal] = []) { self.days = days }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

    public mutating func record(words: Int, spokenMs: Int, processingMs: Int, bundleID: String?, at date: Date,
                                calendar: Calendar = .current) {
        let key = Self.dayKey(date, calendar: calendar)
        var day = days.last?.day == key ? days.removeLast() : DayTotal(day: key)
        day.words += words
        day.spokenMs += spokenMs
        day.processingMs += processingMs
        day.dictations += 1
        day.wordsByCategory[AppCategory.of(bundleID: bundleID).rawValue, default: 0] += words
        days.append(day)
    }

    /// Totals for the last `days` days including today, or all time when nil.
    public func summary(lastDays: Int? = nil, now: Date = Date(), calendar: Calendar = .current) -> InsightsSummary {
        let chosen = selected(lastDays: lastDays, now: now, calendar: calendar)
        var summary = InsightsSummary()
        for day in chosen {
            summary.words += day.words
            summary.dictations += day.dictations
            summary.spokenSeconds += Double(day.spokenMs) / 1000
            summary.processingSeconds += Double(day.processingMs) / 1000
        }
        summary.since = chosen.first?.day
        return summary
    }

    /// Share of words per category over the last `days` days, largest first; categories with no words left out.
    public func categoryShares(lastDays: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> [(AppCategory, Double)] {
        var words: [AppCategory: Int] = [:]
        for day in selected(lastDays: lastDays, now: now, calendar: calendar) {
            for (name, count) in day.wordsByCategory { words[AppCategory(rawValue: name) ?? .other, default: 0] += count }
        }
        let total = Double(words.values.reduce(0, +))
        guard total > 0 else { return [] }
        return words.filter { $0.value > 0 }.map { ($0.key, Double($0.value) / total) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.rawValue < $1.0.rawValue }
    }

    private func selected(lastDays: Int?, now: Date, calendar: Calendar) -> [DayTotal] {
        guard let lastDays, let start = calendar.date(byAdding: .day, value: -(lastDays - 1), to: now) else { return days }
        let first = Self.dayKey(start, calendar: calendar)
        return days.filter { $0.day >= first }
    }
}

/// ~/Library/Application Support/EsyType/insights.json: daily numbers, no text.
public struct InsightsStore: Sendable {
    private let file: ListFile<DayTotal>

    public init(url: URL = ListFile<DayTotal>.inSupportFolder("insights.json")) { file = ListFile(url) }

    public func load() -> InsightsLog { InsightsLog(file.load().items) }
    public func save(_ log: InsightsLog) throws { try file.save(log.days) }
}
