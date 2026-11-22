import AppKit
import EsyTypeCore
import ServiceManagement
import SwiftUI
import WhisperEngine

/// Standard macOS preferences window: toolbar tabs, one SwiftUI form per tab.
enum SettingsTabs {
    @MainActor static func make(permissions: Permissions, models: ModelLibrary, history: HistoryModel) -> NSTabViewController {
        let controller = NSTabViewController()
        controller.tabStyle = .toolbar
        let tabs: [(String, String, AnyView)] = [
            ("General", "gearshape", AnyView(GeneralTab())),
            ("Shortcuts", "keyboard", AnyView(ShortcutsTab())),
            ("Recording", "mic", AnyView(RecordingTab())),
            ("Speech", "waveform", AnyView(SpeechTab(models: models))),
            ("History & Privacy", "lock.shield", AnyView(PrivacyTab(history: history))),
            ("Permissions", "checkmark.shield", AnyView(PermissionsTab(permissions: permissions))),
            ("About", "info.circle", AnyView(AboutTab())),
        ]
        for (title, symbol, view) in tabs {
            // The toolbar tabs need about 600 pt; narrower hides About behind a "more" chevron.
            let hosting = NSHostingController(rootView: view.frame(width: 660).fixedSize())
            hosting.sizingOptions = .preferredContentSize
            hosting.title = title // the window shows the selected tab's name instead of "Untitled"
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            controller.addTabViewItem(item)
        }
        return controller
    }
}

private struct GeneralTab: View {
    @AppStorage(Appearance.defaultsKey) private var appearance = Appearance.dark
    @AppStorage(OverlayController.hideFromCaptureKey) private var hideFromCapture = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: appearance) { Appearance.apply() }
            Toggle("Hide recording overlay from screen sharing", isOn: $hideFromCapture)
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        guard on != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            } footer: {
                if let loginError { Text(loginError).font(.esy(12)).foregroundStyle(Brand.warning) }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutsTab: View {
    @AppStorage(Pref.holdKey) private var holdKey = HoldKey.rightOption
    @AppStorage(Pref.toggleShortcut) private var toggle = ToggleShortcut.controlOptionSpace
    @AppStorage(Pref.doubleTap) private var doubleTap = true

    var body: some View {
        Form {
            Section {
                Picker("Push to talk (hold)", selection: $holdKey) {
                    ForEach(HoldKey.allCases) { Text($0.title).tag($0) }
                }
                Picker("Hands-free (press to start and stop)", selection: $toggle) {
                    ForEach(ToggleShortcut.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Double-tap the push-to-talk key for hands-free", isOn: $doubleTap)
                    .disabled(holdKey == .off)
            } footer: {
                Text("Hold keys need Input Monitoring. Pressed with other keys or modifiers, they work as usual and don’t start dictation.")
                    .font(.esy(12)).foregroundStyle(.secondary)
            }
            LabeledContent("Cancel while recording") { KeyCap("Esc") }
            LabeledContent("Paste last transcript") { KeyCap("⌃⌘V") }
            LabeledContent("Undo last dictation") { KeyCap("⌃⌘Z") }
        }
        .formStyle(.grouped)
    }
}

struct SpeechTab: View {
    let models: ModelLibrary
    @AppStorage(Pref.modelID) private var modelID = ""
    @AppStorage(Pref.language) private var language = ""
    @AppStorage(Pref.translate) private var translate = false

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $modelID) {
                    Text("Recommended (\(models.recommendedModel.name))").tag("")
                    ForEach(ModelCatalog.all.filter(models.isInstalled)) { Text("\($0.name) · \($0.quantisation)").tag($0.id) }
                }
                Picker("Language", selection: $language) {
                    Text("Auto-detect").tag("")
                    ForEach(WhisperCppEngine.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
            } footer: {
                Text(models.activeModel.map { "Using \($0.name) · \($0.quantisation). Download more in EsyType ▸ Models." }
                     ?? "No model installed yet. Download one in EsyType ▸ Models.")
                    .font(.esy(12)).foregroundStyle(.secondary)
            }
            Toggle("Translate to English", isOn: $translate)
            LabeledContent("Filler words, repeats, punctuation") { Text("EsyType ▸ Text Cleanup").foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyTab: View {
    let history: HistoryModel
    @AppStorage(Pref.historyDays) private var days = 30
    @AppStorage(Pref.saveSourceApp) private var saveSourceApp = true
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Text("Nothing leaves this Mac.").font(.esyDisplay(26)).tracking(-0.6)
                Text("Your voice is transcribed on this Mac. EsyType has no account, no cloud service and no analytics. It only connects to the internet to download speech models. Audio is never saved.")
                    .font(.esy(13)).foregroundStyle(.secondary)
            }
            Section {
                Picker("Keep history", selection: $days) {
                    Text("Forever").tag(0)
                    Text("30 days").tag(30)
                    Text("7 days").tag(7)
                    Text("Don’t keep history").tag(-1)
                }
                .onChange(of: days) { history.reload() } // applies a shorter limit straight away
                Toggle("Remember which app you dictated into", isOn: $saveSourceApp)
                LabeledContent("Saved dictations") {
                    Button("Clear History…") { confirmClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { history.clearAll() }
        } message: {
            Text("This can’t be undone.")
        }
    }
}

struct PermissionsTab: View {
    let permissions: Permissions

    var body: some View {
        Form {
            PermissionRow(title: "Microphone", detail: "Hears you only while you’re dictating",
                          granted: permissions.microphone == .allowed,
                          action: { Task { await permissions.requestMicrophone() } })
            PermissionRow(title: "Accessibility", detail: "Pastes your text into the app you’re using",
                          granted: permissions.accessibility, action: permissions.requestAccessibility)
            PermissionRow(title: "Input Monitoring (optional)", detail: "Only for single-key shortcuts like Right ⌥",
                          granted: permissions.inputMonitoring, action: permissions.requestInputMonitoring)
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Brand.success : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.esy(14))
                Text(detail).font(.esy(12)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Allowed").font(.esy(12)).foregroundStyle(Brand.success)
            } else {
                Button("Allow…", action: action).font(.esy(13))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? "Allowed" : "Not allowed")
    }
}

private struct AboutTab: View {
    /// Licence texts shipped in the app bundle (Scripts/build-app.sh copies them).
    private static let acknowledgements: String = {
        let notices = [("whisper.cpp, the speech engine", "Licences", "whisper.cpp-LICENSE"),
                       ("Barlow font", "Fonts", "OFL-Barlow"),
                       ("Instrument Serif font", "Fonts", "OFL-InstrumentSerif")]
        let models = "Speech models: OpenAI Whisper (MIT licence), in the ggml format published by the whisper.cpp project. They are downloaded from Hugging Face when you choose them and are not part of this app."
        return ([models] + notices.map { title, folder, name in
            let text = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: folder)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "(licence file missing from this build)"
            return "\(title)\n\n\(text)"
        }).joined(separator: "\n\n――――――――\n\n")
    }()

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
            Text("EsyType").font(.esyDisplay(32))
            Text("Version \(version) · Beta").font(.esy(12)).foregroundStyle(.secondary)
            Text("Private voice typing by EsyAI. Make Life Esy.").font(.esy(13))
            Link("esyai.co.uk", destination: URL(string: "https://esyai.co.uk")!).font(.esy(13))
            Text("Fonts: Barlow and Instrument Serif, SIL Open Font License 1.1.")
                .font(.esy(11)).foregroundStyle(.secondary)
            DisclosureGroup("Acknowledgements") {
                ScrollView {
                    Text(Self.acknowledgements)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
            }
            .font(.esy(13))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
