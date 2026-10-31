import Foundation

struct ArchitecturePolicy {
  var uncheckedOwners: [String: String]

  static let imports: [String: Set<String>] = [
    "SilliesCore": ["Foundation", "CoreGraphics"],
    "SilliesSpeech": [
      "Foundation", "Dispatch", "Accelerate", "AVFoundation", "Synchronization", "SilliesCore",
    ],
    "SilliesSpeechApple": [
      "Foundation", "AVFoundation", "Speech", "Synchronization", "SilliesSpeech",
    ],
    "SilliesSpeechWhisper": [
      "Foundation", "NaturalLanguage", "CoreML", "WhisperKit", "SilliesSpeech",
    ],
    "SilliesSpeechParakeet": ["Foundation", "FluidAudio", "SilliesSpeech"],
    "SilliesDiarizationNemotron": ["Foundation", "FluidAudio", "SilliesSpeech"],
    "SilliesModelStore": ["Foundation", "CryptoKit", "Synchronization", "SilliesCore"],
    "SilliesModelValidation": ["Foundation", "CoreML"],
    "SilliesPersistence": ["Foundation", "Darwin", "SQLite3", "SilliesCore"],
    "SilliesAudio": [
      "Foundation", "AVFoundation", "CoreMedia", "CoreAudio", "SilliesSpeech",
      "ScreenCaptureKit", "CEchoCancellation", "SilliesCore", "Synchronization",
    ],
  ]
  static let workerEntries: [String: Set<String>] = [
    "WhisperWindowEngine.swift": ["load", "transcribe"],
    "ParakeetWindowEngine.swift": ["load", "transcribe"],
    "NemotronDiarizationRuntime.swift": ["load", "process"],
    "ModelFiles.swift": ["child", "verify", "write"],
    "ModelInterfaceValidator.swift": ["validate"],
    "SpeechLanguageDiscovery.swift": ["load"],
    "SerialQueueStorage.swift": ["withValue"],
    "WindowServerSource.swift": ["performRefresh"],
    "AccessibilityWindowSource.swift": ["readWindow", "roleSnapshot"],
    "AccessibilityTextAccess.swift": ["capture", "insert", "validate"],
    "ClipboardPasteTransaction.swift": ["prepare"],
    "VaultSearchService.swift": ["search"],
    "WindowTextRecognition.swift": ["recognize"],
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
