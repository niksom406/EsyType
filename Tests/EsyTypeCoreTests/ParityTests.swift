import EsyTypeCore
import Foundation
import SQLite3
import Testing

// Simulated: Windows-parity data formats, snippet modes, history status and notes.

@Test func dictionaryReadsTheWindowsCSVAndJSONRoundTrips() throws {
    let windows = try DictionaryCSV.parse(Data("kind,term,replacement\nword,EsyType,\ncorrection,chat gpt,ChatGPT\n".utf8))
    let entries = try windows.map { try $0.result.get() }
    #expect(entries.map(\.kind) == [.word, .correction])
    #expect(entries.map(\.replacement) == ["EsyType", "ChatGPT"])
    let simple = try DictionaryCSV.parse(Data("term,replacement\nPriya,\n".utf8)).map { try $0.result.get() }
    #expect(simple.first?.kind == .word)
    let json = DictionaryCSV.exportJSON(entries)
    let back = try DictionaryCSV.parseJSON(json).map { try $0.result.get() }
    #expect(back.map(\.spoken) == entries.map(\.spoken) && back.map(\.kind) == entries.map(\.kind))
    #expect(throws: CSVFile.FileError.notJSON) { try DictionaryCSV.parseJSON(Data("{not a list".utf8)) }
}

@Test func wholeDictationSnippetsOnlyWhenThatIsAllYouSay() {
    let whole = Snippet(mode: .whole, trigger: "signature", text: "Kind regards,\nJo")
    let engine = SnippetEngine(SnippetLibrary([whole]))
    #expect(engine.expand("Signature.", language: "en").text == "Kind regards,\nJo")
    #expect(engine.expand("Add my signature here", language: "en").text == "Add my signature here")
}

@Test func anywhereSnippetsNeedTwoWords() throws {
    var library = SnippetLibrary()
    #expect(throws: SnippetError.anywhereNeedsTwoWords) { try library.add(Snippet(mode: .anywhere, trigger: "sig", text: "x")) }
    try library.add(Snippet(mode: .whole, trigger: "sig", text: "x")) // one word is fine for a whole dictation
    #expect(throws: SnippetError.tooLong) {
        try library.add(Snippet(mode: .whole, trigger: "long", text: String(repeating: "a", count: 4_001)))
    }
}

@Test func placeholdersAreFilledWhenUsed() {
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    let monday = utc.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 14, minute: 5))!
    let filled = SnippetEngine.fill("{day} {date} at {time}", now: monday, locale: Locale(identifier: "en_GB"))
    #expect(filled.hasPrefix("Monday 23 November 2026 at "))
    let snippet = Snippet(mode: .whole, trigger: "today", text: "Today is {day}.")
    #expect(SnippetEngine(SnippetLibrary([snippet])).expand("Today", language: "en", now: monday, locale: Locale(identifier: "en_GB")).text
            == "Today is Monday.")
}

@Test func snippetsReadTheWindowsCSVAndJSONRoundTrips() throws {
    let rows = try SnippetCSV.parse(Data("trigger,text,mode\nmy address,\"1 Main St,\nPune\",anywhere\nsig,Jo,whole\n".utf8))
    let snippets = try rows.map { try $0.result.get() }
    #expect(snippets.map(\.mode) == [.anywhere, .whole] && snippets[0].text == "1 Main St,\nPune")
    let back = try SnippetCSV.parseJSON(SnippetCSV.exportJSON(snippets)).map { try $0.result.get() }
    #expect(back.map(\.text) == snippets.map(\.text) && back.map(\.mode) == snippets.map(\.mode))
    #expect(try SnippetCSV.parse(SnippetCSV.export(snippets)).map { try $0.result.get().mode } == [.anywhere, .whole])
}

@Test func historyKeepsStatusEditsAndUpgradesOldFiles() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "hist-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    // An old-format file (before the "inserted" column) with one row.
    var db: OpaquePointer?
    sqlite3_open(url.path, &db)
    sqlite3_exec(db, """
        CREATE TABLE entries (id INTEGER PRIMARY KEY, created_at REAL NOT NULL, text TEXT NOT NULL, language TEXT NOT NULL,
        duration_ms INTEGER NOT NULL, model_id TEXT NOT NULL, app_bundle_id TEXT);
        INSERT INTO entries (created_at, text, language, duration_ms, model_id) VALUES (1, 'old one', 'en', 1000, 'small');
        """, nil, nil, nil)
    sqlite3_close(db)
    let store = try HistoryStore(url: url)
    #expect(try await store.entries().first?.inserted == true) // old rows count as typed
    let new = try await store.add(text: "copied", language: "en", durationMs: 1, modelID: "m", appBundleID: nil, inserted: false)
    #expect(try await store.entries().first { $0.id == new.id }?.inserted == false)
    try await store.setInserted(id: new.id, true)
    try await store.update(id: new.id, text: "edited")
    let entry = try await store.entries().first { $0.id == new.id }
    #expect(entry?.inserted == true && entry?.text == "edited")
    let csv = String(decoding: HistoryExport.csv(try await store.entries(), appName: { _ in nil }), as: UTF8.self)
    #expect(csv.contains("\"edited\"") && csv.contains("\"inserted\""))
}

@Test func notesMigrateTheOldScratchpadAndHaveTitles() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try "Draft for the scratch pad.\nSecond line".write(to: folder.appending(path: "scratchpad.txt"), atomically: true, encoding: .utf8)
    let store = NotesStore(url: folder.appending(path: "notes.json"), legacy: folder.appending(path: "scratchpad.txt"))
    let notes = store.load()
    #expect(notes.count == 1 && notes[0].title == "Draft for the scratch pad." && notes[0].words == 7)
    #expect(store.load().count == 1) // migrated once, not again
    #expect(Note(text: "").title == "New note")
}
