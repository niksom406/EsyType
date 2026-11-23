import AppKit
import EsyTypeCore
import SwiftUI
import UniformTypeIdentifiers
import WhisperEngine

/// Main window ▸ Dictionary: words spelled your way and corrections, import/export, built-in product names.
struct DictionaryPage: View {
    let model: DictionaryModel
    @AppStorage(Pref.dictionaryHints) private var hints = false
    @AppStorage(Pref.builtInNames) private var builtIns = true
    @State private var kind = DictionaryEntry.Kind.word
    @State private var term = ""
    @State private var replacement = ""
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var deleting: DictionaryEntry?
    @State private var confirmDeleteAll = false
    @State private var importing: ImportPlan<DictionaryEntry>?
    @State private var status: (text: String, file: URL?)?
    @State private var showBuiltIns = false
    @FocusState private var termFocused: Bool

    private var dictionary: PersonalDictionary { model.dictionary }
    private var shown: [DictionaryEntry] { dictionary.search(query).reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle("Dictionary")
            PageHero("dictionary", headline: Text("EsyType spells the way ") + Text("you").italic() + Text(" do."),
                     message: "Add names, company jargon and uncommon words once, and they’re spelled right every time you dictate.",
                     glow: Color(hex: 0x8350E8)) {
                HeroButton("Add new word") { kind = .word; termFocused = true }
                ForEach(examples, id: \.self) { word in HeroChip(word) { query = word } }
            }
            addCard
            listCard
            builtInCard
        }
        .sheet(item: $editing) { entry in
            EntryEditor(entry: entry, categories: dictionary.categories) { edited in
                model.change { try $0.update(edited) }
            }
        }
        .sheet(item: $importing) { plan in
            ImportPreview(plan: plan) { updateExisting in
                let error = model.change { $0.apply(plan, updateExisting: updateExisting) }
                status = (error ?? "Imported \(plan.additions.count) new \(plan.additions.count == 1 ? "entry" : "entries")\(updateExisting && !plan.updates.isEmpty ? ", updated \(plan.updates.count)" : "").", nil)
                importing = nil
            } cancel: { importing = nil }
        }
        .confirmationDialog("Delete “\(deleting?.spoken ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let id = deleting?.id { model.change { $0.delete(id: id) } } }
        }
        .confirmationDialog("Delete your whole dictionary?", isPresented: $confirmDeleteAll) {
            Button("Delete All \(dictionary.entries.count)", role: .destructive) {
                model.change { dictionary in dictionary.entries.map(\.id).forEach { dictionary.delete(id: $0) } }
            }
        } message: { Text("Export it first if you might want it back. This can’t be undone.") }
    }

    private var examples: [String] {
        let mine = Array(dictionary.entries.suffix(4).map(\.replacement).reversed())
        return mine.isEmpty ? ["EsyType", "Priya", "Kubernetes"] : mine
    }

    // MARK: Add

    private var addCard: some View {
        SectionCard("Add to your dictionary") {
            Segmented(selection: $kind, options: [(.word, "Word"), (.correction, "Correction")])
            if kind == .word {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("Word or name, spelled as you want it")
                    HStack(spacing: 12) {
                        RoundedField(prompt: "EsyType", text: $term).focused($termFocused).onSubmit(add)
                        AccentButton(title: "Add", enabled: !term.trimmingCharacters(in: .whitespaces).isEmpty, action: add)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel("When I say")
                        RoundedField(prompt: "esy type", text: $term).focused($termFocused)
                    }
                    Image(systemName: "arrow.right").foregroundStyle(Brand.inkTertiary).padding(.bottom, 14)
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel("Write")
                        RoundedField(prompt: "EsyType", text: $replacement).onSubmit(add)
                    }
                    AccentButton(title: "Add", enabled: !term.trimmingCharacters(in: .whitespaces).isEmpty
                                 && !replacement.trimmingCharacters(in: .whitespaces).isEmpty, action: add)
                }
            }
            Text("Words are spelled exactly as you enter them whenever they’re heard, even when the speech engine splits them (“esy type” → EsyType). Corrections replace what the speech engine writes with what you want. Neither is ever changed by Clean or Style.")
                .font(.esy(13)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
            SwitchRow("Also give these words to the speech engine as a hint",
                      detail: "Off by default. A hint helps the speech engine spell your words, but can slow dictation a little and occasionally puts a dictionary word where it doesn’t belong.",
                      isOn: $hints)
            if let status { StatusLine(text: status.text, file: status.file) }
        }
    }

    private func add() {
        let entry = DictionaryEntry(kind: kind, spoken: term, replacement: kind == .word ? term : replacement)
        if let error = model.change({ try $0.add(entry) }) {
            status = (error, nil)
        } else {
            status = ("Added “\(entry.kind == .word ? entry.spoken : "\(entry.spoken) → \(entry.replacement)")”.", nil)
            term = ""
            replacement = ""
        }
    }

    // MARK: List

    private var listCard: some View {
        SectionCard(title: "Your dictionary", count: dictionary.entries.count) {
            PillButton(title: "Import", systemImage: "square.and.arrow.down", action: importFile)
            PillButton(title: "CSV", systemImage: "square.and.arrow.up") { export(DictionaryCSV.export(dictionary.entries), "csv") }
                .disabled(dictionary.entries.isEmpty)
            PillButton(title: "JSON", systemImage: "square.and.arrow.up") { export(DictionaryCSV.exportJSON(dictionary.entries), "json") }
                .disabled(dictionary.entries.isEmpty)
            PillButton(title: "Delete all", danger: true) { confirmDeleteAll = true }.disabled(dictionary.entries.isEmpty)
        } content: {
            if dictionary.entries.isEmpty {
                EmptyList(symbol: "book.closed", title: "Your dictionary is empty",
                          message: "Add names and terms the speech engine gets wrong.", action: "Add a word") { termFocused = true }
            } else {
                SearchField(prompt: "Search your dictionary", text: $query)
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Rectangle().fill(Brand.hairline).frame(height: 1) }
                        DictionaryRow(entry: entry, conflict: dictionary.conflicts[entry.id],
                                      toggle: { on in model.change { $0.setEnabled(id: entry.id, on) } },
                                      edit: { editing = entry }, delete: { deleting = entry })
                    }
                    if shown.isEmpty { Text("No entries match “\(query)”.").font(.esy(13)).foregroundStyle(Brand.inkTertiary).padding(16) }
                }
                .background(Brand.surfaceRaised.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.hairline))
            }
            Text("Import reads CSV (kind, term, replacement, or EsyType’s own columns) or JSON. New entries are added; existing ones are only replaced if you choose. Exports go to your Downloads folder.")
                .font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func importFile() {
        do {
            guard let data = try CSVPanels.open(message: "Choose a dictionary CSV or JSON file.", types: [.commaSeparatedText, .json, .plainText])
            else { return }
            let isJSON = data.first(where: { !" \n\r\t\u{FEFF}".utf8.contains($0) }) == UInt8(ascii: "[")
            importing = dictionary.plan(try isJSON ? DictionaryCSV.parseJSON(data) : DictionaryCSV.parse(data))
        } catch {
            status = ("Couldn’t import: \(error.localizedDescription)", nil)
        }
    }

    private func export(_ data: Data, _ ext: String) {
        if let url = Downloads.save(data, name: "EsyType Dictionary", extension: ext) {
            status = ("Saved \(url.lastPathComponent) to Downloads.", url)
        } else { status = ("Couldn’t save to Downloads.", nil) }
    }

    // MARK: Built-in names

    private var builtInCard: some View {
        SectionCard("Built-in product names") {
            SwitchRow("Correct common product names: “chat gpt” becomes ChatGPT, “superbase” becomes Supabase, “microsoft co-pilot” becomes Microsoft Copilot",
                      isOn: $builtIns)
            Text("A fixed list, kept apart from your dictionary: it can’t be edited and isn’t exported. Your own entries always win. Names that are also everyday words, such as Claude, Notion, Python or Excel, are never changed by it; add them above if you want them.")
                .font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(isExpanded: $showBuiltIns) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .topLeading)], alignment: .leading, spacing: 8) {
                    ForEach(BuiltInNames.names, id: \.name) { item in
                        (Text(item.name).font(.esy(13, .semibold)) + Text(" from " + item.heard.joined(separator: ", ")).font(.esy(13)).foregroundColor(Brand.inkTertiary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Show the list (\(BuiltInNames.names.count) names)").font(.esy(13, .medium))
            }
        }
    }
}

