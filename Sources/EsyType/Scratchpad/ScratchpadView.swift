import AppKit
import EsyTypeCore
import SwiftUI

/// Main window ▸ Scratchpad: notes that save themselves as you write or dictate.
struct ScratchpadView: View {
    let notes: NotesModel
    @State private var query = ""
    @State private var confirmDeleteAll = false
    @State private var confirmDelete = false
    @State private var status: (text: String, file: URL?)?
    @FocusState private var editorFocused: Bool

    private var shown: [Note] {
        notes.notes.filter { query.isEmpty || $0.text.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle("Scratchpad")
            PageHero("scratchpad", headline: Text("Think out ") + Text("loud").italic() + Text("."),
                     message: "Notes that save themselves as you write or dictate. Click in a note, hold your shortcut and speak: the text goes in at the cursor.",
                     glow: Color(hex: 0x4ADE80)) {
                HeroButton("New note") { newNote() }
                if let note = notes.selected, !note.text.isEmpty { HeroChip("\(note.words) words in this note") }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    list.frame(width: 290)
                    editor
                }
                VStack(spacing: 16) { list; editor }
            }
            if let status { StatusLine(text: status.text, file: status.file) }
            Text("Notes stay on this Mac until you delete them; History’s settings never touch them.")
                .font(.esy(12)).foregroundStyle(Brand.inkTertiary)
        }
        .confirmationDialog("Delete all notes?", isPresented: $confirmDeleteAll) {
            Button("Delete All \(notes.notes.count)", role: .destructive) { notes.deleteAll() }
        } message: { Text("This can’t be undone.") }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { if let id = notes.selection { notes.delete(id) } }
        }
    }

    private func newNote() {
        notes.newNote()
        editorFocused = true
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: newNote) {
                Label("New note", systemImage: "square.and.pencil").font(.esy(14, .semibold)).foregroundStyle(Brand.canvas)
                    .padding(.horizontal, 18).frame(height: 40).background(Brand.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            HStack {
                Text("Notes").font(.esy(16, .semibold))
                Text("\(notes.notes.count)").font(.esy(12, .semibold)).foregroundStyle(Brand.inkSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Brand.surfaceRaised, in: Capsule())
                Spacer()
                PillButton(title: "Delete all", danger: true) { confirmDeleteAll = true }.disabled(notes.notes.isEmpty)
            }
            SearchField(prompt: "Search notes", text: $query)
            if notes.notes.isEmpty {
                EmptyList(symbol: "doc.text", title: "No notes yet", message: "Write or dictate; notes save as you go.",
                          action: "New note", perform: newNote)
            } else {
                VStack(spacing: 4) {
                    ForEach(shown) { note in
                        let on = note.id == notes.selection
                        Button { notes.selection = note.id } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title).font(.esy(14, on ? .semibold : .medium)).lineLimit(1)
                                Text("\(note.modified.formatted(.relative(presentation: .named))) · \(note.words) words")
                                    .font(.esy(12)).foregroundStyle(Brand.inkTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(on ? Brand.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    if shown.isEmpty { Text("No notes match “\(query)”.").font(.esy(13)).foregroundStyle(Brand.inkTertiary).padding(8) }
                }
            }
        }
        .padding(20)
        .esyGlassCard(cornerRadius: 20, padded: false)
    }

    private var editor: some View {
        let note = notes.selected
        return VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { note?.text ?? "" }, set: { text in
                    if let id = notes.selection { notes.update(id, text: text) } else { notes.newNote(); notes.update(notes.selection!, text: text) }
                }))
                .font(.esy(16)).lineSpacing(3).scrollContentBackground(.hidden).padding(14)
                .focused($editorFocused)
                .accessibilityLabel("Note")
                if (note?.text ?? "").isEmpty {
                    Text("Write or dictate here. Hold your shortcut and speak: the text goes in at the cursor.")
                        .font(.esy(16)).foregroundStyle(Brand.inkTertiary).padding(.horizontal, 19).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 380)
            .background(Brand.surfaceRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.hairlineStrong))
            HStack(spacing: 8) {
                Text("\(note?.words ?? 0) words").font(.esy(13)).foregroundStyle(Brand.inkTertiary)
                Spacer()
                let empty = (note?.text ?? "").isEmpty
                PillButton(title: "Copy all", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(note?.text ?? "", forType: .string)
                    status = ("Copied.", nil)
                }
                .disabled(empty)
                PillButton(title: ".txt", systemImage: "square.and.arrow.up") { export("txt") }.disabled(empty)
                PillButton(title: ".md", systemImage: "square.and.arrow.up") { export("md") }.disabled(empty)
                PillButton(title: "Delete", danger: true) { confirmDelete = true }.disabled(note == nil)
            }
        }
        .padding(20)
        .esyGlassCard(cornerRadius: 20, padded: false)
    }

    private func export(_ ext: String) {
        guard let note = notes.selected else { return }
        let name = note.title.replacingOccurrences(of: "/", with: "-").prefix(40)
        if let url = Downloads.save(Data(note.text.utf8), name: String(name), extension: ext) {
            status = ("Saved \(url.lastPathComponent) to Downloads.", url)
        } else { status = ("Couldn’t save to Downloads.", nil) }
    }
}
