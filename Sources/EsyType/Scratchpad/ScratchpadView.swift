import AppKit
import EsyTypeCore
import SwiftUI

/// A place to dictate into EsyType itself, saved on this Mac (scratchpad.txt, readable only by you).
struct ScratchpadView: View {
    @State private var text = Scratchpad.load()
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scratchpad").font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader)
            Text("Click in the page, then hold your shortcut and speak. Use it to draft before pasting anywhere. It’s saved on this Mac as you go.")
                .font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.esy(15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 320)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.hairlineStrong))
                .accessibilityLabel("Scratchpad")
                .onChange(of: text) { Scratchpad.save(text) }
            HStack {
                Text("\(text.split(whereSeparator: \.isWhitespace).count) words").font(.esy(12)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear…") { confirmClear = true }.disabled(text.isEmpty)
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(text.isEmpty)
            }
        }
        .confirmationDialog("Clear the scratchpad?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { text = "" }
        } message: { Text("This can’t be undone.") }
    }
}

enum Scratchpad {
    static let url = ListFile<String>.inSupportFolder("scratchpad.txt")

    static func load() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    static func save(_ text: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? Data(text.utf8).write(to: url, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
