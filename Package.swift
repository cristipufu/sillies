// swift-tools-version: 6.0
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
  ],
  targets: [
    .target(name: "SilliesCore", exclude: ["AGENTS.md"]),
    .target(name: "SilliesPersistence", dependencies: ["SilliesCore"], exclude: ["AGENTS.md"]),
    .target(
      name: "SilliesAudio",
      dependencies: [
        "SilliesCore", .product(name: "EchoCancellation", package: "AudioProcessing"),
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
        "WindowMetadataProtocol",
      ],
      exclude: ["Platform/AGENTS.md", "UI/AGENTS.md"],
      resources: [.copy("Resources/Characters")]
    ),
    .testTarget(name: "SilliesCoreTests", dependencies: ["SilliesCore"]),
    .target(
      name: "SilliesAudioTestSupport", dependencies: ["SilliesAudio"],
      path: "Tests/SilliesAudioTestSupport"),
    .testTarget(
      name: "SilliesAudioTests",
      dependencies: ["SilliesAudio", "SilliesCore", "SilliesAudioTestSupport"]),
    .testTarget(
      name: "SilliesPersistenceTests", dependencies: ["SilliesPersistence", "SilliesCore"]),
    .testTarget(
      name: "SilliesAppTests",
      dependencies: [
        "SilliesApp", "SilliesAudio", "SilliesAudioTestSupport", "SilliesCore",
        "WindowMetadataProtocol",
      ]),
  ],
  swiftLanguageModes: [.v6]
)
