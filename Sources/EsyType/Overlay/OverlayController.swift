import AppKit
import EsyTypeCore
import Observation
import SwiftUI

@MainActor @Observable
final class OverlayModel {
    enum Phase: Equatable { case listening, handsFree, transcribing, typed(into: String), copied, undone, error(String) }

    var phase = Phase.listening
    var isVisible = false
    var elapsed: TimeInterval = 0
    var levels = LevelHistory(count: 28)
    /// A warning shown while recording continues (no speech, time limit).
    var notice: String?
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onUndo: () -> Void = {}
}

/// The floating recording pill. A non-activating panel, so the app you are typing in keeps focus.
@MainActor
final class OverlayController {
    static let hideFromCaptureKey = "hideOverlayFromScreenSharing"

    /// ✕ and ■ during a real dictation. The preview handles its own buttons.
    var onCancel: () -> Void = {}
    var onStop: () -> Void = {}
    /// Undo in the "Typed into …" pill.
    var onUndo: () -> Void = {}

    private let model = OverlayModel()
    private lazy var panel = makePanel()
    private var preview: Task<Void, Never>?
    private var clock: Task<Void, Never>?

    init() {
        model.onCancel = { [weak self] in
            guard let self else { return }
            if preview != nil { return stopPreview() }
            switch model.phase { // ✕ on a finished pill just dismisses it
            case .listening, .handsFree, .transcribing: onCancel()
            default: hide()
            }
        }
        model.onStop = { [weak self] in self?.preview == nil ? self?.onStop() : self?.playPreview(from: 2) }
        model.onUndo = { [weak self] in self?.onUndo() }
    }

    // MARK: Real dictation

    func begin(handsFree: Bool) {
        stopPreview()
        model.levels = LevelHistory(count: 28)
        model.elapsed = 0
        model.notice = nil
        set(handsFree ? .handsFree : .listening)
        show()
        let started = Date()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                self?.model.elapsed = Date().timeIntervalSince(started)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func addLevel(_ level: Float) { model.levels.append(level) }

    func notice(_ text: String?) {
        model.notice = text
        if let text { announce(.error(text)) }
    }

    func set(_ phase: OverlayModel.Phase) {
        if phase != .listening, phase != .handsFree { clock?.cancel() }
        model.phase = phase
        announce(phase)
    }

    /// Shows a final state (copied, error) briefly, then hides.
    func finish(_ phase: OverlayModel.Phase) {
        set(phase)
        show()
        let shown = model.phase
        Task { [weak self] in
            // "Typed into …" keeps its Undo button for 60 s, as in the Windows design; a new dictation replaces it.
            let seconds: Double = if case .typed = phase { 60 } else if phase == .copied { 1.6 } else { 2.4 }
            try? await Task.sleep(for: .seconds(seconds))
            if self?.model.phase == shown { self?.hide() }
        }
    }

    // MARK: Preview

    // The menu's scripted demo with simulated levels.
    private static let script: [(OverlayModel.Phase, TimeInterval)] = [
        (.listening, 3), (.handsFree, 3), (.transcribing, 1.8), (.typed(into: "Notes"), 1.2),
        (.copied, 2.2), (.error("No speech detected"), 2.2),
    ]

    func playPreview() { playPreview(from: 0) }

    private func playPreview(from start: Int) {
        preview?.cancel()
        show()
        preview = Task { [weak self] in
            let started = Date()
            for (phase, seconds) in Self.script.dropFirst(start) {
                guard let self, !Task.isCancelled else { return }
                self.model.phase = phase
                self.announce(phase)
                let end = Date().addingTimeInterval(seconds)
                while Date() < end {
                    try? await Task.sleep(for: .milliseconds(33))
                    if Task.isCancelled { return }
                    self.tick(elapsed: Date().timeIntervalSince(started))
                }
            }
            self?.preview = nil
            self?.hide()
        }
    }

    private func stopPreview() {
        guard let preview else { return }
        preview.cancel()
        self.preview = nil
        hide()
    }

    private func tick(elapsed: TimeInterval) {
        model.elapsed = elapsed
        let speaking = model.phase == .listening || model.phase == .handsFree
        // Syllable-like bursts inside slower phrases, roughly how speech loudness moves.
        let syllable = max(0, sin(elapsed * 9)), phrase = 0.5 + 0.5 * sin(elapsed * 1.3)
        let rms = speaking ? Float(0.003 + 0.25 * syllable * phrase) * .random(in: 0.6...1) : 0
        model.levels.append(LevelMeter.normalized(rms: rms))
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 16))
        }
        panel.sharingType = UserDefaults.standard.bool(forKey: Self.hideFromCaptureKey) ? .none : .readOnly
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.isVisible = true }
    }

    func hide() {
        clock?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { model.isVisible = false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if self?.model.isVisible == false { self?.panel.orderOut(nil) }
        }
    }

    private func announce(_ phase: OverlayModel.Phase) {
        let text = switch phase {
        case .listening: "Recording"
        case .handsFree: "Recording hands-free"
        case .transcribing: "Transcribing"
        case .typed(let app): "Typed into \(app)"
        case .undone: "Dictation undone"
        case .copied: "Copied to clipboard. Press Command V to paste."
        case .error(let message): message
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 96),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the pill draws its own soft shadow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }
}
