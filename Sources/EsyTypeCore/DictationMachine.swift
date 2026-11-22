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

    public private(set) var state = State.idle

    public init() {}

    public mutating func handle(_ event: Event) -> Effect {
        switch (state, event) {
        case (.idle, .holdKeyDown(let time)):
            state = .recording(.hold, since: time)
            return .startRecording(.hold)
        case (.idle, .togglePressed(let time)):
            state = .recording(.handsFree, since: time)
            return .startRecording(.handsFree)

        case (.recording(.hold, let since), .holdKeyUp(let time)):
            state = time - since < Self.minimumHold ? .idle : .transcribing
            return state == .idle ? .discardRecording : .stopAndTranscribe
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
}
