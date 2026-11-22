// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EsyType",
    platforms: [.macOS(.v14)],
    targets: [
        // Logic with no windows or UI: unit-tested with Scripts/test.sh.
        .target(name: "EsyTypeCore"),
        // The app. Bundled into EsyType.app by Scripts/build-app.sh.
        .executableTarget(name: "EsyType", dependencies: ["EsyTypeCore", "WhisperEngine"]),
        .testTarget(name: "EsyTypeCoreTests", dependencies: ["EsyTypeCore"]),
        // whisper.cpp, pinned by URL + SHA-256 (ARCHITECTURE ADR-3). Only WhisperEngine may import it.
        .binaryTarget(name: "whisper",
                      url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
                      checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"),
        .target(name: "WhisperEngine", dependencies: ["whisper"]),
        // Model tests run only when models are installed (see TESTING.md).
        .testTarget(name: "WhisperEngineTests", dependencies: ["WhisperEngine", "EsyTypeCore"],
                    exclude: ["Fixtures"]),
    ]
)
