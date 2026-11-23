import EsyTypeCore
import Foundation
import Testing

// All Simulated: made-up dictionaries and transcripts. Real dictation is in Documentation/STAGE_2_TEST_REPORT.md.

private func dict(_ entries: [DictionaryEntry]) -> DictionaryEngine { DictionaryEngine(PersonalDictionary(entries)) }
private func apply(_ entries: [DictionaryEntry], _ text: String, _ language: String = "en") -> String {
    dict(entries).apply(to: text, language: language).text
}
private let esy = DictionaryEntry(spoken: "esy type", replacement: "EsyType", category: "Brand")
private let openAI = DictionaryEntry(spoken: "open ai", replacement: "OpenAI", category: "Brand")

// MARK: Managing entries

@Test func addEditDeleteEnableAndCount() throws {
    var d = PersonalDictionary()
    try d.add(esy)
    try d.add(openAI)
    #expect(d.entries.count == 2 && d.activeCount == 2)
    var edited = esy
    edited.replacement = "EsyType™"
    try d.update(edited)
    #expect(d.entries.first?.replacement == "EsyType™")
    d.setEnabled(id: openAI.id, false)
    #expect(d.activeCount == 1)
    d.delete(id: esy.id)
    #expect(d.entries.map(\.id) == [openAI.id])
}

@Test func rejectsInvalidAndDuplicateEntries() throws {
    var d = PersonalDictionary()
    #expect(throws: DictionaryError.emptyField) { try d.add(DictionaryEntry(spoken: "  ", replacement: "x")) }
    #expect(throws: DictionaryError.badLanguage) { try d.add(DictionaryEntry(spoken: "a", replacement: "b", language: "English")) }
    #expect(throws: DictionaryError.multiline) { try d.add(DictionaryEntry(spoken: "a\nb", replacement: "c")) }
    try d.add(esy)
    // Same words in another case and spacing, same replacement: a duplicate.
    #expect(throws: DictionaryError.duplicate) { try d.add(DictionaryEntry(spoken: "Esy   Type", replacement: "EsyType")) }
}

@Test func searchesAndFilters() throws {
    var d = PersonalDictionary()
    try d.add(esy)
    try d.add(DictionaryEntry(spoken: "प्रिया", replacement: "Priya", language: "hi", category: "Name"))
    #expect(d.search("esy").map(\.replacement) == ["EsyType"])
    #expect(d.search("priya").count == 1)
    #expect(d.search("", category: "Name").count == 1)
    #expect(d.search("", language: "hi").count == 1)
    #expect(d.search("", language: "").count == 1) // "any language" entries
    #expect(d.categories == ["Brand", "Name"])
}

@Test func conflictsAreReportedAndTheEarlierEntryWins() throws {
    var d = PersonalDictionary()
    try d.add(DictionaryEntry(spoken: "jay", replacement: "Jay"))
    let later = DictionaryEntry(spoken: "Jay", replacement: "J.")
    try d.add(later) // allowed, but reported
    #expect(d.conflicts[later.id]?.replacement == "Jay")
    #expect(DictionaryEngine(d).apply(to: "ask jay", language: "en").text == "ask Jay")
}

// MARK: Matching

@Test func theBriefExample() {
    #expect(apply([esy, openAI], "I am developing esy type using open ai.") == "I am developing EsyType using OpenAI.")
}

@Test func caseInsensitiveAndPunctuationAndWhitespaceKept() {
    #expect(apply([esy], "Esy Type, rocks!") == "EsyType, rocks!")
    #expect(apply([esy], "  (esy\u{00A0}type)  ") == "  (EsyType)  ")
    #expect(apply([esy], "\"esy type\".") == "\"EsyType\".")
    #expect(apply([esy], "esy\ntype") == "EsyType")
}

@Test func onlyWholeWords() {
    let ai = DictionaryEntry(spoken: "ai", replacement: "AI")
    #expect(apply([ai], "she said ai is fair") == "she said AI is fair")
    #expect(apply([ai], "aim, wait, ai2, x_ai") == "aim, wait, ai2, x_ai")
}

