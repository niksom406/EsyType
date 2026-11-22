import AVFoundation
import Testing
@testable import EsyTypeCore

/// A 1 s, 440 Hz sine at amplitude 0.5 in the given format.
private func sine(rate: Double, channels: AVAudioChannelCount) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate))!
    buffer.frameLength = buffer.frameCapacity
    for channel in 0..<Int(channels) {
        for i in 0..<Int(rate) { buffer.floatChannelData![channel][i] = 0.5 * sin(2 * .pi * 440 * Float(i) / Float(rate)) }
    }
    return buffer
}

@Test(arguments: [(48_000.0, 1), (44_100.0, 2), (16_000.0, 1)] as [(Double, AVAudioChannelCount)])
func convertsTo16kMono(rate: Double, channels: AVAudioChannelCount) throws {
    let input = sine(rate: rate, channels: channels)
    let converter = try #require(AVAudioConverter(from: input.format, to: AudioRecorder.format))
    converter.downmix = true
    // Two chunks, like consecutive tap callbacks: the converter keeps its state between them.
    let output = AudioRecorder.convert(input, with: converter) + AudioRecorder.convert(input, with: converter)
    #expect(abs(output.count - 32_000) <= 16) // 2 s at 16 kHz, less a few samples of filter delay
    let rms = AudioRecorder.rms(Array(output.dropFirst(1_000).prefix(16_000)))
    #expect(abs(rms - Float(0.5 / 2.0.squareRoot())) < 0.02) // a sine's RMS survives resampling and downmix
}

@Test func silenceDetectionFindsAShortPhraseInALongClip() {
    var clip = [Float](repeating: 0.000_1, count: 16_000 * 600) // 10 min of -80 dB hiss
    for i in 0..<8_000 { clip[16_000 * 300 + i] = 0.05 * sin(Float(i) * 0.2) } // 0.5 s of speech-level sound
    #expect(!AudioRecorder.isSilent(clip))
    #expect(AudioRecorder.isSilent([Float](repeating: 0.000_1, count: 16_000 * 5)))
    #expect(AudioRecorder.isSilent([Float](repeating: 0.5, count: 4_000))) // 0.25 s is too short
}

@Test func peakDecibelsFindsTheLoudestWindow() {
    var clip = [Float](repeating: 0, count: 16_000)
    for i in 8_000..<9_600 { clip[i] = 0.1 } // one 100 ms window at -20 dBFS
    #expect(abs(AudioRecorder.peakDecibels(clip) - (-20)) < 0.01)
    #expect(AudioRecorder.peakDecibels([Float](repeating: 0, count: 1_600)) == -.infinity)
}

@Test func rmsOfSilenceIsZero() {
    #expect(AudioRecorder.rms([]) == 0)
    #expect(AudioRecorder.rms([Float](repeating: 0, count: 100)) == 0)
}
