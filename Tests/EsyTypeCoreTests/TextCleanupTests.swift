import Testing
@testable import EsyTypeCore

// Simulated: made-up transcripts. Real dictation is in Documentation/STAGE_4_TEST_REPORT.md.
private let all = CleanupOptions()
private func clean(_ text: String, _ options: CleanupOptions = CleanupOptions(), _ language: String = "en") -> String {
    TextCleanup.clean(text, options: options, language: language)
}

@Test(arguments: [
    (" Hello world. ", true, "Hello world."),
    ("[BLANK_AUDIO]", true, ""),
    ("Hello [Music] there", true, "Hello there"),
    ("Um, so I think, uh, we should go.", true, "So I think, we should go."),
    ("Um, so I think, uh, we should go.", false, "Um, so I think, uh, we should go."),
    ("Hmm. Erm the plan is fine", true, "The plan is fine"),
    ("The umbrella and the hummus are here, umm.", true, "The umbrella and the hummus are here."),
    ("मुझे कल फ़ोन करना", true, "मुझे कल फ़ोन करना"),
    ("uh", true, ""),
] as [(String, Bool, String)])
func cleansText(input: String, fillers: Bool, expected: String) {
    #expect(clean(input, CleanupOptions(fillers: fillers)) == expected)
}

@Test func fillersOnlyWhereSafe() {
    #expect(clean("Uh-oh, the build broke.") == "Uh-oh, the build broke.")
    #expect(clean("I hmm think so.") == "I hmm think so.") // not set off: could be meant
    #expect(clean("Okay, hmm, let me check.") == "Okay, let me check.")
    #expect(clean("Summer drums are erm loud.") == "Summer drums are loud.")
    #expect(clean("उम्मीद है", all, "hi") == "उम्मीद है")
}

@Test func repeatedWordsButNotOnPurpose() {
    #expect(clean("I I think the the cat is here.") == "I think the cat is here.")
    #expect(clean("It was very very good.") == "It was very very good.")
    #expect(clean("He had had enough.") == "He had had enough.")
    #expect(clean("Bye bye.") == "Bye bye.")
    #expect(clean("No no no, not that.") == "No no no, not that.")
    #expect(clean("Call 4 4 2 now.") == "Call 4 4 2 now.")
    #expect(clean("धीरे धीरे चलो", all, "hi") == "धीरे धीरे चलो") // reduplication is grammar in Hindi
    #expect(clean("I I think.", CleanupOptions(repeatedWords: false)) == "I I think.")
}

@Test func repeatedPhrasesButNotEcho() {
    #expect(clean("I think, I think we should go.") == "I think we should go.")
    #expect(clean("We need to, we need to finish this today.") == "We need to finish this today.")
    #expect(clean("Never give up, never give up.") == "Never give up, never give up.") // an echo ends the sentence
    #expect(clean("Step by step we got there.") == "Step by step we got there.")
    #expect(clean("I think, I think we should go.", CleanupOptions(repeatedPhrases: false)) == "I think, I think we should go.")
}

@Test func punctuationAndSpacing() {
    #expect(clean("Hello , world .  How are you ?") == "Hello, world. How are you?")
    #expect(clean("Wait,,  what..") == "Wait, what.")
    #expect(clean("Really?. Yes,.") == "Really? Yes.")
    #expect(clean("Well...really?! Wow!!") == "Well...really?! Wow!!")
    #expect(clean("first,second;third") == "First, second; third")
    #expect(clean("It ended.Next one") == "It ended. Next one")
    #expect(clean("go to the meeting .see you at www.esyai.co.uk ,ok?") == "Go to the meeting. See you at www.esyai.co.uk, ok?") // found in the real preview
    #expect(clean("Para one.  \n\n\n\n  para two.") == "Para one.\n\nPara two.")
    #expect(clean("Line one\nline two") == "Line one\nLine two")
    #expect(clean("मैं ठीक हूँ ।वह भी", all, "hi") == "मैं ठीक हूँ। वह भी")
    #expect(clean("Hello , world .", CleanupOptions(punctuation: false)) == "Hello , world .")
}

@Test func capitalisationKeepsNamesAcronymsAndCode() {
    #expect(clean("hello. how are you? fine! ok") == "Hello. How are you? Fine! Ok")
    #expect(clean("iPhone and macOS work. iPad too.") == "iPhone and macOS work. iPad too.")
    #expect(clean("The NASA team met IBM.") == "The NASA team met IBM.")
    #expect(clean("i think i'm right, and i.e. so") == "I think I'm right, and i.e. so")
    #expect(clean("Use a fork, e.g. this one. etc. and more") == "Use a fork, e.g. this one. etc. and more")
    #expect(clean("hello", CleanupOptions(capitalisation: false)) == "hello")
}

@Test func neverTouchesLinksEmailsCodeOrNumbers() {
    #expect(clean("visit https://example.com/a_b?x=1,y=2 now.") == "Visit https://example.com/a_b?x=1,y=2 now.")
    #expect(clean("Mail me at priya.sharma@example.co.in, ok?") == "Mail me at priya.sharma@example.co.in, ok?")
    #expect(clean("Open src/main.swift and call snake_case_name() now.") == "Open src/main.swift and call snake_case_name() now.")
    #expect(clean("Pi is 3.14 and v2.0.1 shipped.") == "Pi is 3.14 and v2.0.1 shipped.")
    #expect(clean("see example.com.") == "See example.com.")
    #expect(clean("www.example.com www.example.com is the site") == "Www.example.com www.example.com is the site".replacingOccurrences(of: "Www", with: "www"))
}

@Test func everythingOffOnlyStripsMarkers() {
    // The marker's gap is closed; fillers, repeats and punctuation stay as Whisper wrote them.
    #expect(clean(" um [BLANK_AUDIO] the the  , x ", .none) == "um the the , x")
}

@Test func spacesAfterPreviousText() {
    #expect(TextCleanup.spaced("Please send it.", after: ".") == " Please send it.")
    #expect(TextCleanup.spaced("Hello", after: "d") == " Hello")
    #expect(TextCleanup.spaced("Hello", after: " ") == "Hello")
    #expect(TextCleanup.spaced("Hello", after: "\n") == "Hello")
    #expect(TextCleanup.spaced("Hello", after: nil) == "Hello") // start of field, or the app doesn't say
    #expect(TextCleanup.spaced("Hello", after: "(") == "Hello")
    #expect(TextCleanup.spaced(", and more", after: "d") == ", and more")
}
