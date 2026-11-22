import EsyTypeCore
import Foundation
import Testing

// All Simulated: made-up snippets and transcripts. Real dictation is in Documentation/STAGE_3_TEST_REPORT.md.

private let signature = Snippet(name: "Signature", trigger: "my email signature", text: "Best regards,\nPriya Sharma\nEsyAI")
private func expand(_ snippets: [Snippet], _ text: String, _ language: String = "en") -> String {
    SnippetEngine(SnippetLibrary(snippets)).expand(text, language: language).text
}

@Test func createEditDeleteEnableWithDates() throws {
    let t0 = Date(timeIntervalSince1970: 1_000), t1 = Date(timeIntervalSince1970: 2_000)
    var library = SnippetLibrary()
    try library.add(signature, now: t0)
    #expect(library.snippets.first?.created == t0 && library.snippets.first?.modified == t0)
    var edited = library.snippets[0]
    edited.text = "Thanks,\nPriya"
    try library.update(edited, now: t1)
    #expect(library.snippets[0].text == "Thanks,\nPriya" && library.snippets[0].created == t0 && library.snippets[0].modified == t1)
    library.setEnabled(id: signature.id, false)
    #expect(library.activeCount == 0)
    library.delete(id: signature.id)
    #expect(library.snippets.isEmpty)
}

@Test func validatesAndRefusesDuplicateTriggers() throws {
    var library = SnippetLibrary()
    #expect(throws: SnippetError.emptyTrigger) { try library.add(Snippet(trigger: " ", text: "x")) }
    #expect(throws: SnippetError.emptyText) { try library.add(Snippet(trigger: "a", text: "\n ")) }
    #expect(throws: SnippetError.multilineTrigger) { try library.add(Snippet(trigger: "a\nb", text: "x")) }
    try library.add(signature)
    #expect(library.snippets[0].name == "Signature")
    try library.add(Snippet(trigger: "my address", text: "1 Main St"))
    #expect(library.snippets[1].name == "my address") // no name: the trigger is used
    #expect(throws: SnippetError.duplicateTrigger(usedBy: "Signature")) {
        try library.add(Snippet(trigger: "My  Email Signature", text: "other"))
    }
    var renamed = library.snippets[1]
    renamed.trigger = "my email signature"
    #expect(throws: SnippetError.duplicateTrigger(usedBy: "Signature")) { try library.update(renamed) }
    // Another language is a different trigger.
    try library.add(Snippet(trigger: "my email signature", text: "धन्यवाद", language: "hi"))
}

@Test func searchAndFilters() throws {
    var library = SnippetLibrary()
    try library.add(Snippet(name: "Sig", trigger: "my email signature", text: "Best regards", category: "Email"))
    try library.add(Snippet(name: "पता", trigger: "मेरा पता", text: "पुणे", category: "Personal", language: "hi"))
    #expect(library.search("regards").map(\.name) == ["Sig"])
    #expect(library.search("पुणे").count == 1)
    #expect(library.search("", category: "Email").count == 1)
    #expect(library.search("", language: "hi").count == 1)
    #expect(library.categories == ["Email", "Personal"])
}

@Test func theBriefExampleKeepsPunctuationAndMultiLineText() {
    #expect(expand([signature], "Please send my email signature.") == "Please send Best regards,\nPriya Sharma\nEsyAI.")
    #expect(expand([signature], "My Email Signature, please") == "Best regards,\nPriya Sharma\nEsyAI, please")
}

@Test func wholeWordsOnlyAndNoAccidentalExpansion() {
    let addr = Snippet(trigger: "my address", text: "1 Main St")
    #expect(expand([addr], "my addresses are many") == "my addresses are many")
    #expect(expand([addr], "summy address") == "summy address")
    #expect(expand([addr], "this is my address book") == "this is 1 Main St book") // exact phrase only, as configured
}

@Test func longerTriggerWinsAndNothingRecurses() {
    let short = Snippet(trigger: "my address", text: "1 Main St")
    let long = Snippet(trigger: "my home address", text: "22 Home Rd, Pune")
    #expect(expand([short, long], "Send my home address and my address.") == "Send 22 Home Rd, Pune and 1 Main St.")
    let loop = Snippet(trigger: "sig", text: "sig sig")
    #expect(expand([loop], "sig") == "sig sig")
    let chain = [Snippet(trigger: "alpha", text: "beta"), Snippet(trigger: "beta", text: "gamma")]
    #expect(expand(chain, "alpha") == "beta") // a snippet's text never triggers another snippet
}