@Test func overlappingPhrasesLongestFirstAndNoRepeats() {
    let studio = DictionaryEntry(spoken: "open ai studio", replacement: "OpenAI Studio")
    #expect(apply([openAI, studio], "open ai studio and open ai") == "OpenAI Studio and OpenAI")
    // A replacement that contains its own spoken text is applied once, never again on its output.
    let loop = DictionaryEntry(spoken: "type", replacement: "type type")
    #expect(apply([loop], "type") == "type type")
    #expect(apply([openAI], "open ai open ai open ai") == "OpenAI OpenAI OpenAI")
    #expect(dict([openAI]).apply(to: "open ai, open ai", language: "en").replacements == 2)
}

@Test func languageSpecificEntriesWinAndOthersAreIgnored() {
    let any = DictionaryEntry(spoken: "pune", replacement: "Pune")
    let marathi = DictionaryEntry(spoken: "पुणे", replacement: "पुणे शहर", language: "mr")
    let english = DictionaryEntry(spoken: "pune", replacement: "PUNE", language: "en")
    #expect(apply([any, english], "in pune", "en") == "in PUNE")
    #expect(apply([any, english], "in pune", "fr") == "in Pune")
    #expect(apply([marathi], "मी पुणे येथे", "hi") == "मी पुणे येथे") // Marathi rule, Hindi transcript
    #expect(apply([marathi], "मी पुणे येथे", "mr") == "मी पुणे शहर येथे")
}

@Test func hindiAndMarathiWithWordBoundaries() {
    let hi = DictionaryEntry(spoken: "ईज़ी टाइप", replacement: "EsyType", language: "hi")
    #expect(apply([hi], "मैं ईज़ी टाइप का परीक्षण कर रहा हूँ।", "hi") == "मैं EsyType का परीक्षण कर रहा हूँ।")
    // A matra or virama attached to the word means it's a different word: no replacement inside it.
    let ram = DictionaryEntry(spoken: "राम", replacement: "Ram")
    #expect(apply([ram], "रामायण और राम", "hi") == "रामायण और Ram")
    // Composed and decomposed nukta are the same text.
    let decomposed = DictionaryEntry(spoken: "आवाज\u{093C}", replacement: "voice")
    #expect(apply([decomposed], "मेरी आवाज़ सुनो", "hi") == "मेरी voice सुनो")
}

@Test func emptyAndNoRulesAreHarmless() {
    #expect(apply([esy], "") == "")
    #expect(apply([], "esy type") == "esy type")
    var off = esy
    off.enabled = false
    #expect(apply([off], "esy type") == "esy type")
    #expect(apply([DictionaryEntry(spoken: "c++ (v2)", replacement: "C++ v2")], "use c++ (v2) now") == "use C++ v2 now")
}

@Test func hintsAreShortLanguageAwareAndPunctuated() {
    let hi = DictionaryEntry(spoken: "प्रिया", replacement: "प्रिया", language: "hi")
    let engine = dict([esy, openAI, hi])
    #expect(engine.hints(language: nil) == ["EsyType", "OpenAI"]) // auto-detect: no Devanagari hints
    #expect(engine.hints(language: "hi") == ["EsyType", "OpenAI", "प्रिया"])
    #expect(engine.prompt(language: nil) == TextCleanup.whisperPrompt + " EsyType, OpenAI.")
    #expect(dict([]).prompt(language: nil) == TextCleanup.whisperPrompt)
    let many = (0..<50).map { DictionaryEntry(spoken: "word \($0)", replacement: "Word\($0)") }
    #expect(dict(many).hints(language: "en").count == DictionaryEngine.maxHints)
}

// MARK: CSV

private func csv(_ text: String) throws -> [DictionaryCSV.Row] { try DictionaryCSV.parse(Data(text.utf8)) }

