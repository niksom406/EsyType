import EsyTypeCore
import Foundation
import Testing

// Simulated: made-up dictations on fixed dates.
private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func date(_ day: Int, _ hour: Int = 10) -> Date { utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }

@Test func recordsDailyTotalsAndSummaries() {
    var log = InsightsLog()
    log.record(words: 40, spokenMs: 20_000, processingMs: 1_000, bundleID: "com.apple.mail", at: date(17), calendar: utc)
    log.record(words: 60, spokenMs: 25_000, processingMs: 1_000, bundleID: "com.openai.chat", at: date(22, 9), calendar: utc)
    log.record(words: 20, spokenMs: 15_000, processingMs: 1_000, bundleID: "com.apple.TextEdit", at: date(22, 18), calendar: utc)
    #expect(log.days.map(\.day) == ["2026-11-17", "2026-11-22"])
    #expect(log.days.last?.dictations == 2)

    let all = log.summary(now: date(22), calendar: utc)
    #expect(all.words == 120 && all.dictations == 3 && all.since == "2026-11-17")
    #expect(all.wordsPerMinute == 120) // 120 words in 60 s of speaking
    // Typing 120 words at 40 wpm = 180 s, minus 60 s speaking and 3 s waiting.
    #expect(all.secondsSaved(typingWPM: 40) == 117)

    let week = log.summary(lastDays: 3, now: date(22), calendar: utc)
    #expect(week.words == 80 && week.dictations == 2)
}

@Test func categoriesComeFromBundleIDsOnly() {
    #expect(AppCategory.of(bundleID: "com.tinyspeck.slackmacgap") == .chat)
    #expect(AppCategory.of(bundleID: "com.google.Chrome") == .other) // a browser: which site isn't known
    #expect(AppCategory.of(bundleID: nil) == .other)
    var log = InsightsLog()
    log.record(words: 30, spokenMs: 1, processingMs: 0, bundleID: "com.openai.chat", at: date(22), calendar: utc)
    log.record(words: 10, spokenMs: 1, processingMs: 0, bundleID: "com.apple.mail", at: date(22), calendar: utc)
    let shares = log.categoryShares(now: date(22), calendar: utc)
    #expect(shares.map(\.0) == [.aiAssistants, .email])
    #expect(shares.map(\.1) == [0.75, 0.25])
}

@Test func emptyAndSlowSpeechAreSafe() {
    let empty = InsightsLog().summary()
    #expect(empty.words == 0 && empty.wordsPerMinute == 0 && empty.since == nil && empty.secondsSaved(typingWPM: 40) == 0)
    var log = InsightsLog()
    log.record(words: 2, spokenMs: 60_000, processingMs: 5_000, bundleID: nil, at: date(22), calendar: utc)
    #expect(log.summary().secondsSaved(typingWPM: 40) == 0) // never negative
    #expect(InsightsLog.wordCount("Best regards,\nPriya  Sharma") == 4)
}

@Test func insightsStorePersistsNumbersOnly() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "insights-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var log = InsightsLog()
    log.record(words: 5, spokenMs: 2_000, processingMs: 300, bundleID: "com.apple.Notes", at: date(22), calendar: utc)
    try InsightsStore(url: url).save(log)
    #expect(InsightsStore(url: url).load() == log)
    let json = try String(contentsOf: url, encoding: .utf8)
    #expect(!json.contains("com.apple.Notes")) // categories only, not which app
}
