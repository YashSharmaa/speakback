// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Speak",
    platforms: [
        // FluidAudio supports macOS 14; its ANE-v3 runtime (opt-in) checks for macOS 15 at run time.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "speak", targets: ["speak"]),
        .library(name: "SpeakNormalizer", targets: ["SpeakNormalizer"]),
        .library(name: "SpeakCore", targets: ["SpeakCore"]),
    ],
    dependencies: [
        // Apache-2.0. Pinned exactly: the Kokoro API used here was read from this tag.
        // Diarizer is left out; TTS and the NeMo text normaliser are kept.
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.18.2",
            traits: ["TTS", "NemoTextProcessing"]
        )
    ],
    targets: [
        // Pure text normalisation: Foundation only, no I/O, no global state.
        .target(name: "SpeakNormalizer"),
        // Protocol, paths, chunking, audio scheduling, socket server and client.
        .target(
            name: "SpeakCore",
            dependencies: [
                "SpeakNormalizer",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(name: "speak", dependencies: ["SpeakCore", "SpeakNormalizer"]),
        .testTarget(name: "SpeakNormalizerTests", dependencies: ["SpeakNormalizer"]),
        .testTarget(name: "SpeakCoreTests", dependencies: ["SpeakCore"]),
    ]
)
