import AppKit
import ApplicationServices
import EsyTypeCore
import os

/// Puts a transcript into the app the user was in: borrow the clipboard, send ⌘V, put the clipboard back.
/// Falls back to leaving the text on the clipboard when pasting isn't safe (ARCHITECTURE §4, ADR-6).
@MainActor
enum TextInserter {
    enum Outcome { case inserted, copied }
    private static let log = Logger(subsystem: "co.uk.esyai.esytype", category: "insertion")

    // shortcut: one fixed delay for every app; tune per app from the Phase 6 compatibility matrix.
    static let restoreDelay = Duration.milliseconds(500)

    /// `target` is the app that was frontmost when recording started.
    static func insert(_ text: String, into target: pid_t?) async -> Outcome {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focus = target.flatMap { frontmost == $0 && AXIsProcessTrusted() ? editableFocus($0) : nil }
        let reason: String? = if target == nil { "no target app" }
            else if frontmost != target { "you switched apps" }
            else if !AXIsProcessTrusted() { "Accessibility not allowed" }
            else if focus == nil { "no editable text focus" }
            else { nil }
        guard let target, reason == nil else {
            log.notice("Copied instead of pasting: \(reason ?? "", privacy: .public)")
            Clipboard.write(text)
            return .copied
        }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let ours = Clipboard.write(TextCleanup.spaced(text, after: characterBeforeCursor(focus!)), to: pasteboard)
        let key = Clipboard.pasteKeyCode()
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: key, keyDown: down)
            event?.flags = .maskCommand // ignore modifiers the user may still be holding
            event?.postToPid(target)
        }
        try? await Task.sleep(for: restoreDelay)
        if pasteboard.changeCount == ours { snapshot.restore(to: pasteboard) } // never undo the user's own copy
        return .inserted
    }

    /// The focused element, if something has keyboard focus and it isn't a password field.
    private static func editableFocus(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5) // a hung app must not hang dictation (default is 6 s)
        var focused: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        guard error == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            log.notice("Focused element unavailable: AXError \(error.rawValue, privacy: .public)")
            return nil
        }
        let element = focused as! AXUIElement
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return subrole as? String == kAXSecureTextFieldSubrole ? nil : element
    }

    /// The character just before the cursor, or nil when the app doesn't expose it (then no space is added).
    private static func characterBeforeCursor(_ element: AXUIElement) -> Character? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &selection), selection.location > 0 else { return nil }
        var previous = CFRange(location: selection.location - 1, length: 1) // UTF-16 offsets, as AX reports them
        guard let range = AXValueCreate(.cfRange, &previous) else { return nil }
        var string: CFTypeRef?
        AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, range, &string)
        return (string as? String)?.last
    }
}
