import Foundation

struct ArchitecturePolicy {
  var uncheckedOwners: [String: String]

  static let imports: [String: Set<String>] = [
    "MemorySearchBenchmark": [
      "Foundation", "SilliesCore", "SilliesVault", "SilliesSearchModels", "SilliesInference",
    ],
    "ConversationStorageProbe": ["Foundation", "SilliesConversationTestSupport"],
    "SilliesConversationTestSupport": [
      "Foundation", "Darwin", "SQLite3", "SilliesCore", "SilliesPersistence",
    ],
    "ChatModelBenchmark": [
      "Foundation", "SilliesCore", "SilliesModelStore", "SilliesTextModels", "SilliesReasoning",
      "SilliesVault", "SilliesSearchModels", "SilliesInference", "Synchronization",
    ],
    "SilliesCore": ["Foundation", "CoreGraphics"],
    "SilliesDesign": ["Foundation"],
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
    "SilliesSpeechNemotron": [
      "Foundation", "AVFoundation", "CoreML", "FluidAudio", "SilliesSpeech",
    ],
    "SilliesDiarizationNemotron": ["Foundation", "FluidAudio", "SilliesSpeech"],
    "SilliesFileSystem": ["Foundation", "Darwin"],
    "SilliesModelStore": [
      "Foundation", "CryptoKit", "Synchronization", "SilliesCore", "SilliesFileSystem",
    ],
    "SilliesSearchModels": ["Foundation", "SilliesCore", "SilliesInference"],
    "SilliesSearchInference": [
      "Foundation", "Darwin", "NaturalLanguage", "MLX", "MLXEmbedders", "MLXHuggingFace",
      "MLXLMCommon", "SilliesCore", "SilliesSearchModels", "SilliesInference", "Tokenizers",
    ],
    "SilliesDiagnostics": ["Foundation", "Synchronization", "OSLog"],
    "SilliesInference": ["Foundation", "Darwin", "SilliesDiagnostics"],
    "SilliesChat": [
      "Foundation", "Observation", "Synchronization", "SilliesCore", "SilliesAudio",
      "SilliesSpeech",
      "SilliesReasoning", "SilliesTTS", "SilliesDiagnostics",
    ],
    "SilliesTTS": ["Foundation", "SilliesCore", "SilliesModelStore", "SilliesInference"],
    "SilliesFishSpeech": ["Foundation", "MLX", "Tokenizers", "SilliesTTS"],
    "SilliesVoicePlayback": [
      "Foundation", "AVFoundation", "AudioToolbox", "Synchronization", "SilliesTTS", "SilliesCore",
    ],
    "SilliesTTSInference": [
      "Foundation", "Darwin", "Synchronization", "FluidAudio", "TTSKit", "SilliesTTS",
      "SilliesInference", "SilliesModelStore", "SilliesFishSpeech",
    ],
    "SilliesTextModels": [
      "Foundation", "Darwin", "SilliesCore", "SilliesModelStore", "SilliesInference",
    ],
    "SilliesTextInference": [
      "Foundation", "Darwin", "CryptoKit", "MLX", "MLXLLM", "MLXLMCommon", "Tokenizers",
      "SilliesTextModels",
      "SilliesInference",
    ],
    "SilliesModelValidation": ["Foundation", "CoreML"],
    "SilliesPersistence": ["Foundation", "Darwin", "SQLite3", "SilliesCore"],
    "SilliesAudio": [
      "Foundation", "AVFoundation", "CoreMedia", "CoreAudio", "SilliesSpeech",
      "ScreenCaptureKit", "CEchoCancellation", "SilliesCore", "Synchronization",
    ],
  ]
  static let workerEntries: [String: Set<String>] = [
    "DiagnosticJournal.swift": ["prepare", "append", "clear", "readRecords"],
    "DiagnosticJournal+Export.swift": ["export"],
    "WhisperWindowEngine.swift": ["load", "transcribe"],
    "ParakeetWindowEngine.swift": ["load", "transcribe"],
    "NemotronStreamingEngine.swift": ["load", "transcribe"],
    "NemotronDiarizationRuntime.swift": ["load", "process"],
    "ModelFiles.swift": ["child", "write"],
    "ModelArtifactVerifier.swift": ["verify"],
    "ModelDerivedArtifact.swift": ["materialize"],
    "RegularFileReader.swift": ["withFile"],
    "ModelInterfaceValidator.swift": ["validate"],
    "SpeechLanguageDiscovery.swift": ["load"],
    "SerialQueueStorage.swift": ["withValue"],
    "WindowServerSource.swift": ["performRefresh"],
    "AccessibilityWindowSource.swift": ["readWindow", "roleSnapshot"],
    "AccessibilityTextAccess.swift": ["capture", "insert", "validate"],
    "ClipboardPasteTransaction.swift": ["prepare"],
    "VaultLibrary.swift": ["storage"],
    "VaultSemanticSearchWorker.swift": ["search"],
    "TextCalibrationIdentity.swift": ["capture"],
    "TextCalibrationStore.swift": ["resolve"],
    "ConversationLibrary.swift": ["storage"],
    "WindowTextRecognition.swift": ["recognize"],
    "WindowMetadataReader.swift": ["snapshot"],
    "WindowMetadataClient.swift": ["read"],
    "WindowMetadataConnection.swift": ["read"],
    "TextWorkerConnection.swift": ["generate"],
    "InferenceWorkerConnection.swift": ["send", "receive"],
    "VoicePlayback.swift": ["schedule"],
    "NativeVoiceOutput.swift": ["prepare", "schedule"],
    "ConversationAudioProcessor.swift": ["appendMicrophone", "next", "nextFinalMicrophone"],
    "VoiceActivityDetector.swift": ["consume"],
    "ThemeCatalog.swift": ["load"],
    "LanguageCatalog.swift": ["load"],
    "KokoroPackagePreparation.swift": ["prepare", "prepareVoice"],
    "FishSpeechEngine.swift": ["synthesize", "stream"],
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
