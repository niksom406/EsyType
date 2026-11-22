import AVFoundation
import EsyTypeCore
import SwiftUI

/// Settings ▸ Recording: microphone, sounds, warnings and the length limit.
struct RecordingTab: View {
    @AppStorage(Pref.microphoneUID) private var microphoneUID = ""
    @AppStorage(Pref.startSound) private var startSound = true
    @AppStorage(Pref.stopSound) private var stopSound = true
    @AppStorage(Pref.soundVolume) private var volume = 0.5
    @AppStorage(Pref.noSpeechWarning) private var noSpeechWarning = true
    @AppStorage(Pref.silenceSeconds) private var silenceSeconds = 5.0
    @AppStorage(Pref.maxRecordingSeconds) private var maxSeconds = 1200.0
    @State private var microphones = MicrophoneList()
    @State private var test = MicrophoneTest()

    private var missing: Bool { !microphoneUID.isEmpty && !microphones.inputs.contains { $0.uid == microphoneUID } }

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $microphoneUID) {
                    Text("System default (\(microphones.defaultName))").tag("")
                    ForEach(microphones.inputs) { Text($0.name).tag($0.uid) }
                    if missing { Text("Chosen microphone (not connected)").tag(microphoneUID) }
                }
                LabeledContent("Test") {
                    HStack(spacing: 10) {
                        if test.running {
                            LevelBars(levels: test.levels.values, height: 18)
                            Text("Speak now…").font(.esy(12)).foregroundStyle(.secondary)
                        } else if let result = test.result {
                            Text(result).font(.esy(12)).foregroundStyle(test.ok ? Brand.success : Brand.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(test.running ? "Stop" : "Test Microphone") {
                            test.running ? test.finish() : test.run(uid: microphoneUID)
                        }
                    }
                }
            } footer: {
                Text(missing ? "That microphone isn’t connected. EsyType uses the system default until it’s back."
                             : "The test records 5 seconds, shows the level, then discards it. Nothing is saved.")
                    .font(.esy(12)).foregroundStyle(missing ? Brand.warning : .secondary)
            }
            Section("Sounds") {
                Toggle("Sound when recording starts", isOn: $startSound)
                Toggle("Sound when recording stops", isOn: $stopSound)
                Slider(value: $volume, in: 0.1...1) { Text("Volume") } onEditingChanged: { editing in
                    if !editing { RecordingSound.start.play(volume: Float(volume)) }
                }
                .disabled(!startSound && !stopSound)
            }
            Section {
                Toggle("Warn when no speech is heard", isOn: $noSpeechWarning)
                Picker("Warn after", selection: $silenceSeconds) {
                    ForEach([3.0, 5.0, 10.0], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                .disabled(!noSpeechWarning)
                Picker("Maximum recording length", selection: $maxSeconds) {
                    ForEach([5.0, 10.0, 20.0, 30.0], id: \.self) { Text("\(Int($0)) minutes").tag($0 * 60) }
                }
            } footer: {
                Text("Pauses between sentences never warn. Near the limit you’re warned at 1 minute and 10 seconds; everything recorded is still transcribed.")
                    .font(.esy(12)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { test.finish() }
    }
}

/// The connected microphones, refreshed when one is plugged in or removed.
@MainActor @Observable
private final class MicrophoneList {
    var inputs = AudioInputs.all()
    var defaultName = AudioInputs.defaultID.flatMap(AudioInputs.name(of:)) ?? "none"
    @ObservationIgnored private var watcher: AudioInputWatcher?

    init() {
        watcher = AudioInputWatcher { Task { @MainActor [weak self] in self?.refresh() } }
    }

    private func refresh() {
        inputs = AudioInputs.all()
        defaultName = AudioInputs.defaultID.flatMap(AudioInputs.name(of:)) ?? "none"
    }
}

/// Records 5 seconds from the chosen microphone, in memory, and reports how loud it was.
@MainActor @Observable
private final class MicrophoneTest {
    var running = false
    var levels = LevelHistory(count: 24)
    var result: String?
    var ok = false
    @ObservationIgnored private var recorder: AudioRecorder?

    func run(uid: String) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            (result, ok) = ("Allow the microphone in Permissions first.", false)
            return
        }
        let recorder = AudioRecorder()
        recorder.deviceUID = uid
        recorder.maxSeconds = 5
        recorder.onAudio = { rms, _ in Task { @MainActor [weak self] in self?.levels.append(LevelMeter.normalized(rms: rms)) } }
        recorder.onEnded = { Task { @MainActor [weak self] in self?.finish() } }
        do { try recorder.start() } catch {
            (result, ok) = (error.localizedDescription, false)
            return
        }
        self.recorder = recorder
        levels = LevelHistory(count: 24)
        running = true
    }

    func finish() {
        guard let recorder else { return }
        let samples = recorder.stop() // discarded below: only the level is kept
        self.recorder = nil
        running = false
        switch MicrophoneCheck(samples) {
        case .noAudio: (result, ok) = ("No audio arrived. Is the microphone connected?", false)
        case .silentSignal: (result, ok) = ("Silent signal: the microphone is muted or virtual.", false)
        case .tooQuiet(let db): (result, ok) = ("Too quiet (\(Int(db)) dBFS). Move closer or raise Input volume in Sound settings.", false)
        case .working(let db): (result, ok) = ("Working (\(Int(db)) dBFS).", true)
        }
    }
}
