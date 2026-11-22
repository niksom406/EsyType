import AppKit
import AVFoundation
import EsyTypeCore
import os
import WhisperEngine

/// Shortcut → recorder → whisper.cpp → typed into the app the user was in (or copied when that isn't safe).
@MainActor
final class DictationController {
    let hotkeys = Hotkeys()
    private var machine = DictationMachine()
    private let recorder = AudioRecorder()
    private let dictionary: DictionaryModel
    private let snippets: SnippetModel
    private let insights: InsightsModel
    private let overlay: OverlayController
    private let models: ModelLibrary
    private let history: HistoryModel
    private var model: ModelInfo?
    private var loading: (id: String, task: Task<WhisperCppEngine, Error>)?
    private var transcription: Task<Void, Never>?
    private var pendingStart: Task<Void, Never>?
    private var idleUnload: Task<Void, Never>?
    private let memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
    /// Metal on Apple Silicon. Intel Macs use the CPU until Metal is measured on real Intel GPUs (ARCHITECTURE).
    private let useGPU = HardwareDetector.current().isAppleSilicon
    /// The model (0.25–1.1 GB) is freed after this long without dictation; the next dictation reloads it (~0.1–0.3 s).
    static let unloadAfter = Duration.seconds(600)
    private var target: pid_t?
    /// While recording: decides the pill's warnings (no speech, no signal, mic stopped, time limit).
    private var monitor: RecordingMonitor?
    private var monitorLoop: Task<Void, Never>?
    private var startedAt: TimeInterval = 0
    /// True once real audio arrived, so the stop sound only follows a start sound.
    private var captureLive = false
    /// Whether the last recording ever reached speech level. Near-silence makes Whisper invent text
    /// (seen 2026-11-22: a -49.5 dBFS room recording became "ʕ˘ 그림 ʔʔ nonsense ʔ" after 8 s).
    private var heardSpeech = true
    /// In memory only, for Paste Last Transcript; cleared when EsyType quits.
    private(set) var lastTranscript: String?
    /// Stages and timings only. Never the transcript or audio (CLAUDE.md).
    private static let log = Logger(subsystem: "co.uk.esyai.esytype", category: "dictation")

