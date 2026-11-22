import AVFoundation
import EsyTypeCore
import Foundation
import Testing
import WhisperEngine

/// jfk.wav from whisper.cpp tag b5454 (11.0 s, 16 kHz mono). See LICENCES.md.
private let jfk = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/jfk.wav")

private func samples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    #expect(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

private func words(_ text: String) -> String {
    text.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == " " }
        .map(String.init).joined()
}

private func installedFile(_ model: ModelInfo) -> URL? {
    let url = ModelStore.defaultDirectory.appending(path: model.file)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

@Test func rejectsAFileThatIsNotAModel() {
    #expect(throws: WhisperError.cannotLoadModel) { try WhisperCppEngine(model: jfk) }
}

@Test(arguments: ModelCatalog.all.filter { installedFile($0) != nil }) // no cases until a model is installed
func transcribesEnglish(model: ModelInfo) async throws {
    let engine = try WhisperCppEngine(model: installedFile(model)!)
    let result = try await engine.transcribe(samples(jfk))
    #expect(result.language == "en")
    #expect(words(result.text).contains("ask not what your country can do for you"))
}

/// esytype.wav: macOS `say -v Samantha` (16 kHz mono), "Can EsyType recognise my speech? I am testing EsyType today."
@Test(arguments: ModelCatalog.all.filter { installedFile($0) != nil })
func promptSpellsTheAppName(model: ModelInfo) async throws {
    let engine = try WhisperCppEngine(model: installedFile(model)!)
    let audio = try samples(jfk.deletingLastPathComponent().appending(path: "esytype.wav"))
    let result = try await engine.transcribe(audio, prompt: TextCleanup.whisperPrompt)
    #expect(result.text.components(separatedBy: "EsyType").count - 1 == 2)
    #expect(result.text.hasSuffix("."), "the hint must not cost punctuation")
}

/// Benchmark one model per process: `ESYTYPE_BENCH_MODEL=small-q8 Scripts/test.sh --filter benchmark`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ESYTYPE_BENCH_MODEL"] != nil))
func benchmark() async throws {
    let id = ProcessInfo.processInfo.environment["ESYTYPE_BENCH_MODEL"]!
    let model = try #require(ModelCatalog.all.first { $0.id == id })
    let file = try #require(installedFile(model))
    let audio = try samples(jfk)
    let clock = ContinuousClock()
    let before = footprintMB(peak: false)

    var engine: WhisperCppEngine?
    let load = try clock.measure {
        engine = try WhisperCppEngine(model: file, useGPU: ProcessInfo.processInfo.environment["ESYTYPE_CPU"] == nil,
                                      threads: ProcessInfo.processInfo.environment["ESYTYPE_THREADS"].flatMap { Int($0) })
    }
    var first: Transcript?
    let cold = try await clock.measure { first = try await engine!.transcribe(audio) }
    var warm: [Duration] = []
    for _ in 0..<3 { warm.append(try await clock.measure { _ = try await engine!.transcribe(audio) }) }
    let median = warm.sorted()[1]
    let short = Array(audio.prefix(48_000)) // a typical 3 s dictation
    var shortRuns: [Duration] = []
    for _ in 0..<3 { shortRuns.append(try await clock.measure { _ = try await engine!.transcribe(short) }) }
    let peak = footprintMB(peak: true)
    engine = nil // what the app's idle unload does
    let seconds = { (d: Duration) in Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
    print(String(format: "BENCH model=%@ load=%.2fs first=%.2fs warm11s=%.2fs rtf=%.3f warm3s=%.2fs beforeMB=%.0f peakMB=%.0f afterUnloadMB=%.0f text=%@",
                 id, seconds(load), seconds(cold), seconds(median), seconds(median) / 11.0, seconds(shortRuns.sorted()[1]),
                 before, peak, footprintMB(peak: false), first!.text))
}

/// 30 minutes of audio in one call: `ESYTYPE_BENCH_MODEL=small-q8 ESYTYPE_LONG_AUDIO=1 Scripts/test.sh --filter longAudio`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ESYTYPE_LONG_AUDIO"] != nil), .timeLimit(.minutes(20)))
func longAudio() async throws {
    let id = ProcessInfo.processInfo.environment["ESYTYPE_BENCH_MODEL"] ?? "small-q8"
    let model = try #require(ModelCatalog.all.first { $0.id == id })
    let clip = try samples(jfk)
    let repeats = 30 * 60 * 16_000 / clip.count // the app's 30-minute cap
    let audio = [[Float]](repeating: clip, count: repeats).flatMap { $0 }
    let engine = try WhisperCppEngine(model: try #require(installedFile(model)))
    let clock = ContinuousClock()
    var result: Transcript?
    let elapsed = try await clock.measure { result = try await engine.transcribe(audio, language: "en") }
    let found = words(result!.text).components(separatedBy: "ask not what your country").count - 1
    print("LONG model=\(id) audio=\(audio.count / 16_000)s repeats=\(repeats) time=\(elapsed) found=\(found) peakMB=\(Int(footprintMB(peak: true)))")
    #expect(Double(found) >= Double(repeats) * 0.9) // nearly every repetition transcribed, no early stop
}

private func footprintMB(peak: Bool) -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return (peak ? Double(info.ledger_phys_footprint_peak) : Double(info.phys_footprint)) / 1e6
}

@Test func listsWhisperLanguages() {
    let codes = WhisperCppEngine.languages.map(\.code)
    #expect(codes.count >= 99)
    #expect(codes.contains("hi") && codes.contains("mr") && codes.first == "en")
}

/// Load/unload cycles must not grow memory: `ESYTYPE_BENCH_MODEL=small-q8 Scripts/test.sh --filter unloadCycles`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ESYTYPE_BENCH_MODEL"] != nil))
func unloadCycles() async throws {
    let model = try #require(ModelCatalog.all.first { $0.id == ProcessInfo.processInfo.environment["ESYTYPE_BENCH_MODEL"] })
    let audio = try samples(jfk)
    var after: [Int] = []
    for _ in 0..<4 {
        var engine: WhisperCppEngine? = try WhisperCppEngine(model: try #require(installedFile(model)),
                                                             useGPU: ProcessInfo.processInfo.environment["ESYTYPE_CPU"] == nil)
        _ = try await engine!.transcribe(audio)
        engine = nil
        let freed = Int(footprintMB(peak: false))
        malloc_zone_pressure_relief(nil, 0) // what the app does after unloading
        after.append(Int(footprintMB(peak: false)))
        print("CYCLE beforeRelief=\(freed) afterRelief=\(after.last!)")
    }
    print("CYCLES model=\(model.id) afterEachUnloadMB=\(after)")
    #expect(after.last! - after[1] < 30) // no growth after the first cycle's one-time setup
}
