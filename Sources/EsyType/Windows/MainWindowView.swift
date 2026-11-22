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

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Destination.groups.indices, id: \.self) { index in
                    let group = Destination.groups[index]
                    Section {
                        ForEach(group.items) { item in
                            Label(item.title, systemImage: item.symbol)
                                .font(.esy(13))
                                .badge(item == .meet ? Text("Soon") : nil) // EsyMeet is the next phase, not built yet
                                .tag(item)
                        }
                    } header: {
                        if let title = group.title { Text(title) }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Text("EsyType.")
                    .font(.esyDisplay(26))
                    .tracking(-0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .accessibilityLabel("EsyType")
                    .accessibilityAddTraits(.isHeader)
            }
            .safeAreaInset(edge: .bottom) {
                Text(engineSummary)
                    .font(.esy(11, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .onAppear { selection = Destination(rawValue: remembered).flatMap { $0 == .settings ? nil : $0 } ?? .dictation }
            .onChange(of: selection) { old, new in
                if new == .settings { // a window, not a page: open it and stay where we were
                    openSettings()
                    selection = old ?? .dictation
                } else if let new {
                    remembered = new.rawValue
                }
            }
        } detail: {
            ScrollView {
                Group {
                    switch selection ?? .dictation {
                    case .dictation, .settings:
                        DictationHome(models: models, permissions: permissions, insights: insights) { selection = .insights }
                    case .meet: EsyMeetPreview()
                    case .insights: InsightsView(insights: insights)
                    case .history: HistoryView(history: history)
                    case .dictionary:
                        VStack(alignment: .leading, spacing: 4) {
                            PageTitle("Dictionary")
                            DictionaryTab(model: dictionary).padding(.horizontal, -20)
                        }
                    case .snippets: SnippetsView(model: snippets)
                    case .style: TextCleanupView()
                    case .scratchpad: ScratchpadView()
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

/// The Dictation home: how to dictate, this week at a glance, a place to try it, and the last dictation.
private struct DictationHome: View {
    let models: ModelLibrary
    let permissions: Permissions
    let insights: InsightsModel
    let openInsights: () -> Void
    @State private var tryText = ""
    @AppStorage(Pref.holdKey) private var holdKey = HoldKey.rightOption
    @AppStorage(Pref.toggleShortcut) private var toggle = ToggleShortcut.controlOptionSpace
    @AppStorage(Pref.typingWPM) private var typingWPM = 40.0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let hold = holdKey.keyCap { Text("Hold"); KeyCap(hold); Text(", speak, release.").padding(.leading, -7) }
                    else if let press = toggle.keyCap { Text("Press"); KeyCap(press); Text(", speak, press again.").padding(.leading, -7) }
                    else { Text("Choose a shortcut in Settings.") }
                }
                .font(.esyDisplay(32)).tracking(-0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(holdKey.keyCap.map { "Hold \($0), speak, release." }
                                    ?? toggle.keyCap.map { "Press \($0), speak, press again." } ?? "Choose a shortcut in Settings.")
                .accessibilityAddTraits(.isHeader)
                Text(subline).font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

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

            Button(action: openInsights) {
                let week = insights.log.summary(lastDays: 7)
                HStack(spacing: 0) {
                    figure(week.words.formatted(), "words this week")
                    figure("\(Int((week.secondsSaved(typingWPM: typingWPM) / 60).rounded())) min", "saved, by EsyType’s estimate")
                    figure(week.dictations.formatted(), "dictations")
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .esyCard()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Insights")

            VStack(alignment: .leading, spacing: 10) {
                Text("Try it").font(.esy(13, .semibold))
                TextEditor(text: $tryText)
                    .font(.esy(14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 88)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) {
                        if tryText.isEmpty {
                            Text("Click here, then hold the shortcut and speak.").font(.esy(14)).foregroundStyle(.tertiary)
                                .padding(14).allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.hairlineStrong))
                    .accessibilityLabel("Try it here")
            }
            .esyCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Last dictation").font(.esy(13, .semibold))
                if let last = insights.last {
                    Text(lastDetails(last)).font(.esy(12)).foregroundStyle(.secondary)
                    Text(last.text).font(.esy(15)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your last dictation appears here. It’s kept in memory only.").font(.esy(12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .esyCard()
        }
    }

    private var subline: String {
        var parts: [String] = []
        if holdKey != .off, let press = toggle.keyCap { parts.append("Or press \(press) to start and again to stop.") }
        parts.append("Esc cancels. Text goes where your cursor was.")
        return parts.joined(separator: " ")
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.esyDisplay(28)).tracking(-0.5)
            Text(label).font(.esy(12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func lastDetails(_ last: InsightsModel.LastDictation) -> String {
        let parts = [last.app, "\(Int(last.spokenSeconds.rounded())) s spoken",
                     "typed in \(last.typingSeconds.formatted(.number.precision(.fractionLength(1)))) s"]
            + (last.cleaned ? ["Clean"] : [])
        return parts.joined(separator: " · ")
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
