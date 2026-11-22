import AppKit
import Carbon.HIToolbox
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
            last = nil
            log.notice("Copied instead of pasting: \(reason ?? "", privacy: .public)")
            Clipboard.write(text)
            return .copied
        }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let typed = TextCleanup.spaced(text, after: characterBeforeCursor(focus!))
        last = Insertion.before(typing: typed, into: focus!, app: target)
        let ours = Clipboard.write(typed, to: pasteboard)
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

    // MARK: Undo

    /// The last text EsyType typed, in memory only: where it went and what it replaced. Never saved to disk.
    struct Insertion {
        let app: pid_t
        let element: AXUIElement
        let location: Int // UTF-16, as Accessibility counts
        let typed: String
        let replaced: String

        @MainActor static func before(typing text: String, into element: AXUIElement, app: pid_t) -> Insertion? {
            guard let range = selectedRange(element) else { return nil } // the app doesn't say where: no undo
            var selected: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
            return Insertion(app: app, element: element, location: range.location, typed: text,
                             replaced: range.length > 0 ? selected as? String ?? "" : "")
        }
    }

    enum UndoResult: Equatable { case undone, unavailable(String) }

    private(set) static var last: Insertion?

    /// Removes the last dictation only if it's still exactly where EsyType typed it, then puts back any text it
    /// replaced. Never sends ⌘Z (that would undo whatever the app did last, maybe the user's own typing).
    static func undoLast() -> UndoResult {
        guard let insertion = last else { return .unavailable("Nothing to undo: the last dictation wasn’t typed by EsyType") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == insertion.app else {
            return .unavailable("Go back to the app you dictated into, then undo")
        }
        let length = (insertion.typed as NSString).length
        guard let before = value(insertion.element), NSMaxRange(NSRange(location: insertion.location, length: length)) <= (before as NSString).length,
              (before as NSString).substring(with: NSRange(location: insertion.location, length: length)) == insertion.typed
        else {
            last = nil
            return .unavailable("Can’t undo: the dictated text was edited or moved")
        }
        let expected = (before as NSString).replacingCharacters(in: NSRange(location: insertion.location, length: length),
                                                                with: insertion.replaced)
        var range = CFRange(location: insertion.location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(insertion.element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
              selectedRange(insertion.element).map({ $0.location == range.location && $0.length == range.length }) == true
        else { return .unavailable("Can’t undo in this app: it doesn’t let EsyType select text") }
        // Replace just that selection. Apps that refuse get a Delete key, but only for exactly that selection.
        if AXUIElementSetAttributeValue(insertion.element, kAXSelectedTextAttribute as CFString, insertion.replaced as CFString) != .success
            || value(insertion.element) != expected {
            guard insertion.replaced.isEmpty, value(insertion.element) == before else {
                return value(insertion.element) == expected ? done() : .unavailable("Can’t undo in this app")
            }
            for down in [true, false] {
                CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: CGKeyCode(kVK_Delete), keyDown: down)?
                    .postToPid(insertion.app)
            }
            usleep(150_000) // the app applies the key asynchronously
            guard value(insertion.element) == expected else { return .unavailable("Can’t undo in this app") }
        }
        return done()
    }

    private static func done() -> UndoResult {
        last = nil
        return .undone
    }

    private static func value(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success ? value as? String : nil
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cfRange, &range)
        else { return nil }
        return range
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
