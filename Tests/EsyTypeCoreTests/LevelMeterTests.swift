import Testing
@testable import EsyTypeCore

@Test func silenceAndInvalidInputAreZero() {
    #expect(LevelMeter.normalized(rms: 0) == 0)
    #expect(LevelMeter.normalized(rms: -1) == 0)
    #expect(LevelMeter.normalized(rms: .nan) == 0)
    #expect(LevelMeter.normalized(rms: 0.000_01) == 0) // -100 dB, below the floor
}

@Test func fullScaleIsOneAndMidpointIsHalf() {
    #expect(LevelMeter.normalized(rms: 1) == 1)
    #expect(LevelMeter.normalized(rms: 2) == 1) // clipped input clamps
    let minus25dB = Float(0.056_234_13) // 10^(-25/20)
    #expect(abs(LevelMeter.normalized(rms: minus25dB) - 0.5) < 0.001)
}

@Test func historyKeepsNewestValuesInOrder() {
    var history = LevelHistory(count: 3)
    #expect(history.values == [0, 0, 0])
    for level: Float in [0.1, 0.2, 0.3, 0.4] { history.append(level) }
    #expect(history.values == [0.2, 0.3, 0.4])
    history.append(5)
    history.append(.infinity)
    #expect(history.values == [0.4, 1, 0])
}
