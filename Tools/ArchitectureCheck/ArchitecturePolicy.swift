import Foundation

struct ArchitecturePolicy {
  var uncheckedOwners: [String: String]

  static let imports: [String: Set<String>] = [
    "SilliesCore": ["Foundation", "CoreGraphics"],
    "SilliesReasoning": [
      "Foundation", "FoundationModels", "NaturalLanguage", "SilliesCore", "SilliesTextModels",
      "SilliesModelStore",
    ],
    "SilliesWriting": [
      "Foundation", "Observation", "SilliesCore", "SilliesReasoning", "SilliesAudio",
      "SilliesSpeech",
    ],
    "SilliesVault": ["Foundation", "SilliesCore", "SilliesPersistence", "SilliesReasoning"],
    "SilliesSpeech": [
      "Foundation", "Dispatch", "Accelerate", "AVFoundation", "Synchronization", "SilliesCore",
      "SilliesInference",
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
    "SilliesInference": ["Foundation"],
    "SilliesTextModels": [
      "Foundation", "Darwin", "SilliesCore", "SilliesModelStore", "SilliesInference",
    ],
    "SilliesTextInference": [
      "Foundation", "Darwin", "MLX", "MLXLLM", "MLXLMCommon", "Tokenizers", "SilliesTextModels",
    ],
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
    "VaultLibrary.swift": ["storage"],
    "WindowTextRecognition.swift": ["recognize"],
    "WindowMetadataReader.swift": ["snapshot"],
    "WindowMetadataClient.swift": ["read"],
    "WindowMetadataConnection.swift": ["read"],
    "TextWorkerConnection.swift": ["generate"],
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
