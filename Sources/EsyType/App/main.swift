import AppKit

// AppKit lifecycle (ARCHITECTURE ADR-10): explicit control of the status item, windows and overlay panel.
Pref.registerDefaults() // before anything reads a preference

#if DEBUG
if Snapshots.runIfRequested() { exit(0) }
#endif

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
