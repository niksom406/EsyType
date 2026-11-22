import Foundation

/// Decides which warning the recording pill shows, from real audio levels and the elapsed time.
/// Times are seconds on one monotonic clock (e.g. `ProcessInfo.systemUptime`).
public struct RecordingMonitor: Sendable {
    public enum Notice: Equatable, Sendable {
        /// Audio arrives but nothing loud enough to be speech yet.
        case noSpeech
        /// Audio arrives but every sample is exactly zero: a muted or virtual device.
        case noSignal
        /// No audio has arrived for a while: the microphone was unplugged or stopped.
        case inputStopped
        /// Less than a minute left before the limit.
        case limitSoon
        /// The last seconds before the limit.
        case stopping(seconds: Int)
    }

    /// About -45 dBFS. Quiet rooms measured -50 dBFS here; speech near a MacBook mic is -35 to -15.
    public static let speechRMS: Float = 0.0056
    /// Speech must add up to this long, so a click or a key press doesn't count.
    static let speechSeconds = 0.25
    /// Ignore the first moment: the start sound itself reaches the microphone.
    static let grace = 0.3
    static let stalledAfter = 1.5

    public let limit: TimeInterval
    public let silenceWarning: TimeInterval?
    private let start: TimeInterval
    private var lastAudio: TimeInterval
    private var speech: TimeInterval = 0
    private var anySignal = false

    /// `silenceWarning` nil turns the no-speech warning off.
    public init(start: TimeInterval, limit: TimeInterval, silenceWarning: TimeInterval?) {
        self.start = start
        self.limit = limit
        self.silenceWarning = silenceWarning
        lastAudio = start
    }

    public var heardSpeech: Bool { speech >= Self.speechSeconds }

    /// One chunk of audio: its RMS and how long it lasts.
    public mutating func audio(rms: Float, seconds: TimeInterval, at time: TimeInterval) {
        lastAudio = time
        if rms > 0 { anySignal = true }
        if rms >= Self.speechRMS, time - start >= Self.grace { speech += seconds }
    }

    public func notice(at now: TimeInterval) -> Notice? {
        let elapsed = now - start, remaining = limit - elapsed
        if elapsed > Self.stalledAfter, now - lastAudio > Self.stalledAfter { return .inputStopped }
        if remaining <= 10 { return .stopping(seconds: max(0, Int(remaining.rounded(.up)))) }
        if remaining <= 60 { return .limitSoon }
        // Only before any speech: pauses between sentences never warn.
        if let silenceWarning, !heardSpeech, elapsed >= silenceWarning { return anySignal ? .noSpeech : .noSignal }
        return nil
    }
}

/// The verdict of Settings ▸ Recording ▸ Test Microphone, from the captured samples.
public enum MicrophoneCheck: Equatable, Sendable {
    case noAudio
    case silentSignal
    case tooQuiet(dBFS: Float)
    case working(dBFS: Float)

    public init(_ samples: [Float]) {
        let peak = AudioRecorder.peakDecibels(samples)
        if samples.isEmpty { self = .noAudio }
        else if !samples.contains(where: { $0 != 0 }) { self = .silentSignal }
        else if 20 * log10(RecordingMonitor.speechRMS) > peak { self = .tooQuiet(dBFS: peak) }
        else { self = .working(dBFS: peak) }
    }
}
