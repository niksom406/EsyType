import Foundation

public struct HardwareProfile: Sendable, Equatable {
    public var chip: String
    /// True on Apple Silicon hardware, also when this process runs under Rosetta.
    public var isAppleSilicon: Bool
    /// True when an x86_64 build runs under Rosetta on Apple Silicon.
    public var isTranslated: Bool
    public var memoryBytes: UInt64
    public var freeDiskBytes: Int64
    public var macOSVersion: String

    public init(chip: String, isAppleSilicon: Bool, isTranslated: Bool, memoryBytes: UInt64,
                freeDiskBytes: Int64, macOSVersion: String) {
        self.chip = chip
        self.isAppleSilicon = isAppleSilicon
        self.isTranslated = isTranslated
        self.memoryBytes = memoryBytes
        self.freeDiskBytes = freeDiskBytes
        self.macOSVersion = macOSVersion
    }

    /// Whole GiB, which is how Macs are sold (an "8 GB" Mac reports exactly 8 GiB).
    public var memoryGB: UInt64 { memoryBytes >> 30 }
}

public enum HardwareDetector {
    /// Reads this Mac. `volume` is any path on the volume models are stored on.
    public static func current(volume: URL = URL(fileURLWithPath: NSHomeDirectory())) -> HardwareProfile {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let free = (try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? 0
        return HardwareProfile(
            chip: sysctlString("machdep.cpu.brand_string") ?? "Unknown",
            isAppleSilicon: sysctlInt32("hw.optional.arm64") == 1, // missing on Intel, 1 under Rosetta
            isTranslated: sysctlInt32("sysctl.proc_translated") == 1,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            freeDiskBytes: free,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }

    /// Physical cores (not hyper-threads).
    public static var physicalCores: Int { max(1, Int(sysctlInt32("hw.physicalcpu"))) }

    private static func sysctlInt32(_ name: String) -> Int32 {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : 0
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Storage rule from MODEL_REGISTRY.md: required = file + max(1 GB, 10 % of file).
public enum DiskSpace {
    public static func required(forFileBytes bytes: Int64) -> Int64 {
        bytes + max(1_000_000_000, (bytes + 9) / 10)
    }

    /// Bytes the user must free before the file can be downloaded; 0 when it fits.
    public static func shortfall(fileBytes: Int64, freeBytes: Int64) -> Int64 {
        max(0, required(forFileBytes: fileBytes) - freeBytes)
    }
}
