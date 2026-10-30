// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Sillies",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "SilliesCore", targets: ["SilliesCore"]),
    .executable(name: "Sillies", targets: ["SilliesApp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    .package(path: "Vendor/AudioProcessing"),
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    .package(
      url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: ["Diarizer"]
    ),
  ],
  targets: [
    .target(name: "SilliesCore", exclude: ["AGENTS.md"]),
    .target(name: "SilliesSpeech", dependencies: ["SilliesCore"]),
    .target(name: "SilliesModelValidation"),
    .target(name: "SilliesSpeechApple", dependencies: ["SilliesSpeech"]),
    .target(
      name: "SilliesModelStore", dependencies: ["SilliesCore"], resources: [.copy("Resources")]),
    .target(
      name: "SilliesSpeechWhisper",
      dependencies: ["SilliesSpeech", .product(name: "WhisperKit", package: "argmax-oss-swift")]),
    .target(
      name: "SilliesSpeechParakeet",
      dependencies: ["SilliesSpeech", .product(name: "FluidAudio", package: "FluidAudio")]),
    .target(
      name: "SilliesDiarizationNemotron",
      dependencies: ["SilliesSpeech", .product(name: "FluidAudio", package: "FluidAudio")]),
    .target(name: "SilliesPersistence", dependencies: ["SilliesCore"], exclude: ["AGENTS.md"]),
    .target(
      name: "SilliesAudio",
      dependencies: [
        "SilliesCore", "SilliesSpeech",
        .product(name: "EchoCancellation", package: "AudioProcessing"),
      ],
      exclude: ["AGENTS.md"]),
    .target(name: "WindowMetadataProtocol"),
    .executableTarget(
      name: "SilliesWindowMetadata", dependencies: ["WindowMetadataProtocol"]),
    .executableTarget(
      name: "SilliesApp",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
        "SilliesAudio",
        "SilliesCore",
        "SilliesPersistence",
        "SilliesSpeech", "SilliesSpeechApple", "SilliesSpeechWhisper", "SilliesSpeechParakeet",
        "SilliesModelStore", "SilliesModelValidation", "SilliesDiarizationNemotron",
        "WindowMetadataProtocol",
      ],
      exclude: ["Platform/AGENTS.md", "UI/AGENTS.md"],
      resources: [.copy("Resources/Characters")]
    ),
    .executableTarget(
      name: "SpeechBenchmark",
      dependencies: [
        "SilliesCore", "SilliesModelStore", "SilliesSpeech", "SilliesSpeechWhisper",
        "SilliesSpeechParakeet", "SilliesDiarizationNemotron",
      ], path: "Tools/SpeechBenchmark"),
    .testTarget(name: "SilliesCoreTests", dependencies: ["SilliesCore"]),
    .testTarget(name: "SilliesSpeechTests", dependencies: ["SilliesSpeech", "SilliesSpeechApple"]),
    .testTarget(
      name: "SilliesModelStoreTests", dependencies: ["SilliesModelStore", "SilliesCore"]),
    .target(
      name: "SilliesAudioTestSupport", dependencies: ["SilliesAudio", "SilliesSpeech"],
      path: "Tests/SilliesAudioTestSupport"),
    .testTarget(
      name: "SilliesAudioTests",
      dependencies: ["SilliesAudio", "SilliesCore", "SilliesSpeech", "SilliesAudioTestSupport"]),
    .testTarget(
      name: "SilliesPersistenceTests", dependencies: ["SilliesPersistence", "SilliesCore"],
      resources: [.copy("Fixtures")]),
    .testTarget(
      name: "SilliesAppTests",
      dependencies: [
        "SilliesApp", "SilliesAudio", "SilliesAudioTestSupport", "SilliesCore",
        "SilliesPersistence",
        "SilliesSpeech", "SilliesSpeechApple", "SilliesSpeechWhisper", "SilliesSpeechParakeet",
        "SilliesModelStore", "SilliesDiarizationNemotron",
        "WindowMetadataProtocol",
      ]),
  ],
  swiftLanguageModes: [.v6]
)
