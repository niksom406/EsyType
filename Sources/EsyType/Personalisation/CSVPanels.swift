import AppKit
import EsyTypeCore
import SwiftUI
import UniformTypeIdentifiers

/// The macOS file dialogs for CSV import and export, shared by Dictionary and Snippets.
@MainActor
enum CSVPanels {
    /// The chosen file's contents, or nil if the user cancelled.
    static func open(message: String) throws -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= CSVFile.maxBytes else { throw CSVFile.FileError.tooLarge }
        return try Data(contentsOf: url)
    }

    /// Writes `data` where the user chooses. Returns a message for the screen, or nil if cancelled.
    static func save(_ data: Data, name: String) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return "Saved \(url.lastPathComponent)."
        } catch {
            return "Couldn’t save: \(error.localizedDescription)"
        }
    }
}

/// Counts and rejected rows of an import, with Cancel and Import. Nothing changes until Import is pressed.
struct ImportPreview<Item: Equatable & Sendable>: View {
    let plan: ImportPlan<Item>
    var title = "Import dictionary"
    let confirm: (_ updateExisting: Bool) -> Void
    let cancel: () -> Void
    @State private var updateExisting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.esy(17, .semibold))
            Grid(alignment: .leading, verticalSpacing: 4) {
                GridRow { Text("New entries to add"); Text("\(plan.additions.count)").bold() }
                GridRow { Text("Existing entries that differ"); Text("\(plan.updates.count)").bold() }
                GridRow { Text("Already in your dictionary (skipped)"); Text("\(plan.skipped)").bold() }
                GridRow { Text("Rejected rows"); Text("\(plan.rejected.count)").bold() }
            }
            .font(.esy(13))
            if !plan.updates.isEmpty {
                Toggle("Replace the \(plan.updates.count) existing entries with the file’s version", isOn: $updateExisting)
                    .font(.esy(13))
            }
            if !plan.rejected.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(plan.rejected.prefix(50).enumerated()), id: \.offset) { _, row in
                            Text("Line \(row.line): \(row.reason)").font(.esy(12)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Import") { confirm(updateExisting) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.additions.isEmpty && !(updateExisting && !plan.updates.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
