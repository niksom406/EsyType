import AppKit

/// Short macOS system sounds (in /System/Library/Sounds), so no audio files are downloaded or bundled.
public enum RecordingSound: String, CaseIterable, Sendable {
    case start = "Tink"
    case stop = "Pop"

    /// Plays at `volume` (0...1). A copy, so a quick stop right after a start isn't cut off.
    @MainActor @discardableResult
    public func play(volume: Float) -> Bool {
        guard let sound = NSSound(named: rawValue)?.copy() as? NSSound else { return false }
        sound.volume = volume
        return sound.play()
    }
}
