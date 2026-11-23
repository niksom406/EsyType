import EsyTypeCore
import SwiftUI
import UniformTypeIdentifiers
import WhisperEngine

/// Main window ▸ Snippets: say a trigger and EsyType types the saved text.
struct SnippetsView: View {
    let model: SnippetModel
    @State private var trigger = ""
    @State private var text = ""
    @State private var mode = Snippet.Mode.whole
    @State private var query = ""
    @State private var editing: Snippet?
    @State private var deleting: Snippet?
    @State private var confirmDeleteAll = false
    @State private var importing: ImportPlan<Snippet>?
    @State private var status: (text: String, file: URL?)?
    @FocusState private var triggerFocused: Bool

    private var library: SnippetLibrary { model.library }
    private var shown: [Snippet] { library.search(query).reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle("Snippets")
            PageHero("snippets", headline: Text("Say a few words, ") + Text("type").italic() + Text(" the rest."),
                     message: "Your signature, address, meeting link or standard reply, typed in full when you say its trigger.",
                     glow: Color(hex: 0x27669A)) {
                HeroButton("New snippet") { triggerFocused = true }
                HeroChip("my email signature") { trigger = "my email signature"; mode = .anywhere; triggerFocused = true }
                HeroChip("{date}") { text += "{date}" }
            }
            addCard
            listCard
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet, categories: library.categories) { edited in model.change { try $0.update(edited) } }
        }
        .sheet(item: $importing) { plan in
            ImportPreview(plan: plan, title: "Import snippets") { updateExisting in
                let error = model.change { $0.apply(plan, updateExisting: updateExisting) }
                status = (error ?? "Imported \(plan.additions.count) new \(plan.additions.count == 1 ? "snippet" : "snippets").", nil)
                importing = nil
            } cancel: { importing = nil }
        }
        .confirmationDialog("Delete the snippet “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let id = deleting?.id { model.change { $0.delete(id: id) } } }
        }
        .confirmationDialog("Delete all your snippets?", isPresented: $confirmDeleteAll) {
            Button("Delete All \(library.snippets.count)", role: .destructive) {
                model.change { library in library.snippets.map(\.id).forEach { library.delete(id: $0) } }
            }
        } message: { Text("Export them first if you might want them back. This can’t be undone.") }
    }

    // MARK: Add

    private var addCard: some View {
        SectionCard("Add a snippet") {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("When I say")
                RoundedField(prompt: "my email signature", text: $trigger).focused($triggerFocused)
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Insert (\(text.count) of \(SnippetLibrary.maxText) characters)")
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text).font(.esy(15)).scrollContentBackground(.hidden).padding(10)
                        .accessibilityLabel("Text to insert")
                    if text.isEmpty {
                        Text("Kind regards,\nJo Smith").font(.esy(15)).foregroundStyle(Brand.inkTertiary)
                            .padding(.horizontal, 15).padding(.vertical, 10).allowsHitTesting(false)
                    }
                }
                .frame(height: 130)
                .background(Brand.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(text.count > SnippetLibrary.maxText ? Brand.recording : Brand.hairlineStrong))
            }
            HStack(spacing: 8) {
                Text("Add:").font(.esy(13)).foregroundStyle(Brand.inkTertiary)
                ForEach(["{date}", "{time}", "{day}"], id: \.self) { token in
                    PillButton(title: token) { text += token }
                }
            }
            ModeChoice(mode: $mode)
            HStack(spacing: 12) {
                AccentButton(title: "Add snippet", enabled: !trigger.trimmingCharacters(in: .whitespaces).isEmpty && !text.isEmpty, action: add)
                if let status { StatusLine(text: status.text, file: status.file) }
            }
            Text("Say the trigger and EsyType types the text exactly as written, line breaks included. {date}, {time} and {day} are filled in when the snippet is used.")
                .font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func add() {
        let snippet = Snippet(mode: mode, trigger: trigger, text: text)
        if let error = model.change({ try $0.add(snippet) }) {
            status = (error, nil)
        } else {
            status = ("Added “\(snippet.trigger)”.", nil)
            trigger = ""
            text = ""
        }
    }

    // MARK: List

    private var listCard: some View {
        SectionCard(title: "Your snippets", count: library.snippets.count) {
            PillButton(title: "Import", systemImage: "square.and.arrow.down", action: importFile)
            PillButton(title: "CSV", systemImage: "square.and.arrow.up") { export(SnippetCSV.export(library.snippets), "csv") }
                .disabled(library.snippets.isEmpty)
            PillButton(title: "JSON", systemImage: "square.and.arrow.up") { export(SnippetCSV.exportJSON(library.snippets), "json") }
                .disabled(library.snippets.isEmpty)
            PillButton(title: "Delete all", danger: true) { confirmDeleteAll = true }.disabled(library.snippets.isEmpty)
        } content: {
            if library.snippets.isEmpty {
                EmptyList(symbol: "text.badge.plus", title: "No snippets yet",
                          message: "Try your email signature, address or a meeting link.", action: "Add a snippet") { triggerFocused = true }
            } else {
                SearchField(prompt: "Search your snippets", text: $query)
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, snippet in
                        if index > 0 { Rectangle().fill(Brand.hairline).frame(height: 1) }
                        SnippetRow(snippet: snippet, ambiguous: library.ambiguous.contains(snippet.id),
                                   toggle: { on in model.change { $0.setEnabled(id: snippet.id, on) } },
                                   edit: { editing = snippet }, delete: { deleting = snippet })
                    }
                    if shown.isEmpty { Text("No snippets match “\(query)”.").font(.esy(13)).foregroundStyle(Brand.inkTertiary).padding(16) }
                }
                .background(Brand.surfaceRaised.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.hairline))
            }
            Text("Import reads CSV (trigger, text and optionally mode, or EsyType’s own columns) or JSON. Exports go to your Downloads folder.")
                .font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func importFile() {
        do {
            guard let data = try CSVPanels.open(message: "Choose a snippets CSV or JSON file.", types: [.commaSeparatedText, .json, .plainText])
            else { return }
            let isJSON = data.first(where: { !" \n\r\t\u{FEFF}".utf8.contains($0) }) == UInt8(ascii: "[")
            importing = library.plan(try isJSON ? SnippetCSV.parseJSON(data) : SnippetCSV.parse(data))
        } catch {
            status = ("Couldn’t import: \(error.localizedDescription)", nil)
        }
    }

    private func export(_ data: Data, _ ext: String) {
        if let url = Downloads.save(data, name: "EsyType Snippets", extension: ext) {
            status = ("Saved \(url.lastPathComponent) to Downloads.", url)
        } else { status = ("Couldn’t save to Downloads.", nil) }
    }
}

