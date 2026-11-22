import Foundation
import whisper

public struct Transcript: Sendable, Equatable {
    public let text: String
    /// ISO 639-1 code whisper.cpp used, e.g. "en", "hi", "mr".
    public let language: String
}

public enum WhisperError: Error, Equatable, LocalizedError {
    case cannotLoadModel
    case transcriptionFailed(code: Int32)

    public var errorDescription: String? {
        switch self {
        case .cannotLoadModel: "The speech model couldn’t be loaded. Try removing it and downloading it again."
        case .transcriptionFailed(let code): "Transcription failed (whisper.cpp error \(code))."
        }
    }
}

/// The only code that calls whisper.cpp. One loaded model per engine; the actor serialises calls.
public actor WhisperCppEngine {
    // Only used inside the actor, and by deinit once nothing else can reach it.
    private nonisolated(unsafe) let context: OpaquePointer
    private let threads: Int32?

    /// Keeps whisper.cpp and ggml quiet: their default logging goes to stderr.
    private static let silenceLogs: Void = whisper_log_set({ _, _, _ in }, nil)

    /// `threads`: CPU threads for decoding, or nil for whisper.cpp's default (4).
    public init(model: URL, useGPU: Bool = true, threads: Int? = nil) throws {
        self.threads = threads.map { Int32($0) }
        Self.silenceLogs
        var params = whisper_context_default_params()
        params.use_gpu = useGPU
        guard let context = whisper_init_from_file_with_params(model.path, params) else {
            throw WhisperError.cannotLoadModel
        }
        self.context = context
    }

    deinit { whisper_free(context) }

    /// Every language whisper.cpp knows, as (ISO code, English name), in whisper's order.
    public static let languages: [(code: String, name: String)] = (0...whisper_lang_max_id()).map {
        (String(cString: whisper_lang_str($0)), String(cString: whisper_lang_str_full($0)).capitalized)
    }

    /// `samples` are 16 kHz mono Float32. `language` is an ISO code, or nil to detect it.
    /// `translate` outputs English whatever was spoken.
    /// `prompt` biases spelling toward words Whisper doesn't know, e.g. "EsyType" (otherwise "EZ type").
    public func transcribe(_ samples: [Float], language: String? = nil, translate: Bool = false,
                           prompt: String = "") throws -> Transcript {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        // Never print: these would write the transcript to stderr.
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.no_context = true // each dictation stands alone
        params.translate = translate
        if let threads { params.n_threads = threads }
        let code = (language ?? "auto").withCString { language in
            prompt.withCString { prompt in
                params.language = language
                params.initial_prompt = prompt
                return samples.withUnsafeBufferPointer { whisper_full(context, params, $0.baseAddress, Int32($0.count)) }
            }
        }
        guard code == 0 else { throw WhisperError.transcriptionFailed(code: code) }
        let text = (0..<whisper_full_n_segments(context))
            .map { String(cString: whisper_full_get_segment_text(context, $0)) }
            .joined()
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                          language: String(cString: whisper_lang_str(whisper_full_lang_id(context))))
    }
}