@Test func ambiguousTriggersNeverExpand() {
    let a = Snippet(name: "Work", trigger: "my signature", text: "Work sig")
    let b = Snippet(name: "Home", trigger: "My Signature", text: "Home sig")
    let library = SnippetLibrary([a, b]) // as a hand-edited file might hold
    #expect(library.ambiguous == [a.id, b.id])
    #expect(SnippetEngine(library).expand("add my signature", language: "en").text == "add my signature")
}

@Test func disabledAndOtherLanguageSnippetsDontExpand() {
    var off = signature
    off.enabled = false
    #expect(expand([off], "my email signature") == "my email signature")
    let hindiOnly = Snippet(trigger: "मेरा पता", text: "पुणे 411001", language: "hi")
    #expect(expand([hindiOnly], "मेरा पता", "mr") == "मेरा पता")
    #expect(expand([hindiOnly], "यह मेरा पता है।", "hi") == "यह पुणे 411001 है।")
    let marathi = Snippet(trigger: "माझा पत्ता", text: "पुणे, महाराष्ट्र", language: "mr")
    #expect(expand([marathi], "माझा पत्ता लिहा", "mr") == "पुणे, महाराष्ट्र लिहा")
    #expect(expand([signature], "") == "")
}

@Test func dictionaryRunsFirstAndNeverTouchesSnippetText() {
    // The dictionary fixes Whisper's spelling of the trigger; the snippet's text then stays exactly as saved.
    let dictionary = DictionaryEngine(PersonalDictionary([
        DictionaryEntry(spoken: "e mail", replacement: "email"),
        DictionaryEntry(spoken: "regards", replacement: "REGARDS"),
    ]))
    let snippets = SnippetEngine(SnippetLibrary([signature]))
    let fixed = dictionary.apply(to: "Add my e mail signature.", language: "en").text
    #expect(fixed == "Add my email signature.")
    #expect(snippets.expand(fixed, language: "en").text == "Add Best regards,\nPriya Sharma\nEsyAI.")
}

@Test func snippetCSVRoundTripKeepsEverythingIncludingDates() throws {
    let created = Date(timeIntervalSince1970: 1_700_000_000.25)
    let snippets = [
        Snippet(name: "Sig, \"work\"", trigger: "my email signature", text: "Best,\n\"Priya\"\n=EsyAI", category: "Email",
                created: created, modified: created.addingTimeInterval(60)),
        Snippet(name: "पता", trigger: "मेरा पता", text: "पुणे, महाराष्ट्र", category: "Personal", language: "hi", enabled: false,
                created: created),
    ]
    let rows = try SnippetCSV.parse(SnippetCSV.export(snippets))
    let back = try rows.map { try $0.result.get() }
    for (a, b) in zip(snippets, back) {
        #expect(a.name == b.name && a.trigger == b.trigger && a.text == b.text && a.category == b.category)
        #expect(a.language == b.language && a.enabled == b.enabled)
        #expect(abs(a.created.timeIntervalSince(b.created)) < 0.001 && abs(a.modified.timeIntervalSince(b.modified)) < 0.001)
    }
}

@Test func snippetImportPreviewAndValidation() throws {
    var library = SnippetLibrary()
    try library.add(signature)
    let rows = try SnippetCSV.parse(Data("""
    trigger_phrase,replacement_text,name,enabled
    my email signature,"Best regards,\nPriya Sharma\nEsyAI",Signature,true
    my email signature,Changed,Signature,true
    my address,1 Main St,,true
    my address,1 Main St,,true
    my address,2 Other St,,true
    ,no trigger,,true
    x,y,,perhaps
    """.utf8))
    let plan = library.plan(rows)
    #expect(plan.skipped == 2) // identical signature, and the identical second address
    #expect(plan.rejected.map(\.line) == [5, 8, 9, 10]) // line numbers count the 3-line value; conflicting signature row, conflicting address, no trigger, bad enabled
    #expect(plan.additions.map(\.trigger) == ["my address"])
    #expect(plan.updates.isEmpty)
    #expect(throws: CSVFile.FileError.missingColumns(["replacement_text"])) {
        try SnippetCSV.parse(Data("trigger_phrase,name\na,b".utf8))
    }
}

@Test func snippetStorePersists() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "snip-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = SnippetStore(url: folder.appending(path: "snippets.json"))
    try store.save(SnippetLibrary([signature]))
    let loaded = store.load().library.snippets
    #expect(loaded.map(\.text) == [signature.text] && loaded.first?.id == signature.id)
    #expect(abs((loaded.first?.created.timeIntervalSince(signature.created)) ?? 99) < 1)
    #expect((try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int) == 0o600)
}
