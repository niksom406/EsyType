import Foundation

public struct ModelInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let quantisation: String
    public let file: String
    public let bytes: Int64
    public let sha256: String

    /// Pinned revision from MODEL_REGISTRY.md.
    public var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/\(file)")!
    }
}

/// Exact values from MODEL_REGISTRY.md (checked by a test). Phase 3 adds the manual-choice files.
public enum ModelCatalog {
    public static let baseQ8 = ModelInfo(id: "base-q8", name: "Whisper Base", quantisation: "Q8_0",
        file: "ggml-base-q8_0.bin", bytes: 81_768_585,
        sha256: "c577b9a86e7e048a0b7eada054f4dd79a56bbfa911fbdacf900ac5b567cbb7d9")
    public static let smallQ8 = ModelInfo(id: "small-q8", name: "Whisper Small", quantisation: "Q8_0",
        file: "ggml-small-q8_0.bin", bytes: 264_464_607,
        sha256: "49c8fb02b65e6049d5fa6c04f81f53b867b5ec9540406812c643f177317f779f")
    public static let turboQ8 = ModelInfo(id: "turbo-q8", name: "Whisper Large v3 Turbo", quantisation: "Q8_0",
        file: "ggml-large-v3-turbo-q8_0.bin", bytes: 874_188_075,
        sha256: "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1")
    public static let turboQ5 = ModelInfo(id: "turbo-q5", name: "Whisper Large v3 Turbo", quantisation: "Q5_0",
        file: "ggml-large-v3-turbo-q5_0.bin", bytes: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2")

    public static let all = [baseQ8, smallQ8, turboQ8, turboQ5]
}

/// A measured result on this Mac. RTF = processing time ÷ audio duration.
public struct Benchmark: Sendable, Equatable {
    public let modelID: String
    public let realTimeFactor: Double
    public init(modelID: String, realTimeFactor: Double) {
        self.modelID = modelID
        self.realTimeFactor = realTimeFactor
    }
}

public struct Recommendation: Sendable, Equatable {
    public let model: ModelInfo
    public let reason: String
    /// Bytes to free before `model` can be downloaded; 0 when it fits.
    public let shortfallBytes: Int64
    public let warnings: [String]
}

/// Rules from MODEL_REGISTRY.md "Hardware recommendation". Turbo is only chosen with a passing benchmark.
public enum Recommender {
    static let turboMaxRTF = 0.3
    static let intelSmallMaxRTF = 0.5

    public static func recommend(for mac: HardwareProfile, benchmarks: [Benchmark] = []) -> Recommendation {
        var warnings: [String] = []
        if mac.isTranslated {
            warnings.append("EsyType is running under Rosetta, so speech will be slower. Reinstall EsyType to get the native version.")
        }
        if !mac.isAppleSilicon {
            warnings.append("EsyType hasn’t been tested on Intel Macs yet.")
        }

        let (pick, reason) = hardwarePick(mac, benchmarks)
        // Fall back to the largest smaller tier that fits on disk; if none fits, keep the pick and show the shortfall.
        let tiers = [ModelCatalog.baseQ8, ModelCatalog.smallQ8, pick]
        let ladder = tiers.prefix(through: tiers.firstIndex(of: pick)!).reversed()
        let fits = ladder.first { DiskSpace.shortfall(fileBytes: $0.bytes, freeBytes: mac.freeDiskBytes) == 0 }
        guard let fits, fits != pick else {
            return Recommendation(model: pick, reason: reason,
                                  shortfallBytes: DiskSpace.shortfall(fileBytes: pick.bytes, freeBytes: mac.freeDiskBytes),
                                  warnings: warnings)
        }
        return Recommendation(model: fits,
                              reason: "\(pick.name) needs more free disk than this Mac has. \(fits.name) fits and still works well.",
                              shortfallBytes: 0, warnings: warnings)
    }

    private static func hardwarePick(_ mac: HardwareProfile, _ benchmarks: [Benchmark]) -> (ModelInfo, String) {
        func rtf(_ model: ModelInfo) -> Double {
            benchmarks.filter { $0.modelID == model.id }.map(\.realTimeFactor).min() ?? .infinity
        }
        guard mac.isAppleSilicon else {
            if rtf(ModelCatalog.smallQ8) <= intelSmallMaxRTF {
                return (ModelCatalog.smallQ8, "Small ran fast enough on this Mac in a quick test.")
            }
            return (ModelCatalog.baseQ8, "Base is quick on Intel Macs and still accurate.")
        }
        if mac.memoryGB <= 8 {
            return (ModelCatalog.baseQ8, "Base is quick with \(mac.memoryGB) GB of memory and leaves room for your other apps.")
        }
        if mac.memoryGB >= 24, let turbo = [ModelCatalog.turboQ8, ModelCatalog.turboQ5].first(where: { rtf($0) <= turboMaxRTF }) {
            return (turbo, "Turbo is the most accurate model and ran fast enough on this Mac.")
        }
        return (ModelCatalog.smallQ8, "Small balances accuracy and speed with \(mac.memoryGB) GB of memory.")
    }
}
