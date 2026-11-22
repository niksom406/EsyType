import AppKit
import ApplicationServices
import AVFoundation
import Observation

/// Live status of the three macOS permissions EsyType uses. Call `refresh()` while a permission screen is visible:
/// macOS sends no notification when the user changes these in System Settings.
@MainActor @Observable
final class Permissions {
    enum Microphone { case notAsked, allowed, denied }

    private(set) var microphone: Microphone = .notAsked
    private(set) var accessibility = false
    private(set) var inputMonitoring = false

    init() { refresh() }

    func refresh() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
        accessibility = AXIsProcessTrusted()
        inputMonitoring = CGPreflightListenEventAccess()
    }

    func requestMicrophone() async {
        if microphone == .denied { return open(pane: "Privacy_Microphone") }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    /// Adds EsyType to the Accessibility list (switched off) and opens the pane so the user can switch it on.
    func requestAccessibility() {
        // Literal key: kAXTrustedCheckOptionPrompt is a mutable global, which Swift 6 rejects.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        open(pane: "Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        // CGRequestListenEventAccess alone didn't add EsyType to the list on macOS 26 (2026-11-22); trying a tap also registers it.
        if !CGRequestListenEventAccess(),
           let probe = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                         eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                         callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) {
            CFMachPortInvalidate(probe)
        }
        open(pane: "Privacy_ListenEvent")
    }

    func open(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
