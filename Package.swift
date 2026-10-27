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
    .target(name: "SilliesCore"),
    .target(name: "WindowMetadataProtocol"),
    .executableTarget(
      name: "SilliesWindowMetadata", dependencies: ["WindowMetadataProtocol"]),
    .executableTarget(
      name: "SilliesApp",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
        .product(name: "EchoCancellation", package: "AudioProcessing"),
        "SilliesCore",
        "WindowMetadataProtocol",
      ],
      resources: [.copy("Resources/Characters")]
    ),
    .testTarget(name: "SilliesCoreTests", dependencies: ["SilliesCore"]),
    .testTarget(
      name: "SilliesAppTests",
      dependencies: ["SilliesApp", "SilliesCore", "WindowMetadataProtocol"]),
  ],
  swiftLanguageModes: [.v6]
)
