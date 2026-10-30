import Foundation

struct ArchitecturePolicy {
  var uncheckedOwners: [String: String]

  static let imports: [String: Set<String>] = [
    "SilliesCore": ["Foundation", "CoreGraphics"],
    "SilliesPersistence": ["Foundation", "Darwin", "SilliesCore"],
    "SilliesAudio": [
      "Foundation", "FoundationModels", "AVFoundation", "CoreMedia", "CoreAudio", "Speech",
      "ScreenCaptureKit", "CEchoCancellation", "SilliesCore", "Synchronization",
    ],
  ]
  static let workerEntries: [String: Set<String>] = [
    "WindowServerSource.swift": ["performRefresh"],
    "AccessibilityWindowSource.swift": ["readWindow", "roleSnapshot"],
    "WindowMetadataReader.swift": ["snapshot"],
    "WindowMetadataClient.swift": ["read"],
    "WindowMetadataConnection.swift": ["read"],
    "ApplicationIconCache.swift": ["load"],
  ]
}

struct ArchitectureDiagnostic: Equatable, CustomStringConvertible {
  let path: String
  let line: Int
  let rule: String
  let message: String
  var description: String { "\(path):\(line): [\(rule)] \(message)" }
}
