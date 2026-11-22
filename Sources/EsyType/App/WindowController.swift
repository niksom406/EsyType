import AppKit
import SwiftUI

/// Creates each window once and brings it forward on request.
@MainActor
final class WindowController {
    enum Kind { case main, onboarding, settings }

    private let permissions: Permissions
    private let models: ModelLibrary
    private let history: HistoryModel
    private let dictionary: DictionaryModel
    private let snippets: SnippetModel
    private let insights: InsightsModel
    private var windows: [Kind: NSWindow] = [:]

    init(permissions: Permissions, models: ModelLibrary, history: HistoryModel, dictionary: DictionaryModel, snippets: SnippetModel,
         insights: InsightsModel) {
        self.insights = insights
        self.history = history
        self.dictionary = dictionary
        self.snippets = snippets
        self.permissions = permissions
        self.models = models
    }

    func show(_ kind: Kind) {
        let window = windows[kind] ?? make(kind)
        windows[kind] = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make(_ kind: Kind) -> NSWindow {
        let window: NSWindow
        switch kind {
        case .main:
            window = hosting(MainWindowView(models: models, history: history, dictionary: dictionary, snippets: snippets, insights: insights, permissions: permissions, openSettings: { [weak self] in self?.show(.settings) }),
                             title: "EsyType", size: NSSize(width: 1120, height: 740), minSize: NSSize(width: 860, height: 600))
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 860, height: 600)
        case .onboarding:
            window = hosting(OnboardingView(permissions: permissions, models: models, onFinish: { [weak self] in
                UserDefaults.standard.set(true, forKey: AppDelegate.onboardingDoneKey)
                self?.windows[.onboarding]?.close()
                self?.show(.main)
            }), title: "Welcome to EsyType", size: NSSize(width: 640, height: 500))
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        case .settings:
            window = NSWindow(contentViewController: SettingsTabs.make(permissions: permissions, models: models, history: history))
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
        }
        window.isReleasedWhenClosed = false
        return window
    }


    /// `minSize` is how small the window may get (default: the opening size); it can always grow.
    private func hosting(_ view: some View, title: String, size: NSSize, minSize: NSSize? = nil) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        let minimum = minSize ?? size
        window.contentView = NSHostingView(rootView: view
            .frame(minWidth: minimum.width, maxWidth: .infinity, minHeight: minimum.height, maxHeight: .infinity)
            .background(WindowBackground()))
        return window
    }
}
