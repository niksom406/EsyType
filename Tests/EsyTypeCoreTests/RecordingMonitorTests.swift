import EsyTypeCore
import Testing

// Simulated: levels are fed by the test. Real-microphone checks are in Documentation/STAGE_1_TEST_REPORT.md.
private let speech: Float = 0.05, room: Float = 0.001 // ≈ -26 dBFS and -60 dBFS

/// Feeds 100 ms chunks from `from` to `to` (seconds after start 0).
private func feed(_ m: inout RecordingMonitor, _ rms: Float, from: Double, to: Double) {
    for t in stride(from: from, to: to, by: 0.1) { m.audio(rms: rms, seconds: 0.1, at: t) }
}

@Test func warnsAfterSilenceButNotBefore() {
    var m = RecordingMonitor(start: 0, limit: 1200, silenceWarning: 5)
    feed(&m, room, from: 0, to: 4.9)
    #expect(m.notice(at: 4.9) == nil)
    feed(&m, room, from: 4.9, to: 5.1)
    #expect(m.notice(at: 5.1) == .noSpeech)
    feed(&m, speech, from: 5.1, to: 5.6) // the user starts talking: the warning goes away and stays away
    #expect(m.notice(at: 5.6) == nil)
}

@Test func pausesAfterSpeechNeverWarn() {
    var m = RecordingMonitor(start: 0, limit: 1200, silenceWarning: 5)
    feed(&m, speech, from: 0, to: 2)
    feed(&m, room, from: 2, to: 30)
    #expect(m.notice(at: 30) == nil)
}

@Test func clicksAndTheStartSoundAreNotSpeech() {
    var m = RecordingMonitor(start: 0, limit: 1200, silenceWarning: 5)
    feed(&m, speech, from: 0, to: 0.3) // start sound during the grace period
    feed(&m, room, from: 0.3, to: 2)
    m.audio(rms: speech, seconds: 0.1, at: 2) // one key click
    feed(&m, room, from: 2.1, to: 5.2)
    #expect(m.notice(at: 5.2) == .noSpeech)
}

@Test func tellsSilenceFromNoSignalAndFromAStoppedMicrophone() {
    var zero = RecordingMonitor(start: 0, limit: 1200, silenceWarning: 5)
    feed(&zero, 0, from: 0, to: 5.1) // a muted or virtual device delivers exact zeros
    #expect(zero.notice(at: 5.1) == .noSignal)

    var stalled = RecordingMonitor(start: 0, limit: 1200, silenceWarning: 5)
    feed(&stalled, speech, from: 0, to: 2)
    #expect(stalled.notice(at: 3.4) == nil)
    #expect(stalled.notice(at: 3.6) == .inputStopped) // no audio for over 1.5 s
}

@Test func warnsBeforeTheLimitThenCountsDown() {
    var m = RecordingMonitor(start: 0, limit: 1200, silenceWarning: 5)
    feed(&m, speech, from: 0, to: 1)
    m.audio(rms: room, seconds: 0.1, at: 1139)
    #expect(m.notice(at: 1139) == nil) // 61 s left
    m.audio(rms: room, seconds: 0.1, at: 1140)
    #expect(m.notice(at: 1140) == .limitSoon) // 19 minutes in
    m.audio(rms: room, seconds: 0.1, at: 1190.5)
    #expect(m.notice(at: 1190.5) == .stopping(seconds: 10))
    m.audio(rms: room, seconds: 0.1, at: 1199.2)
    #expect(m.notice(at: 1199.2) == .stopping(seconds: 1))
}

@Test func silenceWarningCanBeTurnedOff() {
    var m = RecordingMonitor(start: 0, limit: 1200, silenceWarning: nil)
    feed(&m, room, from: 0, to: 20)
    #expect(m.notice(at: 20) == nil)
}

@Test func microphoneCheckVerdicts() {
    #expect(MicrophoneCheck([]) == .noAudio)
    #expect(MicrophoneCheck([Float](repeating: 0, count: 16_000)) == .silentSignal)
    if case .tooQuiet = MicrophoneCheck([Float](repeating: 0.001, count: 16_000)) {} else { Issue.record("expected too quiet") }
    if case .working = MicrophoneCheck([Float](repeating: 0.05, count: 16_000)) {} else { Issue.record("expected working") }
}

@Test func recordingSoundsExistOnThisMac() async {
    for sound in RecordingSound.allCases { // macOS system sounds; plays silently (volume 0)
        #expect(await sound.play(volume: 0), "\(sound.rawValue) didn't load")
    }
}