/// Whole dictation or anywhere, as two radio rows.
private struct ModeChoice: View {
    @Binding var mode: Snippet.Mode

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { options }
            VStack(alignment: .leading, spacing: 10) { options }
        }
    }

    @ViewBuilder private var options: some View {
        option(.whole, "Whole dictation", "only when I say just the trigger")
        option(.anywhere, "Anywhere", "wherever I say it in a sentence (two words or more)")
    }

    private func option(_ value: Snippet.Mode, _ title: String, _ detail: String) -> some View {
        Button { mode = value } label: {
            HStack(spacing: 8) {
                Image(systemName: mode == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(mode == value ? Brand.accent : Brand.inkTertiary)
                (Text(title).fontWeight(.semibold) + Text(": " + detail).foregroundColor(Brand.inkSecondary)).font(.esy(14))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let ambiguous: Bool
    let toggle: (Bool) -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: snippet.mode == .whole ? "text.bubble" : "text.insert")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.accentInk)
                .frame(width: 32, height: 32).background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("“\(snippet.trigger)”").font(.esy(15, .semibold))
                    Text(snippet.mode == .whole ? "Whole dictation" : "Anywhere").font(.esy(11, .semibold))
                        .foregroundStyle(Brand.inkSecondary).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Brand.surfaceRaised, in: Capsule())
                }
                Text(snippet.text).font(.esy(13)).foregroundStyle(Brand.inkSecondary).lineLimit(2)
            }
            .opacity(snippet.enabled ? 1 : 0.5)
            Spacer(minLength: 8)
            if ambiguous {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                    .help("Another enabled snippet has the same trigger, so neither is typed. Change or disable one.")
                    .accessibilityLabel("Conflict: another snippet has the same trigger")
            }
            Group {
                IconAction(symbol: "pencil", label: "Edit \(snippet.trigger)", action: edit)
                IconAction(symbol: "trash", label: "Delete \(snippet.trigger)", danger: true, action: delete)
            }
            .opacity(hovering ? 1 : 0.35)
            Toggle("Enabled", isOn: Binding(get: { snippet.enabled }, set: toggle)).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(hovering ? Brand.accentSoft.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

private struct SnippetEditor: View {
    let categories: [String]
    let save: (Snippet) -> String?
    @State private var snippet: Snippet
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(snippet: Snippet, categories: [String], save: @escaping (Snippet) -> String?) {
        self.categories = categories
        self.save = save
        _snippet = State(initialValue: snippet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $snippet.name, prompt: Text("Email signature"))
                TextField("When I say", text: $snippet.trigger, prompt: Text("my email signature"))
                Picker("Works", selection: $snippet.mode) {
                    Text("Whole dictation").tag(Snippet.Mode.whole)
                    Text("Anywhere").tag(Snippet.Mode.anywhere)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Insert (\(snippet.text.count) of \(SnippetLibrary.maxText) characters)")
                    TextEditor(text: $snippet.text).font(.esy(13)).frame(height: 110).accessibilityLabel("Text to insert")
                    HStack {
                        ForEach(["{date}", "{time}", "{day}"], id: \.self) { token in Button(token) { snippet.text += token } }
                    }
                }
                Picker("Language", selection: $snippet.language) {
                    Text("Any language").tag("")
                    ForEach(WhisperCppEngine.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                TextField("Category", text: $snippet.category, prompt: Text("Email"))
                Toggle("Enabled", isOn: $snippet.enabled)
                LabeledContent("Created", value: snippet.created.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: snippet.modified.formatted(date: .abbreviated, time: .shortened))
            }
            .formStyle(.grouped)
            if let error { Text(error).font(.esy(12)).foregroundStyle(Brand.warning).padding(.horizontal, 20) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    error = save(snippet)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 520)
    }
}
