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
        NSApp.appearance = NSAppearance(named: .darkAqua)
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
        render(HistoryView(history: history).padding(40), NSSize(width: 720, height: 560), "history", folder)
        render(MainWindowView(models: models, history: history, dictionary: sampleDictionary(folder),
                              snippets: SnippetModel(store: SnippetStore(url: folder.appending(path: "snapshot-snippets.json"))),
                              permissions: permissions, openSettings: {}), NSSize(width: 820, height: 560), "main", folder)
        render(ModelsView(models: models).padding(40), NSSize(width: 720, height: 560), "models", folder)
        for step in OnboardingView.Step.allCases {
            render(OnboardingView(permissions: permissions, models: models, onFinish: {}, step: step),
                   NSSize(width: 640, height: 500), "onboarding-\(step.rawValue)-\(step)", folder)
        }
        let phases: [OverlayModel.Phase] = [.listening, .handsFree, .transcribing, .inserted, .copied, .error("No speech detected")]
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.4)) // let SwiftUI lay out and start its tasks
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
}
#endif
