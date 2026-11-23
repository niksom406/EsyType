import EsyTypeCore
import SwiftUI

struct MainWindowView: View {
    /// The sidebar, as in the Windows design: Dictation, EsyMeet, Insights; "Your words"; Settings at the bottom.
    enum Destination: String, CaseIterable, Identifiable {
        case dictation, meet, insights, history, dictionary, snippets, style, scratchpad, settings
        var id: Self { self }

        static let groups: [(title: String?, items: [Destination])] = [
            (nil, [.dictation, .meet, .insights]),
            ("Your words", [.history, .dictionary, .snippets, .style, .scratchpad]),
            (nil, [.settings]),
        ]

        var title: String {
            switch self {
            case .dictation: "Dictation"
            case .meet: "EsyMeet"
            case .insights: "Insights"
            case .history: "History"
            case .dictionary: "Dictionary"
            case .snippets: "Snippets"
            case .style: "Style"
            case .scratchpad: "Scratchpad"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .dictation: "mic"
            case .meet: "person.2.wave.2"
            case .insights: "chart.bar"
            case .history: "clock.arrow.circlepath"
            case .dictionary: "character.book.closed"
            case .snippets: "text.badge.plus"
            case .style: "textformat"
            case .scratchpad: "square.and.pencil"
            case .settings: "gearshape"
            }
        }
    }

