// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Sillies",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SilliesCore", targets: ["SilliesCore"]),
    .executable(name: "Sillies", targets: ["SilliesApp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
  ],
  targets: [
    .target(name: "SilliesCore"),
    .executableTarget(
      name: "SilliesApp",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
        "SilliesCore",
      ],
      resources: [.copy("Resources/Characters")]
    ),
    .testTarget(name: "SilliesCoreTests", dependencies: ["SilliesCore"]),
    .testTarget(name: "SilliesAppTests", dependencies: ["SilliesApp", "SilliesCore"]),
  ],
  swiftLanguageModes: [.v6]
)
