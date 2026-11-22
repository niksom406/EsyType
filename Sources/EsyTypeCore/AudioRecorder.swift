@preconcurrency import AVFoundation
import os

public enum RecorderError: Error, Equatable, LocalizedError {
    case noMicrophone

    public var errorDescription: String? { "No microphone is available." }
}

/// Records the default input as 16 kHz mono Float32, in memory only. Nothing is written to disk.
public final class AudioRecorder: @unchecked Sendable {
    public static let sampleRate = 16_000.0
    /// Hard cap: 30 minutes ≈ 115 MB of Float32. The user's limit (`maxSeconds`) can only be lower.
    public static let maxSamples = Int(sampleRate) * 60 * 30
    public static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 1, interleaved: false)!

    /// Called on the audio thread for each captured chunk: its RMS and its length in seconds.
    public var onAudio: @Sendable (_ rms: Float, _ seconds: Double) -> Void = { _, _ in }
    /// Called once on the audio thread when the first audio arrives, i.e. the microphone is really live.
    public var onStarted: @Sendable () -> Void = {}
    /// Called once when recording stops by itself: the length limit was reached, or the input went away.
    public var onEnded: @Sendable () -> Void = {}

    /// Set before `start()`: the microphone's Core Audio UID, "" for the system default.
    public var deviceUID = ""
    /// Set before `start()`: the recording limit, capped at 30 minutes.
    public var maxSeconds: Double = 30 * 60
    /// After `start()`: true when `deviceUID` wasn't connected and the system default was used instead.
    public private(set) var usedFallback = false

    // A fresh engine per recording: one that was pinned to a microphone wouldn't follow the system default again.
    private var engine = AVAudioEngine()
    private struct Capture { var samples: [Float] = []; var running = false; var started = false }
    private let capture = OSAllocatedUnfairLock(initialState: Capture())
    private var configurationObserver: NSObjectProtocol? // main thread only

    public init() {}

    /// Call on the main thread.
    public func start() throws {
        capture.withLock { $0 = Capture(samples: [], running: true) }
        engine = AVAudioEngine()
        // A device change (another default input, or Bluetooth headphones switching to their microphone) stops the
        // engine. Continue on the new input and keep what was captured; end only if there's no input left.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.capture.withLock({ $0.running }) else { return }
            self.engine.stop() // before removeTap, see tearDown()
            self.engine.inputNode.removeTap(onBus: 0)
            do { try self.tapAndStart() } catch { self.endBySelf() }
        }
        do {
            try tapAndStart()
        } catch {
            _ = stop()
            throw error
        }
    }

    private func tapAndStart() throws {
        selectDevice() // before reading the format: each microphone has its own rate and channel count
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let limit = min(Int(maxSeconds * Self.sampleRate), Self.maxSamples)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: Self.format) else { throw RecorderError.noMicrophone }
        converter.downmix = true
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let chunk = Self.convert(buffer, with: converter)
            let (running, first, full) = self.capture.withLock { capture in
                guard capture.running else { return (false, false, false) }
                capture.samples.append(contentsOf: chunk.prefix(limit - capture.samples.count))
                defer { capture.started = true }
                return (true, !capture.started, capture.samples.count >= limit)
            }
            guard running else { return }
            if first { self.onStarted() }
            self.onAudio(Self.rms(chunk), Double(chunk.count) / Self.sampleRate)
            if full { self.endBySelf() }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops and returns everything captured. Call on the main thread.
    public func stop() -> [Float] {
        let captured = capture.withLock { capture in
            defer { capture = Capture() }
            return capture.samples
        }
        tearDown()
        return captured
    }

    /// From the audio thread or a notification: stop capturing now, tell the owner once, tear down on main.
    private func endBySelf() {
        let wasRunning = capture.withLock { capture in
            defer { capture.running = false }
            return capture.running
        }
        guard wasRunning else { return }
        onEnded() // the owner calls stop() to collect the audio
    }

    private func tearDown() {
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer) }
        configurationObserver = nil
        // Stop first: removing the tap while the engine runs let the audio I/O thread call a freed tap and crash
        // (crash report 2026-11-22 15:08, EXC_BAD_ACCESS on com.apple.audio.IOThread.client during stop).
        engine.stop() // releases the microphone, so the orange indicator goes away
        engine.inputNode.removeTap(onBus: 0)
    }

    /// Converts one tap buffer. Feeds it in the slice sizes the converter asks for: it takes at most
    /// 4096 frames per request and drops the rest of a bigger buffer (found in Phase 5 tests).
    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Float] {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
              buffer.floatChannelData != nil else { return [] }
        let offset = OSAllocatedUnfairLock(initialState: AVAudioFrameCount(0)) // the block runs synchronously
        var error: NSError?
        converter.convert(to: output, error: &error) { wanted, status in
            let start = offset.withLock { $0 }
            let count = min(wanted, buffer.frameLength - start)
            guard count > 0, let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count) else {
                status.pointee = .noDataNow
                return nil
            }
            slice.frameLength = count
            for channel in 0..<Int(buffer.format.channelCount) {
                slice.floatChannelData![channel].update(from: buffer.floatChannelData![channel] + Int(start), count: Int(count))
            }
            offset.withLock { $0 += count }
            status.pointee = .haveData
            return slice
        }
        guard error == nil, let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }

    /// Loudest 100 ms window in dBFS (-inf for silence), for diagnostics: tells "too quiet" apart from "no words".
    public static func peakDecibels(_ samples: [Float]) -> Float {
        let loudest = stride(from: 0, to: samples.count, by: 1_600)
            .map { rms(Array(samples[$0..<min($0 + 1_600, samples.count)])) }.max() ?? 0
        return 20 * log10(loudest)
    }

    /// The input device's name and sample rate, for diagnostics.
    public var inputDescription: String {
        let format = engine.inputNode.outputFormat(forBus: 0)
        // Following the default, the engine reports its private "CADefaultDeviceAggregate"; name the real device.
        let device = deviceUID.isEmpty || usedFallback ? AudioInputs.defaultID : currentDevice
        let name = device.flatMap(AudioInputs.name(of:)) ?? "unknown"
        return "\(name), \(format.sampleRate) Hz, \(format.channelCount) ch"
    }

    /// Points the engine at `deviceUID`. If that microphone is gone, back to the system default.
    private func selectDevice() {
        let wanted = AudioInputs.resolve(uid: deviceUID, in: AudioInputs.all())
        usedFallback = !deviceUID.isEmpty && wanted == nil
        // Untouched for "System default", so the engine keeps following the default when it changes.
        guard var id = wanted?.id ?? (usedFallback ? AudioInputs.defaultID : nil), id != currentDevice,
              let unit = engine.inputNode.audioUnit else { return }
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &id, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private var currentDevice: AudioDeviceID? {
        guard let unit = engine.inputNode.audioUnit else { return nil }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size)
        return status == noErr ? id : nil
    }

    /// True when no 100 ms window reaches the level meter's floor (-50 dBFS), or the clip is under 0.3 s.
    public static func isSilent(_ samples: [Float]) -> Bool {
        guard samples.count >= Int(sampleRate * 0.3) else { return true }
        return !stride(from: 0, to: samples.count, by: 1_600).contains { start in
            LevelMeter.normalized(rms: rms(Array(samples[start..<min(start + 1_600, samples.count)]))) > 0
        }
    }

    static func rms(_ chunk: [Float]) -> Float {
        guard !chunk.isEmpty else { return 0 }
        return (chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)).squareRoot()
    }
}
