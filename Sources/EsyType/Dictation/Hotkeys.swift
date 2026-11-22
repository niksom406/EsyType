import AppKit
import Carbon.HIToolbox
import EsyTypeCore
import os

/// Global shortcuts. The toggle, Esc and ⌃⌘V are Carbon hot keys (no permission needed). The hold key uses a
/// listen-only event tap, which needs Input Monitoring; it never sees or changes what you type beyond key codes.
@MainActor
final class Hotkeys {
    var onEvent: (DictationMachine.Event) -> Void = { _ in }
    var onPasteLast: () -> Void = {}
    var onUndo: () -> Void = {}
    /// Called with a message when a shortcut can't be registered (usually another app already uses it).
    var onConflict: (String) -> Void = { _ in }

    /// Esc is only taken from other apps while a dictation is running.
    var escapeActive = false {
        didSet {
            guard escapeActive != oldValue else { return }
            if escapeActive { escapeRef = register(UInt32(kVK_Escape), modifiers: 0, id: Self.escapeID) }
            else if let escapeRef { UnregisterEventHotKey(escapeRef); self.escapeRef = nil }
        }
    }

    private static let toggleID: UInt32 = 1, escapeID: UInt32 = 2, pasteLastID: UInt32 = 3, undoID: UInt32 = 4
    private static let log = Logger(subsystem: "co.uk.esyai.esytype", category: "hotkeys")
    private var handler: EventHandlerRef?
    private var toggleRef: EventHotKeyRef?
    private var registeredToggle: ToggleShortcut?
    private var escapeRef: EventHotKeyRef?
    private var tap: CFMachPort?
    private var holdKey = HoldKey.current
    private var holdKeyDown = false
    private var loggedMissingPermission = false

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData!).takeUnretainedValue()
            let pressed = id.id
            MainActor.assumeIsolated { hotkeys.hotKeyPressed(pressed) } // Carbon calls back on the main thread
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        reload()
        if register(UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | cmdKey), id: Self.pasteLastID) == nil {
            onConflict("⌃⌘V (Paste Last Transcript) is used by another app.")
        }
        if register(UInt32(kVK_ANSI_Z), modifiers: UInt32(controlKey | cmdKey), id: Self.undoID) == nil {
            onConflict("⌃⌘Z (Undo Last Dictation) is used by another app. Use the menu instead.")
        }
        enableHoldKey()
        // Input Monitoring is often allowed in System Settings while another app is in front: keep trying.
        Task { [weak self] in
            while let self, self.tap == nil { // also covers switching the hold key back on in Settings
                try? await Task.sleep(for: .seconds(2))
                self.enableHoldKey()
            }
        }
    }

    /// Applies the shortcut preferences. Safe to call on every defaults change: re-registers only what changed.
    func reload() {
        holdKey = HoldKey.current
        let toggle = ToggleShortcut.current
        guard toggle != registeredToggle else { return }
        registeredToggle = toggle
        if let toggleRef { UnregisterEventHotKey(toggleRef) }
        toggleRef = toggle == .off ? nil : register(UInt32(kVK_Space), modifiers: toggle.carbonModifiers, id: Self.toggleID)
        if toggle != .off, toggleRef == nil {
            onConflict("\(toggle.title) is used by another app. Choose another shortcut in Settings ▸ Shortcuts.")
        }
    }

    /// Starts the hold-key tap once Input Monitoring is allowed. Safe to call repeatedly.
    func enableHoldKey() {
        guard tap == nil, holdKey != .off else { return }
        guard CGPreflightListenEventAccess() else {
            if !loggedMissingPermission { Self.log.notice("Hold key waiting for Input Monitoring permission") }
            loggedMissingPermission = true
            return
        }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue | 1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, userInfo in
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userInfo!).takeUnretainedValue()
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode), flags = event.flags.rawValue
            MainActor.assumeIsolated { hotkeys.handle(type, keyCode: keyCode, flags: flags) } // main run loop source
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Self.log.error("Right Option tap could not be created")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
        Self.log.notice("Hold key listener started")
    }

    private func register(_ key: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x4553_5954 /* ESYT */, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { Self.log.error("Hot key \(id) not registered: \(status) (taken by another app?)") }
        return ref
    }

    private func hotKeyPressed(_ id: UInt32) {
        switch id {
        case Self.escapeID: onEvent(.cancel)
        case Self.pasteLastID: onPasteLast()
        case Self.undoID: onUndo()
        default: onEvent(.togglePressed(at: Self.now))
        }
    }

    private func handle(_ type: CGEventType, keyCode: Int64, flags: UInt64) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged where holdKey != .off && keyCode == holdKey.keyCode:
            let down = flags & holdKey.deviceMask != 0
            guard down != holdKeyDown else { return }
            holdKeyDown = down
            let otherModifiers = CGEventFlags(rawValue: flags)
                .intersection([.maskCommand, .maskControl, .maskShift, .maskAlternate]).subtracting(holdKey.flag)
            let sameKeyOnLeft = flags & holdKey.leftDeviceMask != 0
            if !down {
                onEvent(.holdKeyUp(at: Self.now))
            } else if otherModifiers.isEmpty, !sameKeyOnLeft { // with other modifiers it's part of another shortcut
                onEvent(.holdKeyDown(at: Self.now))
            }
        case .keyDown where holdKeyDown:
            onEvent(.otherKeyWhileHeld)
        default:
            break
        }
    }
}
