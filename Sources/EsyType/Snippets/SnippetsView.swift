import EsyTypeCore
import SwiftUI
import WhisperEngine

/// Snippets: say a trigger phrase, EsyType types the saved text.
struct SnippetsView: View {
    let model: SnippetModel
    @State private var query = ""
    @State private var category: String?
    @State private var editing: EditRequest?
    @State private var deleting: Snippet?
    @State private var importing: ImportPlan<Snippet>?
    @State private var message: String?

    struct EditRequest: Identifiable {
        var snippet: Snippet
        let isNew: Bool
        var id: UUID { snippet.id }
    }

    private var library: SnippetLibrary { model.library }
    private var shown: [Snippet] { library.search(query, category: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Snippets").font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader)
            Text("Say a trigger phrase and EsyType types your saved text instead: a signature, an address, a standard reply. Triggers match exactly, as whole words.")
                .font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    Text("All categories").tag(String?.none)
                    ForEach(library.categories, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden().frame(width: 160)
            }
            List {
                ForEach(shown) { snippet in row(snippet) }
            }
            .frame(minHeight: 280)
            .overlay {
                if shown.isEmpty {
                    Text(library.snippets.isEmpty
                         ? "No snippets yet.\nExample: say “my email signature” to type your signature."
                         : "No snippets match.")
                        .font(.esy(13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            HStack {
                Text("\(library.activeCount) active of \(library.snippets.count)").font(.esy(12)).foregroundStyle(.secondary)
                Spacer()
                Menu("CSV") {
                    Button("Import…", action: importCSV)
                    Button("Export…") { message = CSVPanels.save(SnippetCSV.export(library.snippets), name: "EsyType Snippets.csv") ?? message }
                        .disabled(library.snippets.isEmpty)
                }
                .fixedSize()
                Button("New Snippet…") { editing = EditRequest(snippet: Snippet(trigger: "", text: ""), isNew: true) }
            }
            if let text = message ?? model.notice {
                Text(text).font(.esy(12)).foregroundStyle(Brand.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $editing) { request in
            SnippetEditor(request: request, categories: library.categories) { snippet in
                let error = model.change { request.isNew ? try $0.add(snippet) : try $0.update(snippet) }
                if error == nil { message = nil }
                return error
            }
        }
        .sheet(item: $importing) { plan in
            ImportPreview(plan: plan, title: "Import snippets") { updateExisting in
                message = model.change { $0.apply(plan, updateExisting: updateExisting) }
                    ?? "Imported: \(plan.additions.count) added\(updateExisting ? ", \(plan.updates.count) updated" : "")."
                importing = nil
            } cancel: { importing = nil }
        }
        .confirmationDialog("Delete the snippet “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = deleting?.id { model.change { $0.delete(id: id) } }
            }
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Enabled", isOn: Binding(get: { snippet.enabled },
                                           set: { on in model.change { $0.setEnabled(id: snippet.id, on) } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name).font(.esy(13, .medium)).foregroundStyle(snippet.enabled ? .primary : .secondary)
                Text("Say “\(snippet.trigger)”").font(.esy(12)).foregroundStyle(.secondary)
                Text(snippet.text).font(.esy(12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if library.ambiguous.contains(snippet.id) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                    .help("Another enabled snippet has the same trigger, so neither is typed. Change or disable one.")
                    .accessibilityLabel("Conflict: another snippet has the same trigger")
            }
            if !snippet.category.isEmpty { Text(snippet.category).font(.esy(11)).foregroundStyle(.secondary) }
            Button { editing = EditRequest(snippet: snippet, isNew: false) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).accessibilityLabel("Edit \(snippet.name)")
            Button { deleting = snippet } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).accessibilityLabel("Delete \(snippet.name)")
        }
        .padding(.vertical, 3)
    }

    private func importCSV() {
        do {
            guard let data = try CSVPanels.open(message: "Choose a snippets CSV (UTF-8).") else { return }
            importing = library.plan(try SnippetCSV.parse(data))
            message = nil
        } catch {
            message = "Couldn’t import: \(error.localizedDescription)"
        }
    }
}

private struct SnippetEditor: View {
    let request: SnippetsView.EditRequest
    let categories: [String]
    let save: (Snippet) -> String?
    @State private var snippet: Snippet
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(request: SnippetsView.EditRequest, categories: [String], save: @escaping (Snippet) -> String?) {
        self.request = request
        self.categories = categories
        self.save = save
        _snippet = State(initialValue: request.snippet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $snippet.name, prompt: Text("Email signature"))
                TextField("Trigger phrase", text: $snippet.trigger, prompt: Text("my email signature"))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text to type")
                    TextEditor(text: $snippet.text)
                        .font(.esy(13))
                        .frame(height: 110)
                        .accessibilityLabel("Text to type")
                }
                Picker("Language", selection: $snippet.language) {
                    Text("Any language").tag("")
                    ForEach(WhisperCppEngine.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                HStack {
                    TextField("Category", text: $snippet.category, prompt: Text("Email"))
                    Menu("") {
                        ForEach(Array(Set(["Email", "Personal", "Work", "Replies"] + categories)).sorted(), id: \.self) { name in
                            Button(name) { snippet.category = name }
                        }
                    }
                    .fixedSize().accessibilityLabel("Choose a category")
                }
                Toggle("Enabled", isOn: $snippet.enabled)
                if !request.isNew {
                    LabeledContent("Created", value: snippet.created.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Modified", value: snippet.modified.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .formStyle(.grouped)
            if let error {
                Text(error).font(.esy(12)).foregroundStyle(Brand.warning).padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.isNew ? "Add" : "Save") {
                    error = save(snippet)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 500)
    }
}
