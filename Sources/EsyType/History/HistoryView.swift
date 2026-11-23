import AppKit
import EsyTypeCore
import SwiftUI

/// Main window ▸ History: your dictations by day, searchable and filterable, with copy and delete.
struct HistoryView: View {
    @Bindable var history: HistoryModel
    @State private var confirmClear = false
    @State private var filter = Filter.all
    @State private var appeared = false
    @State private var editing: HistoryEntry?
    @State private var status: (text: String, file: URL?)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Filter: Hashable { case all, today, week, notInserted, app(String) }

    private var shown: [HistoryEntry] {
        let calendar = Calendar.current
        return history.entries.filter { entry in
            switch filter {
            case .all: true
            case .today: calendar.isDateInToday(entry.createdAt)
            case .week: entry.createdAt > calendar.date(byAdding: .day, value: -7, to: Date())!
            case .notInserted: !entry.inserted
            case .app(let id): entry.appBundleID == id
            }
        }
    }

    var body: some View {
        let entries = shown
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.createdAt) }.sorted { $0.key > $1.key }
        VStack(alignment: .leading, spacing: 18) {
            PageTitle("History")
            PageHero("history", headline: Text("Everything you’ve ") + Text("said").italic() + Text(", kept on this Mac."),
                     message: "Your dictations, stored only on this Mac for as long as you choose. Audio is never saved.",
                     glow: Color(hex: 0xA78BFA)) {
                HeroChip("\(history.entries.count.formatted()) dictations")
                HeroChip("\(history.entries.reduce(0) { $0 + InsightsLog.wordCount($1.text) }.formatted()) words")
                let missed = history.entries.filter { !$0.inserted }.count
                if missed > 0 { HeroChip("\(missed) not inserted") { filter = .notInserted } }
            }
            HStack(spacing: 8) {
                Text(summary).font(.esy(14)).foregroundStyle(Brand.inkTertiary)
                Spacer(minLength: 8)
                PillButton(title: "CSV", systemImage: "square.and.arrow.up") { export(HistoryExport.csv(history.entries, appName: HistoryRow.appName), "csv") }
                    .disabled(history.entries.isEmpty)
                PillButton(title: "JSON", systemImage: "square.and.arrow.up") { export(HistoryExport.json(history.entries, appName: HistoryRow.appName), "json") }
                    .disabled(history.entries.isEmpty)
                PillButton(title: "Delete all", danger: true) { confirmClear = true }
                    .disabled(history.entries.isEmpty && history.search.isEmpty)
            }
            if let status { StatusLine(text: status.text, file: status.file) }
            searchField
            chips
            if let error = history.error {
                Text(error).font(.esy(12)).foregroundStyle(Brand.warning)
            }
            if entries.isEmpty { empty }
            ForEach(Array(groups.enumerated()), id: \.element.key) { index, group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Eyebrow(Self.dayTitle(group.key))
                        Text("\(group.value.count)").font(.esy(10.5, .semibold)).foregroundStyle(Brand.inkTertiary)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Brand.surfaceRaised, in: Capsule())
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(group.value.enumerated()), id: \.element.id) { row, entry in
                            if row > 0 { Rectangle().fill(Brand.hairline).frame(height: 1).padding(.leading, 24) }
                            HistoryRow(entry: entry, search: history.search, edit: { editing = entry }) { history.delete(entry) }
                        }
                    }
                    .esyGlassCard(cornerRadius: 18, padded: false)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.88).delay(min(Double(index) * 0.07, 0.5)),
                           value: appeared)
            }
        }
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            appeared = false
            DispatchQueue.main.async { appeared = true }
        }
        .sheet(item: $editing) { entry in
            HistoryEditor(entry: entry) { text in history.update(entry, text: text) }
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { history.clearAll() }
        } message: {
            Text("This can’t be undone.")
        }
    }

    private func export(_ data: Data, _ ext: String) {
        if let url = Downloads.save(data, name: "EsyType History", extension: ext) {
            status = ("Saved \(url.lastPathComponent) to Downloads.", url)
        } else { status = ("Couldn’t save to Downloads.", nil) }
    }

    private var summary: String {
        let words = history.entries.reduce(0) { $0 + InsightsLog.wordCount($1.text) }
        let count = history.entries.count
        return count == 0 ? "Nothing yet." : "\(count.formatted()) \(count == 1 ? "dictation" : "dictations") · \(words.formatted()) words"
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Brand.inkTertiary)
            TextField("Search your dictations", text: $history.search)
                .textFieldStyle(.plain).font(.esy(14))
            if !history.search.isEmpty {
                Button { history.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Brand.inkTertiary).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Brand.glassStrong, in: Capsule())
        .overlay(Capsule().stroke(Brand.hairlineStrong))
    }

    /// All / Today / This week, then the apps you've dictated into most.
    private var chips: some View {
        let apps = Dictionary(grouping: history.entries.compactMap(\.appBundleID), by: { $0 })
            .sorted { $0.value.count > $1.value.count }.prefix(6).map(\.key)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", .all)
                chip("Today", .today)
                chip("This week", .week)
                if history.entries.contains(where: { !$0.inserted }) { chip("Not inserted", .notInserted) }
                ForEach(apps, id: \.self) { id in
                    chip(HistoryRow.appName(id) ?? id, .app(id), icon: HistoryRow.icon(id))
                }
            }
        }
    }

    private func chip(_ title: String, _ value: Filter, icon: NSImage? = nil) -> some View {
        let on = filter == value
        return Button { withAnimation(.easeInOut(duration: 0.2)) { filter = value } } label: {
            HStack(spacing: 6) {
                if let icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                Text(title).font(.esy(13, on ? .semibold : .regular))
            }
            .padding(.horizontal, 12).frame(height: 30)
            .foregroundStyle(on ? Color.white : Brand.inkSecondary)
            .background(on ? Brand.accent : Brand.surfaceRaised, in: Capsule())
            .overlay(Capsule().stroke(on ? Color.clear : Brand.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var empty: some View {
        if !history.search.isEmpty {
            Text("No dictations match “\(history.search)”.").font(.esy(14)).foregroundStyle(Brand.inkTertiary)
        } else if filter != .all {
            Text("Nothing here yet.").font(.esy(14)).foregroundStyle(Brand.inkTertiary)
        } else {
            VStack(spacing: 14) {
                SpeakingWave(bars: 18, barWidth: 4, spacing: 4, height: 60).frame(width: 160)
                Text("Nothing yet").font(.esyDisplay(30))
                Text("Your dictations appear here, stored only on this Mac. Settings ▸ History & Privacy sets how long they’re kept.")
                    .font(.esy(14)).foregroundStyle(Brand.inkTertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .esyGlassCard(cornerRadius: 18)
        }
    }

    static func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

/// One dictation: time and app icon, the text (search matches highlighted), details, and Copy / Delete on hover.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let search: String
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false
    @State private var copied = false
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.esy(13)).monospacedDigit().foregroundStyle(Brand.inkTertiary)
                if let id = entry.appBundleID, let icon = Self.icon(id) {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                }
            }
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(highlighted).font(.esy(15)).lineSpacing(2).textSelection(.enabled).lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(details).font(.esy(12)).foregroundStyle(Brand.inkTertiary)
                    if !entry.inserted {
                        Label("Not inserted", systemImage: "circle.fill").labelStyle(NotInsertedStyle())
                            .help("EsyType couldn’t type this one, so it was copied for you to paste.")
                    }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                action(copied ? "checkmark" : "doc.on.doc", copied ? "Copied" : "Copy") {
                    Clipboard.write(entry.text)
                    withAnimation { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { copied = false } }
                }
                action("pencil", "Edit", action: edit)
                action("trash", "Delete", role: .destructive, action: delete)
            }
            .opacity(hovering || copied || focused ? 1 : 0) // always reachable by keyboard and VoiceOver
            .accessibilityFocused($focused)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(hovering ? Brand.accentSoft.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private func action(_ symbol: String, _ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol).font(.system(size: 13))
                .frame(width: 30, height: 30)
                .background(Brand.surfaceRaised, in: Circle())
                .foregroundStyle(role == .destructive ? Brand.recording : symbol == "checkmark" ? Brand.success : Brand.inkSecondary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var details: String {
        let seconds = max(1, entry.durationMs / 1000)
        let words = InsightsLog.wordCount(entry.text)
        return ([entry.appBundleID.flatMap(Self.appName)].compactMap { $0 }
                + ["\(words) \(words == 1 ? "word" : "words")", "\(seconds) s spoken",
                   Locale.current.localizedString(forLanguageCode: entry.language) ?? entry.language.uppercased()])
            .joined(separator: " · ")
    }

    /// The text with every match of the search in the brand's purple.
    private var highlighted: AttributedString {
        var text = AttributedString(entry.text)
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return text }
        var start = text.startIndex
        while let range = text[start...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].backgroundColor = Brand.accentSoft
            text[range].foregroundColor = Brand.accentInk
            start = range.upperBound
        }
        return text
    }

    @MainActor static func icon(_ bundleID: String) -> NSImage? { AppInfo.icon(bundleID) }
    @MainActor static func appName(_ bundleID: String) -> String? { AppInfo.name(bundleID) }
}

/// "● Not inserted", the Windows badge for a dictation that was copied instead of typed.
private struct NotInsertedStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Brand.warning)
            configuration.title.font(.esy(11.5, .semibold)).foregroundStyle(Brand.warning)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Brand.warning.opacity(0.12), in: Capsule())
    }
}

/// History ▸ Edit: change a dictation's text.
private struct HistoryEditor: View {
    let entry: HistoryEntry
    let save: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(entry: HistoryEntry, save: @escaping (String) -> Void) {
        self.entry = entry
        self.save = save
        _text = State(initialValue: entry.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit dictation").font(.esy(17, .semibold))
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.esy(12)).foregroundStyle(Brand.inkTertiary)
            TextEditor(text: $text).font(.esy(14)).frame(minHeight: 140)
                .padding(8).background(Brand.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(text); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}
