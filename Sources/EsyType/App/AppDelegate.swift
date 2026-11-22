import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    static let onboardingDoneKey = "hasCompletedOnboarding"

    private let permissions = Permissions()
    private lazy var overlay = OverlayController()
    private let models = ModelLibrary()
    private let history = HistoryModel()
    private let dictionary = DictionaryModel()
    private let snippets = SnippetModel()
    private let insights = InsightsModel()
    private lazy var windows = WindowController(permissions: permissions, models: models, history: history, dictionary: dictionary,
                                                     snippets: snippets, insights: insights)
    private lazy var modelItem = disabled("No speech model installed")
    private var dictation: DictationController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Another copy (e.g. one in Applications, one in a build folder) already runs: show it instead of competing for the shortcuts.
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0 != .current }), let url = other.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
            return NSApp.terminate(nil)
        }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        UserDefaults.standard.register(defaults: [
            Appearance.defaultsKey: Appearance.dark.rawValue,
            OverlayController.hideFromCaptureKey: true,
        ])
        Appearance.apply()
        dictation = DictationController(overlay: overlay, models: models, history: history, dictionary: dictionary,
                                         snippets: snippets, insights: insights)
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.dictation?.hotkeys.reload() }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image
        item.button?.setAccessibilityLabel("EsyType")
        item.menu = makeMenu()
        statusItem = item
        NSApp.mainMenu = makeMainMenu()

        if !UserDefaults.standard.bool(forKey: Self.onboardingDoneKey) {
            windows.show(.onboarding)
        } else if !atLogin {
            windows.show(.main) // opened by hand: show something, the menu-bar icon may be hidden by the notch
        }
    }

    /// Opening EsyType again (Spotlight, Finder, Dock) while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.show(UserDefaults.standard.bool(forKey: Self.onboardingDoneKey) ? .main : .onboarding)
        return false
    }

    // Input Monitoring may have just been allowed in System Settings.
    func applicationDidBecomeActive(_ notification: Notification) { dictation?.hotkeys.enableHoldKey() }

    func applicationWillTerminate(_ notification: Notification) { dictation?.shutDown() }

    // Menu-bar apps keep running with no windows open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        menu.addItem(disabled("EsyType \(version) · Beta"))
        menu.addItem(modelItem)
        menu.delegate = self
        menu.addItem(.separator())

        let start = item("Start/Stop Dictation", #selector(toggleDictation))
        start.keyEquivalent = " "
        start.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(start)
        let paste = item("Paste Last Transcript", #selector(pasteLast))
        paste.keyEquivalent = "v"
        paste.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(paste)
        let undo = item("Undo Last Dictation", #selector(undoLast))
        undo.keyEquivalent = "z"
        undo.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(undo)
        menu.addItem(item("Preview Recording Overlay", #selector(previewOverlay)))
        menu.addItem(.separator())

        menu.addItem(item("Open EsyType…", #selector(openMain)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Welcome Guide…", #selector(openOnboarding)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit EsyType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// Shown while a window is open. The Edit menu is what makes ⌘C, ⌘V and ⌘A work in text fields.
    private func makeMainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(item("Settings…", #selector(openSettings), key: ","))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Hide EsyType", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(NSMenuItem(title: "Quit EsyType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"),
                                     ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let main = NSMenu()
        for menu in [app, edit, window] {
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }
        return main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        modelItem.title = models.activeModel.map { "Model: \($0.name) · \($0.quantisation)" } ?? "No speech model installed"
    }

    @objc private func toggleDictation() { dictation?.toggle() }
    @objc private func pasteLast() { dictation?.pasteLast() }
    @objc private func undoLast() { dictation?.undoLast() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action != #selector(pasteLast) || dictation?.lastTranscript != nil
    }
    @objc private func previewOverlay() { overlay.playPreview() }
    @objc private func openMain() { windows.show(.main) }
    @objc private func openSettings() { windows.show(.settings) }
    @objc private func openOnboarding() { windows.show(.onboarding) }
}

/// Three vertical bars: the EsyAI mark reduced to a menu-bar template image (adapts to light/dark menu bars).
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for (x, height) in [(4.0, 8.0), (8.0, 14.0), (12.0, 10.0)] {
                NSBezierPath(roundedRect: NSRect(x: x, y: (18 - height) / 2, width: 2.2, height: height),
                             xRadius: 1.1, yRadius: 1.1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