    let models: ModelLibrary
    let history: HistoryModel
    let dictionary: DictionaryModel
    let snippets: SnippetModel
    let insights: InsightsModel
    let permissions: Permissions
    let openSettings: () -> Void
    @AppStorage("mainWindowSection") private var remembered = Destination.dictation.rawValue
    @State private var selection: Destination?
    @State private var notes = NotesModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Brand.hairline).frame(width: 1)
            ScrollView {
                Group {
                    switch selection ?? .dictation {
                    case .dictation, .settings:
                        DictationHome(models: models, permissions: permissions, insights: insights, history: history,
                                      dictionary: dictionary, snippets: snippets) { select($0) }
                    case .meet: EsyMeetPreview()
                    case .insights: InsightsView(insights: insights)
                    case .history: HistoryView(history: history)
                    case .dictionary: DictionaryPage(model: dictionary)
                    case .snippets: SnippetsView(model: snippets)
                    case .style: StylePage(history: history)
                    case .scratchpad: ScratchpadView(notes: notes)
                    }
                }
                .frame(maxWidth: 1240, alignment: .leading) // grows with the window, readable on very wide screens
                .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        .onAppear { selection = Destination(rawValue: remembered).flatMap { $0 == .settings ? nil : $0 } ?? .dictation }
    }

    /// The Windows sidebar: wordmark, three primary pages, "Your words", Settings at the bottom, engine status.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("EsyType.").font(.esyDisplay(25)).tracking(-0.25)
                .padding(.horizontal, 12).padding(.bottom, 18)
                .accessibilityLabel("EsyType").accessibilityAddTraits(.isHeader)
            ForEach(Destination.groups.indices, id: \.self) { index in
                let group = Destination.groups[index]
                if group.items == [.settings] { Spacer(minLength: 12) }
                if let title = group.title {
                    Text(title.uppercased()).font(.esy(10.5, .semibold)).tracking(1.2).foregroundStyle(Brand.inkTertiary)
                        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.items) { item in navRow(item) }
            }
            HStack(spacing: 8) {
                Circle().fill(Brand.success).frame(width: 7, height: 7)
                Text(engineSummary).font(.esy(12, .medium)).foregroundStyle(Brand.success)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Brand.surfaceRaised, in: Capsule())
            .padding(.top, 10).padding(.leading, 4)
        }
        .padding(.top, 40).padding(.horizontal, 12).padding(.bottom, 14) // room for the window buttons
        .frame(width: 216)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.sidebar.opacity(0.35)) // the window's glass shows through, as on Windows
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
    }

    private func navRow(_ item: Destination) -> some View {
        let on = (selection ?? .dictation) == item && item != .settings
        return Button { select(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol).font(.system(size: 15)).frame(width: 18)
                    .foregroundStyle(on ? Brand.accentInk : Brand.inkSecondary)
                Text(item.title).font(.esy(14, on ? .semibold : .regular))
                    .foregroundStyle(on ? Brand.ink : Brand.inkSecondary)
                Spacer(minLength: 0)
                if item == .meet { // EsyMeet is the next phase, not built yet
                    Text("Soon").font(.esy(10.5, .semibold)).foregroundStyle(Brand.inkTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Brand.surfaceRaised, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(on ? Brand.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func select(_ item: Destination) {
        if item == .settings { return openSettings() } // a window, not a page: stay where we were
        selection = item
        remembered = item.rawValue
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let pages = Destination.allCases.filter { $0 != .settings }
        guard let index = pages.firstIndex(of: selection ?? .dictation) else { return .ignored }
        select(pages[(index + step + pages.count) % pages.count])
        return .handled
    }

    /// "Local · Small · Metal", like the Windows sidebar's engine line.
    private var engineSummary: String {
        let model = models.activeModel.map { $0.name.replacingOccurrences(of: "Whisper ", with: "") } ?? "no model"
        let engine = HardwareDetector.current().isAppleSilicon ? "Metal" : "\(HardwareDetector.physicalCores) threads"
        return "Local · \(model) · \(engine)"
    }
}

struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader) }
}

/// The Dictation home: a welcome, an animated hero, your numbers, and recent dictations by day.
private struct DictationHome: View {
    let models: ModelLibrary
    let permissions: Permissions
    let insights: InsightsModel
    let history: HistoryModel
    let dictionary: DictionaryModel
    let snippets: SnippetModel
    let open: (MainWindowView.Destination) -> Void
    @AppStorage(Pref.userName) private var userName = ""
    @AppStorage(Pref.holdKey) private var holdKey = HoldKey.rightOption
    @AppStorage(Pref.toggleShortcut) private var toggle = ToggleShortcut.controlOptionSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(welcome).font(.esy(30, .semibold)).accessibilityAddTraits(.isHeader)

            // Permissions are tied to the app's signature, so they can silently go missing after an update.
            let needsHold = holdKey != .off && !permissions.inputMonitoring
            if permissions.microphone != .allowed || !permissions.accessibility || needsHold {
                VStack(alignment: .leading, spacing: 10) {
                    Text("EsyType needs your permission").font(.esy(16, .semibold))
                    Text("If System Settings already shows EsyType switched on, select it, remove it with –, then allow it again here.")
                        .font(.esy(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if permissions.microphone != .allowed {
                        PermissionRow(title: "Microphone", detail: "Needed to hear you",
                                      granted: false, action: { Task { await permissions.requestMicrophone() } })
                    }
                    if !permissions.accessibility {
                        PermissionRow(title: "Accessibility", detail: "Needed to type into your apps (otherwise text is copied)",
                                      granted: false, action: permissions.requestAccessibility)
                    }
                    if needsHold {
                        PermissionRow(title: "Input Monitoring", detail: "Needed for holding \(holdKey.keyCap ?? "the key") to talk",
                                      granted: false, action: permissions.requestInputMonitoring)
                    }
                }
                .esyCard()
                .task {
                    while !Task.isCancelled {
                        permissions.refresh()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    hero
                    numbers.frame(width: 280)
                }
                VStack(alignment: .leading, spacing: 22) { hero; numbers }
            }
            recent
        }
    }

    private var welcome: String {
        let first = userName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Welcome back" : "Welcome back, \(first)"
    }

    private var shortcutLine: String {
        let hold = holdKey.keyCap.map { "Hold \($0) in any app and speak." }
        let press = toggle.keyCap.map { "Or press \($0) to start and stop." }
        return ([hold ?? press] + (hold != nil ? [press] : [])).compactMap { $0 }.joined(separator: " ")
            + " It all stays on this Mac."
    }

    /// The shared page banner (no ✕ here: this is home).
    private var hero: some View {
        PageHero("dictation", headline: Text("Your voice, typed ") + Text("anywhere").italic() + Text("."),
                 message: shortcutLine, dismissible: false) {
            HeroButton("Set your style") { open(.style) }
        }
    }

    /// Total words, speed and streak; then your words, linking to Dictionary and Snippets.
    private var numbers: some View {
        let all = insights.log.summary()
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                stat(all.words.formatted(.number.notation(.compactName)), "total words")
                stat("\(all.wordsPerMinute)", "wpm")
                stat("\(insights.log.streak())", "day streak")
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { open(.insights) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens Insights")
            Rectangle().fill(Brand.hairline).frame(height: 1)
            Button { open(.dictionary) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your words").font(.esy(18, .semibold))
                    Text("\(dictionary.dictionary.activeCount) in your dictionary · \(snippets.library.activeCount) snippets")
                        .font(.esy(13)).foregroundStyle(Brand.inkSecondary)
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .esyGlassCard(cornerRadius: 18, padded: false)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // The system serif has lining figures; Georgia's old-style 0 reads as the letter "o".
            Text(value).font(.system(size: 38, design: .serif)).monospacedDigit()
            Text(label).font(.esy(16)).foregroundStyle(Brand.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Recent dictations grouped by day, newest first.
    private var recent: some View {
        let groups = Dictionary(grouping: history.entries.prefix(40)) { Calendar.current.startOfDay(for: $0.createdAt) }
            .sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 14) {
            if groups.isEmpty {
                Eyebrow("Today")
                Text("Your dictations appear here. Hold \(holdKey.keyCap ?? "your shortcut") in any app and speak.")
                    .font(.esy(14)).foregroundStyle(Brand.inkTertiary)
            }
            ForEach(Array(groups.enumerated()), id: \.element.key) { index, group in
                HStack {
                    Eyebrow(dayTitle(group.key))
                    Spacer()
                    if index == 0 {
                        Button { open(.history) } label: { Image(systemName: "magnifyingglass").font(.system(size: 15)) }
                            .buttonStyle(.plain).foregroundStyle(Brand.inkSecondary).accessibilityLabel("Search history")
                    }
                }
                .padding(.top, index == 0 ? 0 : 10)
                VStack(spacing: 0) {
                    ForEach(Array(group.value.enumerated()), id: \.element.id) { row, entry in
                        if row > 0 { Rectangle().fill(Brand.hairline).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.esy(13)).foregroundStyle(Brand.inkTertiary).frame(width: 90, alignment: .leading)
                            Text(entry.text).font(.esy(15)).lineLimit(3).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 28).padding(.vertical, 18)
                    }
                }
                .esyGlassCard(cornerRadius: 18, padded: false)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.wide).day().year())
    }
}

/// EsyMeet is the next phase. Shown honestly as planned, so the sidebar matches the Windows design.
private struct EsyMeetPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) { PageTitle("EsyMeet"); PreviewBadge(text: "Soon") }
            Text("Live meeting transcription on this Mac. Not built yet: it’s the next phase.")
                .font(.esy(15, .light)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text("Planned").font(.esy(13, .semibold))
                ForEach(["When Teams, Zoom or a browser starts using the microphone, a small prompt asks once. It never records by itself.",
                         "The transcript grows during the meeting: your microphone as “You”, the call’s sound as “Others”. You can rename both.",
                         "Meetings get their own searchable history, with Copy transcript, Export and Copy for AI.",
                         "Audio is not kept. Transcripts stay on this Mac."], id: \.self) { line in
                    Label(line, systemImage: "circle").labelStyle(.titleOnly).font(.esy(13)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .esyCard()
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandMark(bars: 12, barWidth: 3, spacing: 3, height: 44).opacity(0.8)
            Text(title).font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader)
            Text(message).font(.esy(15, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 40)
    }
}
