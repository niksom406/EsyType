import Testing
@testable import EsyTypeCore

private func run(_ events: [DictationMachine.Event]) -> (DictationMachine, [DictationMachine.Effect]) {
    var machine = DictationMachine()
    let effects = events.map { machine.handle($0) }
    return (machine, effects)
}

@Test func holdThenReleaseTranscribes() {
    let (machine, effects) = run([.holdKeyDown(at: 10), .holdKeyUp(at: 12), .transcriptionFinished])
    #expect(effects == [.startRecording(.hold), .stopAndTranscribe, .none])
    #expect(machine.state == .idle)
}

@Test func aShortTapIsDiscarded() {
    let (machine, effects) = run([.holdKeyDown(at: 10), .holdKeyUp(at: 10.29)])
    #expect(effects == [.startRecording(.hold), .discardRecording])
    #expect(machine.state == .idle)
    #expect(run([.holdKeyDown(at: 10), .holdKeyUp(at: 10.3)]).1.last == .stopAndTranscribe)
}

@Test func usingTheKeyAsAModifierDiscards() {
    let (machine, effects) = run([.holdKeyDown(at: 0), .otherKeyWhileHeld, .holdKeyUp(at: 5)])
    #expect(effects == [.startRecording(.hold), .discardRecording, .none])
    #expect(machine.state == .idle)
}

@Test func toggleStartsAndStopsHandsFree() {
    let (machine, effects) = run([.togglePressed(at: 0), .holdKeyDown(at: 1), .holdKeyUp(at: 3), .togglePressed(at: 9)])
    #expect(effects == [.startRecording(.handsFree), .none, .none, .stopAndTranscribe])
    #expect(machine.state == .transcribing)
}

@Test func cancelDiscardsRecordingOrTranscription() {
    #expect(run([.holdKeyDown(at: 0), .cancel]).1 == [.startRecording(.hold), .discardRecording])
    #expect(run([.togglePressed(at: 0), .cancel]).1 == [.startRecording(.handsFree), .discardRecording])
    let (machine, effects) = run([.togglePressed(at: 0), .togglePressed(at: 2), .cancel])
    #expect(effects.last == .discardTranscription)
    #expect(machine.state == .idle)
    #expect(run([.cancel]).1 == [.none]) // Esc when idle does nothing
}

@Test func busyTranscribingRejectsANewStart() {
    let (machine, effects) = run([.holdKeyDown(at: 0), .holdKeyUp(at: 2), .holdKeyDown(at: 3), .togglePressed(at: 4)])
    #expect(effects.suffix(2) == [.none, .none])
    #expect(machine.state == .transcribing)
}

@Test func endedRecordingKeepsTheAudio() {
    #expect(run([.togglePressed(at: 0), .recordingEnded]).1.last == .stopAndTranscribe)
    #expect(run([.holdKeyDown(at: 0), .recordingEnded]).1.last == .stopAndTranscribe)
    #expect(run([.recordingEnded]).1 == [.none])
}

// Stage 5 (Simulated events). Real key presses are in Documentation/STAGE_5_TEST_REPORT.md.

@Test func doubleTapLatchesHandsFreeAndDoubleTapStops() {
    let (machine, effects) = run([
        .holdKeyDown(at: 10), .holdKeyUp(at: 10.1),        // tap 1: discarded, mic never opened (150 ms delay)
        .holdKeyDown(at: 10.3), .holdKeyUp(at: 10.4),      // tap 2 within 0.4 s: hands-free; its release is ignored
        .holdKeyDown(at: 15), .holdKeyUp(at: 15.1),        // tap while recording: nothing yet
        .holdKeyDown(at: 15.3),                            // second tap: stop and transcribe
    ])
    #expect(effects == [.startRecording(.hold), .discardRecording, .startRecording(.handsFree), .none,
                        .none, .none, .stopAndTranscribe])
    #expect(machine.state == .transcribing)
}

@Test func slowTapsOrDoubleTapOffDoNotLatch() {
    #expect(run([.holdKeyDown(at: 10), .holdKeyUp(at: 10.1), .holdKeyDown(at: 10.6)]).1.last == .startRecording(.hold))
    var machine = DictationMachine()
    machine.doubleTap = false
    let effects = [DictationMachine.Event.holdKeyDown(at: 10), .holdKeyUp(at: 10.1), .holdKeyDown(at: 10.2)].map { machine.handle($0) }
    #expect(effects.last == .startRecording(.hold))
}

@Test func repeatedAndMixedShortcutsNeverStartASecondSession() {
    // Key repeat, the toggle while holding, and a hold key press during hands-free: one session only.
    let (machine, effects) = run([.togglePressed(at: 1), .togglePressed(at: 1.0), .transcriptionFinished,
                                  .holdKeyDown(at: 5), .togglePressed(at: 5.5), .holdKeyDown(at: 5.6)])
    #expect(effects == [.startRecording(.handsFree), .stopAndTranscribe, .none, .startRecording(.hold), .none, .none])
    #expect(machine.state == .recording(.hold, since: 5))
}

@Test func aDoubleTapAfterTranscribingStartsFresh() {
    let (_, effects) = run([.togglePressed(at: 1), .togglePressed(at: 2), .holdKeyDown(at: 2.1), .holdKeyUp(at: 2.15),
                            .transcriptionFinished, .holdKeyDown(at: 9)])
    #expect(effects.last == .startRecording(.hold)) // taps while transcribing are ignored, not remembered
}
