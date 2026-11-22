import EsyTypeCore
import SwiftUI

/// Text Cleanup: the rules EsyType applies to every transcript, each with its own switch, and a live preview.
struct TextCleanupView: View {
    @AppStorage(Pref.removeFillers) private var fillers = true
    @AppStorage(Pref.cleanRepeatedWords) private var repeatedWords = true
    @AppStorage(Pref.cleanRepeatedPhrases) private var repeatedPhrases = true
    @AppStorage(Pref.cleanPunctuation) private var punctuation = true
    @AppStorage(Pref.cleanCapitalisation) private var capitalisation = true
    @State private var sample = "um, so i think, i think we should go to the the meeting .see https://example.com/a_b ,ok?"
    @State private var sampleLanguage = "en"

    private var options: CleanupOptions {
        CleanupOptions(fillers: fillers, repeatedWords: repeatedWords, repeatedPhrases: repeatedPhrases,
                       punctuation: punctuation, capitalisation: capitalisation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Text Cleanup").font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader)
            Text("Fixed rules tidy what Whisper writes before it’s typed. They remove noise and fix layout; they never reword what you said. Everything runs on this Mac.")
                .font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Section("Rules") {
                    rule("Remove filler words", "“um, uh, erm”, and “hmm” on its own → removed. English only.", $fillers)
                    rule("Remove repeated words", "“the the cat” → “the cat”. Keeps “very very”, “bye bye.”, numbers. English only.", $repeatedWords)
                    rule("Remove repeated phrases", "“I think, I think we should go” → “I think we should go”. Keeps echoes like “never give up, never give up.” English only.", $repeatedPhrases)
                    rule("Fix punctuation and spacing", "“Hello , world .How” → “Hello, world. How”. Keeps “...”, “?!”, paragraphs and line breaks.", $punctuation)
                    rule("Capitalise sentences", "“hello. how are you” → “Hello. How are you”. Leaves iPhone, NASA and “e.g.” alone; never lowercases.", $capitalisation)
                }
                Section("Always on") {
                    Text("Removes Whisper’s markers such as [BLANK_AUDIO], and closes the gaps that removals leave.").font(.esy(12))
                    Text("Never changes web addresses, emails, file paths, code names (snake_case, main.swift) or numbers like 3.14.").font(.esy(12))
                }
                Section("Try it") {
                    TextEditor(text: $sample).font(.esy(13)).frame(height: 60).accessibilityLabel("Text to clean")
                    Picker("Language", selection: $sampleLanguage) {
                        Text("English").tag("en")
                        Text("Hindi").tag("hi")
                        Text("Marathi").tag("mr")
                    }
                    LabeledContent("Result") {
                        Text(TextCleanup.clean(sample, options: options, language: sampleLanguage))
                            .font(.esy(13, .medium)).textSelection(.enabled).multilineTextAlignment(.trailing)
                    }
                }
                Section("Planned, not available yet") {
                    Text("Spoken commands such as “new line” or “comma”, numbers written as digits, and styles per app. These aren’t built.")
                        .font(.esy(12)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).fixedSize(horizontal: false, vertical: true).padding(.horizontal, -20)
            Text("Order for every dictation: Whisper → cleanup → Personal Dictionary → Snippets → typed. Snippet text is typed exactly as saved.")
                .font(.esy(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rule(_ title: String, _ example: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.esy(13))
                Text(example).font(.esy(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