/// One dictionary entry: kind icon, words, details, on/off, edit and delete.
private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let conflict: DictionaryEntry?
    let toggle: (Bool) -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.kind == .word ? "textformat.abc" : "arrow.triangle.swap")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.accentInk)
                .frame(width: 32, height: 32).background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                if entry.kind == .word {
                    Text(entry.spoken).font(.esy(15, .semibold))
                } else {
                    (Text(entry.spoken).foregroundColor(Brand.inkSecondary) + Text("  →  ").foregroundColor(Brand.inkTertiary)
                     + Text(entry.replacement).fontWeight(.semibold)).font(.esy(15))
                }
                Text(details).font(.esy(12)).foregroundStyle(Brand.inkTertiary).lineLimit(1)
            }
            .opacity(entry.enabled ? 1 : 0.5)
            Spacer(minLength: 8)
            if let conflict {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                    .help("Ignored: an earlier entry already turns these words into “\(conflict.replacement)”.")
                    .accessibilityLabel("Conflict: ignored, an earlier entry wins")
            }
            Group {
                IconAction(symbol: "pencil", label: "Edit \(entry.spoken)", action: edit)
                IconAction(symbol: "trash", label: "Delete \(entry.spoken)", danger: true, action: delete)
            }
            .opacity(hovering ? 1 : 0.35)
            Toggle("Enabled", isOn: Binding(get: { entry.enabled }, set: toggle))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(hovering ? Brand.accentSoft.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var details: String {
        let language = entry.language.isEmpty ? "Any language" : Locale.current.localizedString(forLanguageCode: entry.language) ?? entry.language
        return ([entry.kind == .word ? "Word" : "Correction", language, entry.category, entry.note].filter { !$0.isEmpty })
            .joined(separator: " · ")
    }
}

