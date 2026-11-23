#if DEBUG
import AppKit
import CoreText
import EsyTypeCore
import SwiftUI

/// Debug builds only: `EsyType --render-snapshots <folder>` draws each screen offscreen to PNG for layout review
/// where screen recording isn't available. Glass and materials don't render offscreen, so surfaces look flatter.
@MainActor
enum Snapshots {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-snapshots"), flag + 1 < args.count else { return false }
        let folder = URL(fileURLWithPath: args[flag + 1])
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["ESYTYPE_SNAPSHOT_LIGHT"] == nil ? .darkAqua : .aqua)
        let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Resources/Fonts").standardized
        for file in (try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }

        let permissions = Permissions()
        let models = ModelLibrary()
        let historyURL = folder.appending(path: "snapshot-history.sqlite") // never the user's history
        try? FileManager.default.removeItem(at: historyURL)
        var seeded = false
        Task {
            let store = try? HistoryStore(url: historyURL)
            for (text, language, app) in [("Can we move tomorrow’s call to 3 pm? I’ll send the notes before then.", "en", "com.apple.mail"),
                                          ("मुझे कल सुबह फ़ोन करना, रिपोर्ट तैयार है।", "hi", nil),
                                          ("Buy milk, bread and coffee.", "en", "com.apple.Notes")] {
                _ = try? await store?.add(text: text, language: language, durationMs: 4_200, modelID: "small-q8", appBundleID: app)
            }
            seeded = true
        }
        while !seeded { RunLoop.main.run(until: .now + 0.05) }
        let history = HistoryModel(url: historyURL)
        RunLoop.main.run(until: .now + 0.5) // let the first load finish
        render(HistoryView(history: history).padding(40).background(Brand.canvas), NSSize(width: 980, height: 900), "history", folder)
        let pages: [(String, AnyView)] = [
            ("page-dictionary", AnyView(DictionaryPage(model: sampleDictionary(folder)))),
            ("page-snippets", AnyView(SnippetsView(model: sampleSnippets(folder)))),
            ("page-style", AnyView(StylePage(history: history))),
            ("page-scratchpad", AnyView(ScratchpadView(notes: sampleNotes(folder)))),
            ("page-history", AnyView(HistoryView(history: history))),
        ]
        for (name, page) in pages {
            render(page.padding(40).background(Brand.canvas), NSSize(width: 980, height: 1500), name, folder)
        }
        render(InsightsView(insights: sampleInsights(folder)).padding(40).background(Brand.canvas),
               NSSize(width: 980, height: 1060), "insights", folder)
        render(MainWindowView(models: models, history: history, dictionary: sampleDictionary(folder),
                              snippets: SnippetModel(store: SnippetStore(url: folder.appending(path: "snapshot-snippets.json"))),
                              insights: InsightsModel(store: InsightsStore(url: folder.appending(path: "snapshot-insights.json"))),
                              permissions: permissions, openSettings: {}), NSSize(width: 1120, height: 740), "main", folder)
        render(ModelsView(models: models).padding(40), NSSize(width: 720, height: 560), "models", folder)
        for step in OnboardingView.Step.allCases {
            render(OnboardingView(permissions: permissions, models: models, onFinish: {}, step: step),
                   NSSize(width: 640, height: 500), "onboarding-\(step.rawValue)-\(step)", folder)
        }
        let phases: [OverlayModel.Phase] = [.listening, .handsFree, .transcribing, .typed(into: "Notes"), .copied, .error("No speech detected")]
        for (index, phase) in phases.enumerated() {
            let model = OverlayModel()
            model.phase = phase
            model.isVisible = true
            model.elapsed = 7
            for i in 0..<28 { model.levels.append(Float(0.25 + 0.7 * abs(sin(Double(i) * 0.55)))) }
            render(OverlayView(model: model), NSSize(width: 460, height: 96), "overlay-\(index)", folder)
        }
        let settings = SettingsTabs.make(permissions: permissions, models: models, history: history)
        for (index, item) in settings.tabViewItems.enumerated() {
            settings.selectedTabViewItemIndex = index
            if let view = item.viewController?.view {
                capture(view, NSSize(width: 660, height: max(view.fittingSize.height, 200)), "settings-\(index)", folder)
            }
        }
        return true
    }

    private static func render(_ view: some View, _ size: NSSize, _ name: String, _ folder: URL) {
        capture(NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Brand.canvas).environment(\.esyGlassFallback, true)),
                size, name, folder)
    }

    private static func capture(_ view: NSView, _ size: NSSize, _ name: String, _ folder: URL) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = view
        // Let SwiftUI lay out and start its tasks; ESYTYPE_SNAPSHOT_WAIT lets animations finish before capture.
        RunLoop.current.run(until: Date().addingTimeInterval(Double(ProcessInfo.processInfo.environment["ESYTYPE_SNAPSHOT_WAIT"] ?? "") ?? 0.4))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// A throwaway dictionary seeded with the sample template, never the user's.
    private static func sampleDictionary(_ folder: URL) -> DictionaryModel {
        let store = DictionaryStore(url: folder.appending(path: "snapshot-dictionary.json"))
        try? store.save(PersonalDictionary(DictionaryCSV.sampleEntries))
        return DictionaryModel(store: store)
    }

    /// Throwaway sample days (never the user's numbers) so the Insights layout can be reviewed.
    private static func sampleInsights(_ folder: URL) -> InsightsModel {
        let store = InsightsStore(url: folder.appending(path: "snapshot-insights-sample.json"))
        var log = InsightsLog()
        let apps = ["com.openai.chat", "com.apple.mail", "com.apple.TextEdit", "com.tinyspeck.slackmacgap"]
        for back in stride(from: 120, through: 0, by: -1) where (back * 7) % 5 != 0 {
            let date = Calendar.current.date(byAdding: .day, value: -back, to: Date())!
            let words = 40 + (back * 37) % 260
            log.record(words: words, spokenMs: words * 470, processingMs: 900, bundleID: apps[back % 4], at: date)
        }
        try? store.save(log)
        return InsightsModel(store: store)
    }

    private static func sampleSnippets(_ folder: URL) -> SnippetModel {
        let store = SnippetStore(url: folder.appending(path: "snapshot-snippets-sample.json"))
        try? store.save(SnippetLibrary([
            Snippet(mode: .anywhere, name: "Signature", trigger: "my email signature", text: "Kind regards,\nJo Smith\nEsyAI"),
            Snippet(mode: .whole, name: "Meeting link", trigger: "meeting link", text: "Join here: https://meet.example.com/jo"),
            Snippet(mode: .anywhere, name: "Address", trigger: "my home address", text: "22 Home Road, Pune 411001"),
        ]))
        return SnippetModel(store: store)
    }

    private static func sampleNotes(_ folder: URL) -> NotesModel {
        let store = NotesStore(url: folder.appending(path: "snapshot-notes.json"), legacy: folder.appending(path: "none.txt"))
        try? store.save([Note(text: "Ideas for the launch\nShort video, a blog post, and a note to the beta group."),
                         Note(text: "Call with Priya\nShe will send the figures on Friday.")])
        return NotesModel(store: store)
    }
}
#endif
