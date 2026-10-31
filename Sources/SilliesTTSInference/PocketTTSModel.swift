import FluidAudio
import Foundation
import SilliesTTS

actor PocketTTSModel: NativeTTSModel {
  private let manager: PocketTtsManager
  private let languageRoot: URL

  init(configuration: TTSPreparation) async throws {
    guard let language = PocketTtsLanguage(rawValue: configuration.variant) else {
      throw TTSError.invalidRequest
    }
    languageRoot = configuration.directory
      .appendingPathComponent(PocketTtsConstants.defaultModelsSubdirectory)
      .appendingPathComponent(Repo.pocketTts.folderName)
      .appendingPathComponent(language.repoSubdirectory)
    for path in ModelNames.PocketTTS.requiredModels {
      guard FileManager.default.fileExists(atPath: languageRoot.appendingPathComponent(path).path)
      else {
        throw TTSError.unavailable(
          "The Pocket TTS installation is incomplete. Reinstall it in Settings → Voices.")
      }
    }
    guard
      FileManager.default.fileExists(
        atPath: languageRoot.appendingPathComponent("constants_bin/bos_before_voice.bin").path)
    else {
      throw TTSError.unavailable(
        "The Pocket TTS installation is missing a required resource. Reinstall it in Settings → Voices."
      )
    }
    manager = PocketTtsManager(language: language, directory: configuration.directory)
    try await manager.initialize()
  }

  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
  {
    guard request.voiceID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
      FileManager.default.fileExists(
        atPath: languageRoot.appendingPathComponent("constants_bin/\(request.voiceID).safetensors")
          .path)
    else { throw TTSError.unsupportedVoice }
    let stream = try await manager.synthesizeStreaming(text: request.text, voice: request.voiceID)
    for try await frame in stream {
      try Task.checkCancellation()
      try output(frame.samples, PocketTtsConstants.audioSampleRate)
    }
  }
}
