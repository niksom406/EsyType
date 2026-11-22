import AppKit
import EsyTypeCore
import SwiftUI

/// Main window ▸ History: search, copy, delete, clear all.
struct HistoryView: View {
    @Bindable var history: HistoryModel
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear All…") { confirmClear = true }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(history.entries.isEmpty && history.search.isEmpty)
            }
            TextField("Search", text: $history.search)
                .textFieldStyle(.roundedBorder)
                .font(.esy(13))
            if let error = history.error {
                Text(error).font(.esy(12)).foregroundStyle(Brand.warning)
            }
            if history.entries.isEmpty {
                if history.search.isEmpty {
                    EmptyStateView(title: "Nothing yet.",
                                   message: "Your dictations appear here, stored only on this Mac. Settings ▸ History & Privacy sets how long they’re kept.")
                } else {
                    Text("No dictations match “\(history.search)”.").font(.esy(14)).foregroundStyle(.secondary)
                }
            }
            ForEach(history.entries) { row($0) }
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { history.clearAll() }
        } message: {
            Text("This can’t be undone.")
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.text).font(.esy(14)).textSelection(.enabled).lineLimit(6)
            HStack(spacing: 10) {
                Text(entry.createdAt, format: .dateTime.day().month().hour().minute())
                Text(entry.language.uppercased())
                Text("\(max(1, entry.durationMs / 1000)) s")
                if let app = entry.appBundleID.flatMap(Self.appName) { Text(app) }
                Spacer()
                Button("Copy") { Clipboard.write(entry.text) }.buttonStyle(.borderless)
                Button("Delete", role: .destructive) { history.delete(entry) }.buttonStyle(.borderless)
            }
            .font(.esy(12)).foregroundStyle(.secondary)
        }
        .esyCard()
        .accessibilityElement(children: .contain)
    }

    private static func appName(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
}