    init(overlay: OverlayController, models: ModelLibrary, history: HistoryModel, dictionary: DictionaryModel,
         snippets: SnippetModel, insights: InsightsModel) {
        self.dictionary = dictionary
        self.snippets = snippets
        self.insights = insights
        self.overlay = overlay
        self.models = models
        self.history = history
        hotkeys.onEvent = { [weak self] in self?.handle($0) }
        hotkeys.onPasteLast = { [weak self] in self?.pasteLast() }
        hotkeys.onUndo = { [weak self] in self?.undoLast() }
        overlay.onUndo = { [weak self] in self?.undoLast() }
        hotkeys.onConflict = { [weak overlay] message in
            Self.log.error("Shortcut not registered: \(message, privacy: .public)")
            overlay?.finish(.error(message))
        }
        overlay.onCancel = { [weak self] in self?.handle(.cancel) }
        overlay.onStop = { [weak self] in self?.handle(.togglePressed(at: ProcessInfo.processInfo.systemUptime)) }
        recorder.onAudio = { rms, seconds in
            let now = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                self?.overlay.addLevel(LevelMeter.normalized(rms: rms))
                self?.monitor?.audio(rms: rms, seconds: seconds, at: now)
            }
        }
        recorder.onStarted = { Task { @MainActor [weak self] in self?.microphoneLive() } }
        recorder.onEnded = { Task { @MainActor [weak self] in self?.handle(.recordingEnded) } }
        hotkeys.start()
        memoryPressure.setEventHandler { [weak self] in
            MainActor.assumeIsolated { if self?.machine.state == .idle { self?.loading = nil } }
        }
        memoryPressure.activate()
    }

    /// Frees whisper before exit: whisper.cpp's Metal cleanup at exit aborts while a model is still loaded
    /// (crash reports 2026-11-22 19:02 and 19:09, ggml_metal_rsets_free on Quit).
    func unloadModel() {
        idleUnload?.cancel()
        loading = nil
    }

    /// Removes the last dictation if it's untouched (TextInserter.undoLast). Only the outcome is logged.
    func undoLast() {
        guard machine.state == .idle else { return }
        switch TextInserter.undoLast() {
        case .undone:
            Self.log.notice("Undo last dictation: done")
            overlay.finish(.undone)
        case .unavailable(let reason):
            Self.log.notice("Undo last dictation: \(reason, privacy: .public)")
            overlay.finish(.error(reason))
        }
    }

    /// Quitting mid-session: release the microphone and drop the session, then free the model.
    func shutDown() {
        pendingStart?.cancel()
        transcription?.cancel()
        if case .recording = machine.state { _ = recorder.stop() }
        unloadModel()
    }

    func toggle() { handle(.togglePressed(at: ProcessInfo.processInfo.systemUptime)) }

    func pasteLast() {
        guard let text = lastTranscript, machine.state == .idle else { return }
        let target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { if await TextInserter.insert(text, into: target) == .copied { overlay.finish(.copied) } }
    }

    private func handle(_ event: DictationMachine.Event) {
        machine.doubleTap = UserDefaults.standard.bool(forKey: Pref.doubleTap)
        let effect = machine.handle(event)
        hotkeys.escapeActive = machine.state != .idle
        switch effect {
        case .none: break
        case .startRecording(.handsFree): start(handsFree: true)
        case .startRecording(.hold):
            // Wait 150 ms so ⌥E, ⌥← and other ⌥ shortcuts never switch the microphone on.
            pendingStart = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { self?.start(handsFree: false) }
            }
        case .stopAndTranscribe: transcribe(stopRecording())
        case .discardRecording:
            pendingStart?.cancel()
            _ = stopRecording()
            overlay.hide()
            scheduleUnload()
        case .discardTranscription:
            transcription?.cancel()
            overlay.hide()
            scheduleUnload()
        }
    }

    private func start(handsFree: Bool) {
        idleUnload?.cancel()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined: // e.g. after an update changed the signature: ask right here
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            return fail("Allow the microphone, then try again.")
        default:
            return fail("Allow microphone access in EsyType ▸ Home or Settings ▸ Permissions.")
        }
        guard let model = models.activeModel else { return fail("Download a speech model in EsyType ▸ Models.") }
        let defaults = UserDefaults.standard
        recorder.deviceUID = defaults.string(forKey: Pref.microphoneUID) ?? ""
        recorder.maxSeconds = min(max(defaults.double(forKey: Pref.maxRecordingSeconds), 10), 30 * 60)
        startedAt = ProcessInfo.processInfo.systemUptime
        captureLive = false
        do {
            try recorder.start()
        } catch {
            return fail(error.localizedDescription)
        }
        self.model = model
        target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Self.log.notice("Recording started (\(handsFree ? "hands-free" : "hold", privacy: .public), model \(model.id, privacy: .public), input \(self.recorder.inputDescription, privacy: .public)\(self.recorder.usedFallback ? ", chosen microphone missing" : "", privacy: .public))")
        overlay.begin(handsFree: handsFree)
        watch(silenceWarning: defaults.bool(forKey: Pref.noSpeechWarning) ? defaults.double(forKey: Pref.silenceSeconds) : nil)
        _ = engine(for: model) // load while the user speaks
    }

    /// Re-checks the warnings 4×/s while recording. Only stages are logged, never audio or text.
    private func watch(silenceWarning: TimeInterval?) {
        monitor = RecordingMonitor(start: startedAt, limit: recorder.maxSeconds, silenceWarning: silenceWarning)
        let fallback = recorder.usedFallback
        monitorLoop = Task { [weak self] in
            var shown: String?
            while !Task.isCancelled, let self, let monitor = self.monitor {
                let now = ProcessInfo.processInfo.systemUptime
                let text = monitor.notice(at: now).map(Self.text)
                    ?? (fallback && now - self.startedAt < 4 ? "Mic missing. Using default" : nil)
                if text != shown {
                    if let notice = monitor.notice(at: now) { Self.log.notice("Recording notice: \(String(describing: notice), privacy: .public)") }
                    self.overlay.notice(text)
                    shown = text
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private static func text(_ notice: RecordingMonitor.Notice) -> String {
        switch notice {
        case .noSpeech: "Can’t hear you. Check mic"
        case .noSignal: "Mic sends no sound"
        case .inputStopped: "Mic stopped sending audio"
        case .limitSoon: "1 min left"
        case .stopping(let seconds): "Stopping in \(seconds) s"
        }
    }

    /// The first audio arrived: the microphone is really recording.
    private func microphoneLive() {
        guard monitor != nil, !captureLive else { return }
        captureLive = true
        Self.log.notice("Microphone live after \(Int((ProcessInfo.processInfo.systemUptime - self.startedAt) * 1000)) ms")
        playSound(.start, if: Pref.startSound)
    }

    private func playSound(_ sound: RecordingSound, if key: String) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: key) else { return }
        let played = sound.play(volume: Float(defaults.double(forKey: Pref.soundVolume)))
        Self.log.notice("\(sound == .start ? "Start" : "Stop", privacy: .public) sound \(played ? "played" : "failed", privacy: .public)")
    }

    /// Every stop goes through here: Esc, release, ■, the limit, a lost microphone.
    private func stopRecording() -> [Float] {
        monitorLoop?.cancel()
        heardSpeech = monitor?.heardSpeech ?? true
        monitor = nil
        let samples = recorder.stop()
        if captureLive { playSound(.stop, if: Pref.stopSound) }
        captureLive = false
        if samples.count >= Int(recorder.maxSeconds * AudioRecorder.sampleRate) {
            Self.log.notice("Stopped at the \(Int(self.recorder.maxSeconds), privacy: .public) s limit; transcribing all of it")
        }
        return samples
    }

    private func transcribe(_ samples: [Float]) {
        overlay.set(.transcribing)
        Self.log.notice("Recorded \(Double(samples.count) / 16_000, format: .fixed(precision: 1)) s, loudest \(AudioRecorder.peakDecibels(samples), format: .fixed(precision: 1)) dBFS")
        guard let model, heardSpeech, !AudioRecorder.isSilent(samples) else {
            Self.log.notice("Not transcribed: no speech (speech heard \(self.heardSpeech, privacy: .public), model \(self.model != nil, privacy: .public))")
            return finish(.error("No speech detected"))
        }
        let engine = engine(for: model)
        let defaults = UserDefaults.standard
        let language = defaults.string(forKey: Pref.language).flatMap { $0.isEmpty ? nil : $0 }
        let translate = defaults.bool(forKey: Pref.translate), cleanup = Pref.cleanupOptions
        let app = target.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        let started = ContinuousClock.now
        let words = dictionary.engine, prompt = words.prompt(language: language), expander = snippets.engine
        transcription = Task {
            do {
                let result = try await engine.value.transcribe(samples, language: language, translate: translate, prompt: prompt)
                Self.log.notice("Transcribed \(samples.count / 16_000) s of audio in \(ContinuousClock.now - started, privacy: .public)")
                let cleaned = TextCleanup.clean(result.text, options: cleanup, language: translate ? "en" : result.language)
                // Exact replacements after cleanup; the count only is logged, never the words.
                let (text, replaced) = words.apply(to: cleaned, language: translate ? "en" : result.language)
                if replaced > 0 { Self.log.notice("Dictionary replacements: \(replaced)") }
                // Snippets last, so dictionary rules never change a snippet's saved text. Counts only in the log.
                let (expanded, expansions) = expander.expand(text, language: translate ? "en" : result.language)
                if expansions > 0 { Self.log.notice("Snippets expanded: \(expansions)") }
                guard !Task.isCancelled else { return }
                if text.isEmpty {
                    // Counts only, never the text: tells "Whisper heard nothing" from "cleanup removed everything".
                    Self.log.notice("No words: whisper returned \(result.text.count) characters, language \(result.language, privacy: .public)")
                    return finish(.error("No speech detected"))
                }
                lastTranscript = expanded // Paste Last types what was typed
                // Saved before pasting, so nothing is lost if the paste lands nowhere. History keeps the transcript
                // before snippet expansion, so saved addresses and signatures aren't copied into it every time.
                history.save(text, language: result.language, durationMs: samples.count / 16,
                             modelID: model.id, appBundleID: app)
                endSession() // Esc can't interrupt the paste and clipboard restore below
                let appName = target.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "your app"
                insights.record(.init(app: appName, spokenSeconds: Double(samples.count) / AudioRecorder.sampleRate,
                                      typingSeconds: (ContinuousClock.now - started) / .seconds(1),
                                      cleaned: cleaned != result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                      text: expanded), bundleID: app)
                let outcome = await TextInserter.insert(expanded, into: target)
                Self.log.notice("Dictation \(outcome == .inserted ? "inserted" : "copied to the clipboard", privacy: .public)")
                overlay.finish(outcome == .inserted ? .typed(into: appName) : .copied)
            } catch where !Task.isCancelled {
                Self.log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                if error is WhisperError { loading = nil } // retry the load next time
                finish(.error(error.localizedDescription))
            } catch {} // Esc: the result is dropped
        }
    }

    private func finish(_ phase: OverlayModel.Phase) {
        overlay.finish(phase)
        endSession()
    }

    private func endSession() {
        _ = machine.handle(.transcriptionFinished)
        hotkeys.escapeActive = false
        scheduleUnload()
    }

    /// Restarted every time dictation goes back to idle.
    private func scheduleUnload() {
        idleUnload?.cancel()
        idleUnload = Task { [weak self] in
            try? await Task.sleep(for: Self.unloadAfter)
            if !Task.isCancelled, self?.machine.state == .idle { self?.loading = nil } // frees whisper's memory
        }
    }

    private func fail(_ message: String) {
        Self.log.error("Dictation stopped: \(message, privacy: .public)")
        machine = DictationMachine()
        hotkeys.escapeActive = false
        scheduleUnload()
        overlay.finish(.error(message))
    }

    private func engine(for model: ModelInfo) -> Task<WhisperCppEngine, Error> {
        if let loading, loading.id == model.id { return loading.task }
        let url = ModelStore.defaultDirectory.appending(path: model.file)
        // Measured on the M4: CPU decoding is ~19 % faster on all cores than whisper's default 4; Metal is best at 4.
        let useGPU = useGPU, threads = useGPU ? nil : HardwareDetector.physicalCores
        let task = Task.detached(priority: .userInitiated) {
            try WhisperCppEngine(model: url, useGPU: useGPU, threads: threads)
        }
        loading = (model.id, task)
        return task
    }
}
