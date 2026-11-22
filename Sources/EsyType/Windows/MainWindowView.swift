import EsyTypeCore
import SwiftUI

struct MainWindowView: View {
    /// The sidebar: Main, Personalisation, System. Every item opens a real screen; Settings opens the Settings window.
    enum Destination: String, CaseIterable, Identifiable {
        case dashboard, dictation, history, dictionary, snippets, cleanup, models, settings
        var id: Self { self }

        static let groups: [(title: String, items: [Destination])] = [
            ("Main", [.dashboard, .dictation, .history]),
            ("Personalisation", [.dictionary, .snippets, .cleanup]),
            ("System", [.models, .settings]),
        ]

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .dictation: "Dictation"
            case .history: "History"
            case .dictionary: "Personal Dictionary"
            case .snippets: "Snippets"
            case .cleanup: "Text Cleanup"
            case .models: "AI & Models"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .dictation: "mic"
            case .history: "clock.arrow.circlepath"
            case .dictionary: "character.book.closed"
            case .snippets: "text.badge.plus"
            case .cleanup: "textformat"
            case .models: "cpu"
            case .settings: "gearshape"
            }
        }
    }

    let models: ModelLibrary
    let history: HistoryModel
    let dictionary: DictionaryModel
    let snippets: SnippetModel
    let permissions: Permissions
    let openSettings: () -> Void
    @AppStorage("mainWindowSection") private var remembered = Destination.dashboard.rawValue
    @State private var selection: Destination?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Destination.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            Label(item.title, systemImage: item.symbol)
                                .font(.esy(13))
                                .tag(item)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Text("EsyType")
                    .font(.esyDisplay(24))
                    .tracking(-0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            .safeAreaInset(edge: .bottom) {
                Text("Runs on this Mac.\nNo account. No cloud.")
                    .font(.esy(11, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .onAppear { selection = Destination(rawValue: remembered).flatMap { $0 == .settings ? nil : $0 } ?? .dashboard }
            .onChange(of: selection) { old, new in
                if new == .settings { // a window, not a page: open it and stay where we were
                    openSettings()
                    selection = old ?? .dashboard
                } else if let new {
                    remembered = new.rawValue
                }
            }
        } detail: {
            ScrollView {
                Group {
                    switch selection ?? .dashboard {
                    case .dashboard, .settings: HomeView(models: models, permissions: permissions)
                    case .dictation: DictationPage()
                    case .history: HistoryView(history: history)
                    case .dictionary:
                        VStack(alignment: .leading, spacing: 4) {
                            PageTitle("Personal Dictionary")
                            DictionaryTab(model: dictionary).padding(.horizontal, -20)
                        }
                    case .snippets: SnippetsView(model: snippets)
                    case .cleanup: TextCleanupView()
                    case .models:
                        VStack(alignment: .leading, spacing: 18) {
                            PageTitle("AI & Models")
                            SpeechTab(models: models).fixedSize(horizontal: false, vertical: true).padding(.horizontal, -20)
                            ModelsView(models: models)
                        }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader) }
}

/// Shortcuts, microphone and recording: the same settings as in Settings, where people look for them first.
private struct DictationPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageTitle("Dictation")
            Text("How you start dictating, which microphone EsyType uses, and what you hear and see while it records.")
                .font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ShortcutsTab().fixedSize(horizontal: false, vertical: true).padding(.horizontal, -20)
            RecordingTab().fixedSize(horizontal: false, vertical: true).padding(.horizontal, -20)
        }
    }
}

private struct HomeView: View {
    let models: ModelLibrary
    let permissions: Permissions
    @State private var tryText = ""
    @AppStorage(Pref.holdKey) private var holdKey = HoldKey.rightOption
    @AppStorage(Pref.toggleShortcut) private var toggle = ToggleShortcut.controlOptionSpace
    @AppStorage(Pref.modelID) private var modelID = "" // re-renders the Model card when the choice changes

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Speak. It’s typed.")
                .font(.esyDisplay(44))
                .tracking(-1.1)
                .accessibilityAddTraits(.isHeader)

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

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let hold = holdKey.keyCap { Text("Hold"); KeyCap(hold); Text("to talk.") }
                    if let press = toggle.keyCap { Text("Press"); KeyCap(press); Text("for hands-free.") }
                    if holdKey == .off, toggle == .off { Text("Choose a shortcut in Settings ▸ Shortcuts.") }
                }
                .font(.esy(14))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

                Text("Try it here").font(.esy(12)).foregroundStyle(.secondary)
                TextEditor(text: $tryText)
                    .font(.esy(14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 88)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.hairlineStrong))
                    .accessibilityLabel("Try it here")
                HStack(spacing: 8) {
                    PreviewBadge(text: "Beta")
                    Text("EsyType types into the app you’re in once Accessibility is allowed. Otherwise the text is copied: press ⌘V.")
                        .font(.esy(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
            .esyCard()

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Model")
                    Text(models.activeModel.map { "\($0.name) · \($0.quantisation)" } ?? "No model installed")
                        .font(.esy(16, .semibold))
                    Text(models.activeModel == nil ? "Download one in Models" : "Installed on this Mac")
                        .font(.esy(12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .esyCard()
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Language")
                    Text("Auto-detect").font(.esy(16, .semibold))
                    Text("One language per dictation").font(.esy(12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .esyCard()
            }
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