/// A small round icon button (edit, delete, copy).
struct IconAction: View {
    let symbol: String
    let label: String
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12.5))
                .foregroundStyle(danger ? Brand.recording : Brand.inkSecondary)
                .frame(width: 30, height: 30).background(Brand.surfaceRaised, in: Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// Capsule segmented control in the Windows style (Word | Correction, Whole | Anywhere).
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                let on = selection == value
                Button { withAnimation(.easeInOut(duration: 0.18)) { selection = value } } label: {
                    Text(title).font(.esy(14, on ? .semibold : .regular)).foregroundStyle(on ? Brand.ink : Brand.inkSecondary)
                        .padding(.horizontal, 18).frame(height: 36)
                        .background(on ? Brand.surface : .clear, in: Capsule())
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Brand.surfaceRaised, in: Capsule())
        .overlay(Capsule().stroke(Brand.hairline))
    }
}

/// Edit one entry (all fields).
private struct EntryEditor: View {
    let categories: [String]
    let save: (DictionaryEntry) -> String?
    @State private var entry: DictionaryEntry
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(entry: DictionaryEntry, categories: [String], save: @escaping (DictionaryEntry) -> String?) {
        self.categories = categories
        self.save = save
        _entry = State(initialValue: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker("Type", selection: $entry.kind) {
                    Text("Word").tag(DictionaryEntry.Kind.word)
                    Text("Correction").tag(DictionaryEntry.Kind.correction)
                }
                .pickerStyle(.segmented)
                if entry.kind == .word {
                    TextField("Word or name", text: $entry.spoken, prompt: Text("EsyType"))
                } else {
                    TextField("When I say", text: $entry.spoken, prompt: Text("esy type"))
                    TextField("Write", text: $entry.replacement, prompt: Text("EsyType"))
                }
                Picker("Language", selection: $entry.language) {
                    Text("Any language").tag("")
                    ForEach(WhisperCppEngine.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                HStack {
                    TextField("Category", text: $entry.category, prompt: Text("Brand"))
                    Menu("") {
                        ForEach(Array(Set(["Brand", "Technical", "Abbreviation", "Name", "Other"] + categories)).sorted(), id: \.self) { name in
                            Button(name) { entry.category = name }
                        }
                    }
                    .fixedSize().accessibilityLabel("Choose a category")
                }
                TextField("Description (optional)", text: $entry.note)
                Toggle("Enabled", isOn: $entry.enabled)
            }
            .formStyle(.grouped)
            if let error { Text(error).font(.esy(12)).foregroundStyle(Brand.warning).padding(.horizontal, 20) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    error = save(entry)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480)
    }
}
