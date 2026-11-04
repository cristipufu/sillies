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
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
    .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.32.3"),
    .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    .package(path: "Vendor/AudioProcessing"),
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    .package(
      url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0",
      traits: ["Diarizer", "TTS"]
    ),
  ],
  targets: [
    .target(name: "SilliesCore", exclude: ["AGENTS.md"]),
    .target(name: "SilliesDesign", resources: [.copy("Themes")]),
    .target(name: "SilliesInference"),
    .target(
      name: "SilliesSearchModels",
      dependencies: ["SilliesCore", "SilliesInference"]),
    .executableTarget(
      name: "SilliesSearchInference",
      dependencies: [
        "SilliesSearchModels", "SilliesCore", "SilliesInference",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
        .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
      ]),
    .target(name: "SilliesFileSystem"),
    .target(
      name: "SilliesTTS", dependencies: ["SilliesCore", "SilliesModelStore", "SilliesInference"]),
    .target(
      name: "SilliesFishSpeech",
      dependencies: [
        "SilliesTTS",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ]),
    .target(name: "SilliesVoicePlayback", dependencies: ["SilliesTTS", "SilliesCore"]),
    .target(
      name: "SilliesChat",
      dependencies: [
        "SilliesCore", "SilliesAudio", "SilliesSpeech", "SilliesReasoning", "SilliesTTS",
      ]),
    .executableTarget(
      name: "SilliesTTSInference",
      dependencies: [
        "SilliesTTS", "SilliesInference", "SilliesModelStore", "SilliesFishSpeech",
        .product(name: "FluidAudio", package: "FluidAudio"),
        .product(name: "TTSKit", package: "argmax-oss-swift"),
      ]),
    .target(
      name: "SilliesWriting",
      dependencies: ["SilliesCore", "SilliesAudio", "SilliesSpeech", "SilliesReasoning"],
      exclude: ["AGENTS.md"]),
    .target(
      name: "SilliesVault",
      dependencies: ["SilliesCore", "SilliesPersistence", "SilliesReasoning"],
      exclude: ["AGENTS.md"]),
    .target(
      name: "SilliesReasoning",
      dependencies: ["SilliesCore", "SilliesTextModels", "SilliesModelStore"],
      exclude: ["AGENTS.md"]),
    .target(
      name: "SilliesTextModels",
      dependencies: ["SilliesCore", "SilliesModelStore", "SilliesInference"]),
    .executableTarget(
      name: "SilliesTextInference",
      dependencies: [
        "SilliesTextModels", "SilliesInference",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ], resources: [.copy("Resources")]),
    .target(name: "SilliesSpeech", dependencies: ["SilliesCore", "SilliesInference"]),
    .target(name: "SilliesModelValidation"),
    .target(name: "SilliesSpeechApple", dependencies: ["SilliesSpeech"]),
    .target(
      name: "SilliesModelStore", dependencies: ["SilliesCore", "SilliesFileSystem"],
      resources: [.copy("Resources")]),
    .target(
      name: "SilliesSpeechWhisper",
      dependencies: ["SilliesSpeech", .product(name: "WhisperKit", package: "argmax-oss-swift")]),
    .target(
      name: "SilliesSpeechParakeet",
      dependencies: ["SilliesSpeech", .product(name: "FluidAudio", package: "FluidAudio")]),
    .target(
      name: "SilliesSpeechNemotron",
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
        "SilliesDesign",
        "SilliesPersistence",
        "SilliesSpeech", "SilliesSpeechApple", "SilliesSpeechWhisper", "SilliesSpeechParakeet",
        "SilliesSpeechNemotron",
        "SilliesModelStore", "SilliesModelValidation", "SilliesDiarizationNemotron",
        "WindowMetadataProtocol",
        "SilliesTextModels", "SilliesInference", "SilliesSearchModels",
        "SilliesReasoning",
        "SilliesVault", "SilliesWriting",
        "SilliesChat", "SilliesTTS", "SilliesVoicePlayback",
      ],
      exclude: ["Platform/AGENTS.md", "UI/AGENTS.md"],
      resources: [.copy("Resources/Characters"), .copy("Resources/Scenes")]
    ),
    .executableTarget(
      name: "MemorySearchBenchmark",
      dependencies: ["SilliesCore", "SilliesVault", "SilliesSearchModels", "SilliesInference"],
      path: "Tools/MemorySearchBenchmark"),
    .executableTarget(
      name: "SpeechBenchmark",
      dependencies: [
        "SilliesCore", "SilliesModelStore", "SilliesSpeech", "SilliesSpeechWhisper",
        "SilliesSpeechParakeet", "SilliesSpeechNemotron", "SilliesDiarizationNemotron",
        "SilliesSpeechApple",
      ], path: "Tools/SpeechBenchmark"),
    .executableTarget(
      name: "TextModelBenchmark",
      dependencies: ["SilliesModelStore", "SilliesTextModels", "SilliesReasoning"],
      path: "Tools/TextModelBenchmark"),
    .executableTarget(
      name: "ChatModelBenchmark",
      dependencies: [
        "SilliesCore", "SilliesModelStore", "SilliesTextModels", "SilliesReasoning", "SilliesVault",
        "SilliesSearchModels", "SilliesInference",
      ], path: "Tools/ChatModelBenchmark", exclude: ["AGENTS.md"]),
    .target(
      name: "SilliesConversationTestSupport", dependencies: ["SilliesCore", "SilliesPersistence"],
      path: "Tests/SilliesConversationTestSupport"),
    .executableTarget(
      name: "ConversationStorageProbe", dependencies: ["SilliesConversationTestSupport"],
      path: "Tools/ConversationStorageProbe"),
    .executableTarget(
      name: "TTSBenchmark", dependencies: ["SilliesModelStore", "SilliesTTS", "SilliesInference"],
      path: "Tools/TTSBenchmark"),
    .testTarget(
      name: "SilliesWritingTests",
      dependencies: [
        "SilliesWriting", "SilliesCore", "SilliesAudio", "SilliesSpeech", "SilliesReasoning",
      ]),
    .testTarget(
      name: "SilliesSearchModelsTests",
      dependencies: ["SilliesSearchModels", "SilliesCore", "SilliesInference"]),
    .testTarget(name: "SilliesCoreTests", dependencies: ["SilliesCore"]),
    .testTarget(name: "SilliesDesignTests", dependencies: ["SilliesDesign"]),
    .testTarget(
      name: "SilliesVoicePlaybackTests", dependencies: ["SilliesVoicePlayback", "SilliesTTS"]),
    .testTarget(
      name: "SilliesFishSpeechTests",
      dependencies: ["SilliesFishSpeech", .product(name: "MLX", package: "mlx-swift")],
      resources: [.copy("Fixtures")]),
    .testTarget(
      name: "SilliesChatTests",
      dependencies: [
        "SilliesChat", "SilliesCore", "SilliesAudio", "SilliesSpeech", "SilliesReasoning",
        "SilliesTTS",
      ]),
    .testTarget(
      name: "SilliesTTSTests",
      dependencies: ["SilliesTTS", "SilliesModelStore", "SilliesInference"]),
    .testTarget(
      name: "SilliesVaultTests",
      dependencies: [
        "SilliesVault", "SilliesCore", "SilliesPersistence", "SilliesReasoning",
        "SilliesModelStore", "SilliesTextModels", "SilliesConversationTestSupport",
      ]),
    .testTarget(
      name: "SilliesReasoningTests",
      dependencies: ["SilliesReasoning", "SilliesCore", "SilliesTextModels"]),
    .testTarget(
      name: "SilliesTextModelsTests",
      dependencies: ["SilliesTextModels", "SilliesModelStore", "SilliesInference"]),
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
        "SilliesConversationTestSupport",
        "SilliesApp", "SilliesAudio", "SilliesAudioTestSupport", "SilliesCore",
        "SilliesPersistence",
        "SilliesReasoning",
        "SilliesVault", "SilliesWriting",
        "SilliesSpeech", "SilliesSpeechApple", "SilliesSpeechWhisper", "SilliesSpeechParakeet",
        "SilliesSpeechNemotron",
        "SilliesModelStore", "SilliesDiarizationNemotron",
        "WindowMetadataProtocol",
      ], exclude: ["execution-modes.json"]),
  ],
  swiftLanguageModes: [.v6]
)