@Test func importsValidCSVWithQuotesCommasAndUnicode() throws {
    let rows = try csv(#"""
    \#u{FEFF}recognised_text,replacement_text,language,category,enabled,description
    open ai,OpenAI,en,Brand,true,"The company, not the phrase"
    "say ""hi""","Say ""Hi""",,Other,false,
    ईज़ी टाइप,EsyType,hi,Brand,yes,"multi
    line note"
    इझी टाइप,EsyType,mr,Brand,1,
    """#)
    let entries = rows.compactMap { try? $0.result.get() }
    #expect(entries.count == 4)
    #expect(entries[0].note == "The company, not the phrase")
    #expect(entries[1].spoken == "say \"hi\"" && entries[1].replacement == "Say \"Hi\"" && !entries[1].enabled)
    #expect(entries[2].spoken == "ईज़ी टाइप" && entries[2].note == "multi\nline note")
    #expect(rows.map(\.line) == [2, 3, 4, 6])
}

@Test func rejectsBadFilesAndBadRowsWithReasons() throws {
    #expect(throws: DictionaryCSV.FileError.notUTF8) { try DictionaryCSV.parse(Data([0xFF, 0xFE, 0x00, 0xD8])) }
    #expect(throws: DictionaryCSV.FileError.empty) { try csv("") }
    // Language, category and enabled are optional (the Windows CSV has only kind, term, replacement);
    // the spoken term is what must be there.
    #expect(throws: DictionaryCSV.FileError.missingColumns(["recognised_text"])) {
        try csv("word,replacement_text\na,b")
    }
    #expect(throws: DictionaryCSV.FileError.unterminatedQuote(line: 2)) {
        try csv("recognised_text,replacement_text,language,category,enabled\n\"a,b,en,x,true")
    }
    let rows = try csv("""
    recognised_text,replacement_text,language,category,enabled
    a,b,en,x,maybe
    ,b,en,x,true
    a,b,English,x,true
    a,b,en
    """)
    #expect(rows.allSatisfy { if case .failure = $0.result { true } else { false } })
    #expect(rows.count == 4)
}

@Test func exportThenImportKeepsEverything() throws {
    let tricky = [
        DictionaryEntry(spoken: "open ai", replacement: "OpenAI", language: "en", category: "Brand", note: "comma, \"quote\"\nnewline"),
        DictionaryEntry(spoken: "प्रिया", replacement: "प्रिया शर्मा", language: "hi", category: "Name", enabled: false),
        DictionaryEntry(spoken: "plus one", replacement: "+1", category: "=Formula?", note: "@mention"),
    ]
    let data = DictionaryCSV.export(tricky)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.hasPrefix("\u{FEFF}\"kind\",\"recognised_text\""))
    #expect(text.contains("\"'+1\"") && text.contains("\"'=Formula?\"")) // never a live spreadsheet formula
    let back = try DictionaryCSV.parse(data).map { try $0.result.get() }
    #expect(back.map(\.spoken) == tricky.map(\.spoken))
    #expect(back.map(\.replacement) == tricky.map(\.replacement))
    #expect(back.map(\.category) == tricky.map(\.category))
    #expect(back.map(\.note) == tricky.map(\.note))
    #expect(back.map(\.enabled) == tricky.map(\.enabled))
    #expect(back.map(\.language) == tricky.map(\.language))
}

@Test func importPlanReportsAddUpdateSkipAndRejectWithoutOverwriting() throws {
    var d = PersonalDictionary()
    try d.add(esy)
    try d.add(openAI)
    let rows = try csv("""
    recognised_text,replacement_text,language,category,enabled
    esy type,EsyType,,Brand,true
    open ai,Open AI,,Brand,true
    git hub,GitHub,,Brand,true
    git hub,GitHub,,Brand,true
    git hub,Github,,Brand,true
    ,x,,,true
    """)
    let plan = d.plan(rows)
    #expect(plan.additions.map(\.replacement) == ["GitHub"])
    #expect(plan.updates.map(\.replacement) == ["Open AI"])
    #expect(plan.skipped == 2) // the existing esy type, and the identical second git hub
    #expect(plan.rejected.map(\.line) == [6, 7]) // conflicting git hub, empty text
    var kept = d
    kept.apply(plan, updateExisting: false)
    #expect(kept.entries.count == 3 && kept.entries.first { $0.id == openAI.id }?.replacement == "OpenAI")
    d.apply(plan, updateExisting: true)
    #expect(d.entries.first { $0.id == openAI.id }?.replacement == "Open AI")
}

// MARK: Storage

@Test func storeRoundTripsAndSetsAside_aDamagedFile() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "dict-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DictionaryStore(url: folder.appending(path: "dictionary.json"))
    #expect(store.load().dictionary.entries.isEmpty)
    try store.save(PersonalDictionary([esy, DictionaryEntry(spoken: "प्रिया", replacement: "Priya", language: "hi")]))
    #expect(store.load().dictionary.entries.map(\.replacement) == ["EsyType", "Priya"])
    let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
    try Data("{not json".utf8).write(to: store.url)
    let (loaded, recovered) = store.load()
    #expect(loaded.entries.isEmpty && recovered)
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(files.contains { $0.hasPrefix("dictionary.damaged-") }, "the damaged file is kept, not deleted")
}

@Test func theSampleTemplateImportsCleanly() throws {
    let rows = try DictionaryCSV.parse(DictionaryCSV.export(DictionaryCSV.sampleEntries))
    let plan = PersonalDictionary().plan(rows)
    #expect(plan.rejected.isEmpty && plan.additions.count == DictionaryCSV.sampleEntries.count)
    #expect(plan.additions.allSatisfy { $0.note.hasPrefix("SAMPLE") })
    #expect(Set(plan.additions.map(\.language)) == ["", "en", "hi", "mr"])
}

// MARK: Stage-6 parity with Windows

@Test func wordsAreSpelledAsEnteredEvenWhenSplit() throws {
    var d = PersonalDictionary()
    try d.add(DictionaryEntry(kind: .word, spoken: "EsyType", replacement: "ignored"))
    #expect(d.entries[0].replacement == "EsyType")
    let engine = DictionaryEngine(d)
    #expect(engine.apply(to: "I use esytype and Esy Type daily", language: "en").text == "I use EsyType and EsyType daily")
}

@Test func builtInNamesOnlyWhenSwitchedOnAndYoursWin() throws {
    #expect(DictionaryEngine(PersonalDictionary()).apply(to: "ask chat gpt", language: "en").text == "ask chat gpt")
    #expect(DictionaryEngine(PersonalDictionary(), builtIns: true).apply(to: "ask chat gpt about superbase", language: "en").text
            == "ask ChatGPT about Supabase")
    let mine = PersonalDictionary([DictionaryEntry(spoken: "chat gpt", replacement: "Chat-GPT")])
    #expect(DictionaryEngine(mine, builtIns: true).apply(to: "ask chat gpt", language: "en").text == "ask Chat-GPT")
    #expect(BuiltInNames.names.count >= 25)
}

@Test func hintsCanBeSwitchedOff() {
    let d = PersonalDictionary([DictionaryEntry(spoken: "open ai", replacement: "OpenAI")])
    #expect(DictionaryEngine(d, hints: false).prompt(language: nil) == TextCleanup.whisperPrompt)
    #expect(DictionaryEngine(d, hints: true).prompt(language: nil).hasSuffix("OpenAI."))
}

@Test func oldSavedEntriesWithoutKindStillLoad() throws {
    let json = #"{"id":"8A4A9FCF-30C2-49F4-A178-C02420BC54F2","spoken":"project falcon","replacement":"Project FALCON-9","language":"en","category":"Brand","enabled":true,"note":""}"#
    let entry = try JSONDecoder().decode(DictionaryEntry.self, from: Data(json.utf8))
    #expect(entry.kind == .correction && entry.replacement == "Project FALCON-9")
}
