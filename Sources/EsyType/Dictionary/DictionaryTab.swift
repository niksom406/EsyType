import AppKit
import EsyTypeCore
import SwiftUI
import UniformTypeIdentifiers
import WhisperEngine

/// Settings ▸ Dictionary: the user's words, CSV import and export.
struct DictionaryTab: View {
    let model: DictionaryModel
    @State private var query = ""
    @State private var category: String?
    @State private var language: String?
    @State private var editing: EditRequest?
    @State private var deleting: DictionaryEntry?
    @State private var importing: ImportPlan<DictionaryEntry>?
    @State private var message: String?

    struct EditRequest: Identifiable {
        var entry: DictionaryEntry
        let isNew: Bool
        var id: UUID { entry.id }
    }

    private var dictionary: PersonalDictionary { model.dictionary }
    private var shown: [DictionaryEntry] { dictionary.search(query, category: category, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    Text("All categories").tag(String?.none)
                    ForEach(dictionary.categories, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden().frame(width: 140)
                Picker("Language", selection: $language) {
                    Text("All languages").tag(String?.none)
                    ForEach(dictionary.languages, id: \.self) { Text(languageName($0)).tag(String?.some($0)) }
                }
                .labelsHidden().frame(width: 140)
            }
            List {
                ForEach(shown) { entry in row(entry) }
            }
            .frame(height: 300)
            .overlay {
                if shown.isEmpty {
                    Text(dictionary.entries.isEmpty
                         ? "No words yet. Add one, or import a CSV.\nExample: “esy type” → “EsyType”."
                         : "No entries match.")
                        .font(.esy(13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            HStack {
                Text("\(dictionary.activeCount) active of \(dictionary.entries.count)")
                    .font(.esy(12)).foregroundStyle(.secondary)
                Spacer()
                Menu("CSV") {
                    Button("Import…", action: importCSV)
                    Button("Export…", action: exportCSV).disabled(dictionary.entries.isEmpty)
                    Divider()
                    Button("Save Sample Template…", action: saveTemplate)
                }
                .fixedSize()
                Button("Add Word…") { editing = EditRequest(entry: DictionaryEntry(spoken: "", replacement: ""), isNew: true) }
            }
            if let text = message ?? model.notice {
                Text(text).font(.esy(12)).foregroundStyle(Brand.warning).fixedSize(horizontal: false, vertical: true)
            }
            Text("Replacements are exact: whole words, any capitalisation. Words are also hinted to the speech model, which helps but doesn’t guarantee its spelling. Everything stays on this Mac.")
                .font(.esy(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .sheet(item: $editing) { request in
            EntryEditor(request: request, categories: dictionary.categories) { entry in
                let error = model.change { request.isNew ? try $0.add(entry) : try $0.update(entry) }
                if error == nil, let winner = model.dictionary.conflicts[entry.id] {
                    message = "“\(entry.spoken)” is ignored: an earlier entry already turns it into “\(winner.replacement)”."
                } else if error == nil { message = nil }
                return error
            }
        }
        .sheet(item: $importing) { plan in
            ImportPreview(plan: plan) { updateExisting in
                message = model.change { $0.apply(plan, updateExisting: updateExisting) }
                    ?? "Imported: \(plan.additions.count) added\(updateExisting ? ", \(plan.updates.count) updated" : "")."
                importing = nil
            } cancel: { importing = nil }
        }
        .confirmationDialog("Delete “\(deleting?.spoken ?? "")” → “\(deleting?.replacement ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = deleting?.id { model.change { $0.delete(id: id) } }
            }
        }
    }

    private func row(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("Enabled", isOn: Binding(get: { entry.enabled },
                                           set: { on in model.change { $0.setEnabled(id: entry.id, on) } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.spoken)  →  \(entry.replacement)").font(.esy(13, .medium))
                    .foregroundStyle(entry.enabled ? .primary : .secondary)
                Text([languageName(entry.language), entry.category, entry.note].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.esy(11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let winner = dictionary.conflicts[entry.id] {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                    .help("Ignored: an earlier entry already turns these words into “\(winner.replacement)”.")
                    .accessibilityLabel("Conflict: ignored, an earlier entry wins")
            }
            Button { editing = EditRequest(entry: entry, isNew: false) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).accessibilityLabel("Edit \(entry.spoken)")
            Button { deleting = entry } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).accessibilityLabel("Delete \(entry.spoken)")
        }
        .padding(.vertical, 2)
    }

    private func languageName(_ code: String) -> String {
        code.isEmpty ? "Any language" : Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // MARK: CSV

    private func importCSV() {
        do {
            guard let data = try CSVPanels.open(message: "Choose a dictionary CSV (UTF-8).") else { return }
            importing = dictionary.plan(try DictionaryCSV.parse(data))
            message = nil
        } catch {
            message = "Couldn’t import: \(error.localizedDescription)"
        }
    }

    private func exportCSV() { save(DictionaryCSV.export(dictionary.entries), name: "EsyType Dictionary.csv") }
    private func saveTemplate() { save(DictionaryCSV.export(DictionaryCSV.sampleEntries), name: "EsyType Dictionary Template.csv") }

    private func save(_ data: Data, name: String) { if let text = CSVPanels.save(data, name: name) { message = text } }
}

private struct EntryEditor: View {
    let request: DictionaryTab.EditRequest
    let categories: [String]
    let save: (DictionaryEntry) -> String?
    @State private var entry: DictionaryEntry
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(request: DictionaryTab.EditRequest, categories: [String], save: @escaping (DictionaryEntry) -> String?) {
        self.request = request
        self.categories = categories
        self.save = save
        _entry = State(initialValue: request.entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("When Whisper writes", text: $entry.spoken, prompt: Text("esy type"))
                TextField("Type instead", text: $entry.replacement, prompt: Text("EsyType"))
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
            if let error {
                Text(error).font(.esy(12)).foregroundStyle(Brand.warning).padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.isNew ? "Add" : "Save") {
                    error = save(entry)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 460)
    }
}
