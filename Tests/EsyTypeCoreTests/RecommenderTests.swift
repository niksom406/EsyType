import Foundation
import Testing
@testable import EsyTypeCore

private let gib: UInt64 = 1 << 30
private let plenty: Int64 = 100_000_000_000

private func mac(gb: UInt64, appleSilicon: Bool = true, translated: Bool = false, free: Int64 = plenty) -> HardwareProfile {
    HardwareProfile(chip: "Simulated", isAppleSilicon: appleSilicon, isTranslated: translated,
                    memoryBytes: gb * gib, freeDiskBytes: free, macOSVersion: "26.5.2")
}

// MARK: Disk maths

@Test func reserveIsAtLeastOneGBOrTenPercent() {
    #expect(DiskSpace.required(forFileBytes: 264_464_607) == 1_264_464_607)
    #expect(DiskSpace.required(forFileBytes: 20_000_000_000) == 22_000_000_000)
    #expect(DiskSpace.required(forFileBytes: 10_000_000_001) == 11_000_000_002) // 10 % rounds up
}

@Test func shortfallIsExactAndNeverNegative() {
    #expect(DiskSpace.shortfall(fileBytes: 264_464_607, freeBytes: 1_264_464_607) == 0)
    #expect(DiskSpace.shortfall(fileBytes: 264_464_607, freeBytes: 1_264_464_606) == 1)
    #expect(DiskSpace.shortfall(fileBytes: 264_464_607, freeBytes: 0) == 1_264_464_607)
    #expect(DiskSpace.shortfall(fileBytes: 1, freeBytes: plenty) == 0)
}

// MARK: Recommender (simulated profiles)

@Test(arguments: [
    // (memory GB, Apple Silicon, benchmarks, expected model)
    (8, true, [], "base-q8"),
    (16, true, [], "small-q8"),
    (18, true, [Benchmark(modelID: "turbo-q8", realTimeFactor: 0.1)], "small-q8"), // Turbo needs 24 GB
    (24, true, [], "small-q8"),
    (24, true, [Benchmark(modelID: "turbo-q5", realTimeFactor: 0.3)], "turbo-q5"),
    (24, true, [Benchmark(modelID: "turbo-q5", realTimeFactor: 0.31)], "small-q8"),
    (32, true, [], "small-q8"), // Turbo isn't validated until benchmarked
    (32, true, [Benchmark(modelID: "turbo-q8", realTimeFactor: 0.2), Benchmark(modelID: "turbo-q5", realTimeFactor: 0.1)], "turbo-q8"),
    (64, true, [Benchmark(modelID: "turbo-q8", realTimeFactor: 0.5), Benchmark(modelID: "turbo-q8", realTimeFactor: 0.25)], "turbo-q8"),
    (8, false, [], "base-q8"),
    (32, false, [], "base-q8"),
    (16, false, [Benchmark(modelID: "small-q8", realTimeFactor: 0.5)], "small-q8"),
    (16, false, [Benchmark(modelID: "small-q8", realTimeFactor: 0.6)], "base-q8"),
    (64, false, [Benchmark(modelID: "turbo-q8", realTimeFactor: 0.1)], "base-q8"), // never Turbo on Intel
] as [(UInt64, Bool, [Benchmark], String)])
func recommendsByHardware(gb: UInt64, appleSilicon: Bool, benchmarks: [Benchmark], expected: String) {
    let result = Recommender.recommend(for: mac(gb: gb, appleSilicon: appleSilicon), benchmarks: benchmarks)
    #expect(result.model.id == expected)
    #expect(result.shortfallBytes == 0)
    #expect(!result.reason.isEmpty)
}

@Test func fallsBackToASmallerModelThatFits() {
    let free = DiskSpace.required(forFileBytes: ModelCatalog.baseQ8.bytes) // Base fits, Small doesn't
    let result = Recommender.recommend(for: mac(gb: 16, free: free))
    #expect(result.model == ModelCatalog.baseQ8)
    #expect(result.shortfallBytes == 0)
    #expect(result.reason.contains("Whisper Small"))
}

@Test func showsExactShortfallWhenNothingFits() {
    let result = Recommender.recommend(for: mac(gb: 16, free: 500_000_000))
    #expect(result.model == ModelCatalog.smallQ8)
    #expect(result.shortfallBytes == 1_264_464_607 - 500_000_000)
}

@Test func warnsUnderRosettaAndOnIntel() {
    #expect(Recommender.recommend(for: mac(gb: 16)).warnings.isEmpty)
    #expect(Recommender.recommend(for: mac(gb: 16, translated: true)).warnings.count == 1)
    #expect(Recommender.recommend(for: mac(gb: 16, appleSilicon: false)).warnings.count == 1)
}

// MARK: Catalogue and the real Mac

@Test func catalogueMatchesModelRegistry() throws {
    let registry = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MODEL_REGISTRY.md")
    let rows = try String(contentsOf: registry, encoding: .utf8).split(separator: "\n")
    for model in ModelCatalog.all {
        let bytes = model.bytes.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_GB")))
        let row = rows.first { $0.hasPrefix("|") && $0.contains("`\(model.file)`") }
        #expect(row?.contains("| \(bytes) |") == true, "\(model.file) bytes")
        #expect(row?.contains("`\(model.sha256)`") == true, "\(model.file) SHA-256")
    }
}

@Test func detectsThisMac() {
    let profile = HardwareDetector.current()
    #expect(profile.memoryBytes > 0)
    #expect(profile.freeDiskBytes > 0)
    #expect(profile.chip != "Unknown")
    #if arch(arm64)
    #expect(profile.isAppleSilicon && !profile.isTranslated)
    #else
    #expect(profile.isTranslated == profile.isAppleSilicon) // Rosetta on Apple Silicon, or a real Intel Mac
    #endif
}

@Test func countsPhysicalCores() {
    #expect(HardwareDetector.physicalCores >= 1)
    #expect(HardwareDetector.physicalCores <= ProcessInfo.processInfo.activeProcessorCount)
}
