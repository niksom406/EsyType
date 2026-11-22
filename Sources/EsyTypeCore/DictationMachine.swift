import Foundation

/// Shortcut rules for one dictation at a time. Pure: the app turns each returned effect into recorder/engine calls.
public struct DictationMachine: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case hold, handsFree }
    public enum State: Equatable, Sendable { case idle, recording(Mode, since: TimeInterval), transcribing }

    public enum Event: Equatable, Sendable {
        case holdKeyDown(at: TimeInterval)
        case holdKeyUp(at: TimeInterval)
        /// Another key was pressed while the hold key was down, so it was being used as a modifier (⌥E, ⌥←).
        case otherKeyWhileHeld
        case togglePressed(at: TimeInterval)
        case cancel
        /// Recording hit the length cap or the microphone went away: keep what was captured.
        case recordingEnded
        case transcriptionFinished
    }

    public enum Effect: Equatable, Sendable {
        case none
        case startRecording(Mode)
        case stopAndTranscribe
        case discardRecording
        case discardTranscription
    }

    /// Shorter holds are taps, not dictation.
    public static let minimumHold: TimeInterval = 0.3
    /// Two taps of the hold key this close together (release to press) latch hands-free, or stop it.
    public static let doubleTapWindow: TimeInterval = 0.4

    public private(set) var state = State.idle
    /// Settings ▸ Shortcuts ▸ double-tap. Off: taps are ignored, as before.
    public var doubleTap = true
    private var lastTapEnd: TimeInterval?
    /// The key-up of the press that latched or stopped hands-free is not a tap.
    private var ignoreHoldUp = false

    public init() {}

    public mutating func handle(_ event: Event) -> Effect {
        switch (state, event) {
        case (.idle, .holdKeyDown(let time)):
            if isDoubleTap(at: time) {
                state = .recording(.handsFree, since: time)
                return .startRecording(.handsFree)
            }
            ignoreHoldUp = false
            state = .recording(.hold, since: time)
            return .startRecording(.hold)
        case (.idle, .togglePressed(let time)):
            state = .recording(.handsFree, since: time)
            return .startRecording(.handsFree)

        case (.recording(.hold, let since), .holdKeyUp(let time)):
            guard time - since >= Self.minimumHold else { // a tap: maybe the first of a double-tap
                state = .idle
                lastTapEnd = time
                return .discardRecording
            }
            state = .transcribing
            return .stopAndTranscribe
        case (.recording(.handsFree, _), .holdKeyDown(let time)):
            guard isDoubleTap(at: time) else { return .none }
            state = .transcribing
            return .stopAndTranscribe
        case (.recording(.handsFree, _), .holdKeyUp(let time)):
            if ignoreHoldUp { ignoreHoldUp = false } else { lastTapEnd = time }
            return .none
        case (.recording(.hold, _), .otherKeyWhileHeld):
            state = .idle
            return .discardRecording
        case (.recording(.handsFree, _), .togglePressed), (.recording, .recordingEnded):
            state = .transcribing
            return .stopAndTranscribe
        case (.recording, .cancel):
            state = .idle
            return .discardRecording

        case (.transcribing, .cancel):
            state = .idle
            return .discardTranscription
        case (.transcribing, .transcriptionFinished):
            state = .idle
            return .none

        default: // includes starting while busy transcribing
            return .none
        }
    }

    private mutating func isDoubleTap(at time: TimeInterval) -> Bool {
        guard doubleTap, let last = lastTapEnd, time - last <= Self.doubleTapWindow else { return false }
        lastTapEnd = nil
        ignoreHoldUp = true
        return true
    }
}
