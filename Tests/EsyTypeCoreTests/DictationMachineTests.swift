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
