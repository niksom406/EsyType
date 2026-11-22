import Foundation

/// Turns microphone loudness into the 0...1 bar heights the recording overlay draws.
public enum LevelMeter {
    /// Quietest level that still shows movement. Below this a bar sits at rest.
    public static let floorDecibels: Float = -50

    /// Maps an RMS amplitude (0...1, full scale = 1) to 0...1 on a decibel scale,
    /// so normal speech fills the bars instead of hugging the bottom.
    public static func normalized(rms: Float) -> Float {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, 1 - decibels / floorDecibels))
    }
}

/// The most recent levels, oldest first, at a fixed length (one value per bar).
public struct LevelHistory: Equatable, Sendable {
    public private(set) var values: [Float]

    public init(count: Int) {
        precondition(count > 0, "LevelHistory needs at least one bar")
        values = Array(repeating: 0, count: count)
    }

    public mutating func append(_ level: Float) {
        values.removeFirst()
        values.append(min(1, max(0, level.isFinite ? level : 0)))
    }
}
