import FluidAudio
import Foundation
import SilliesTTS

actor PocketTTSModel: NativeTTSModel {
  private let manager: PocketTtsManager
  private let languageRoot: URL
  private var prepared: (voice: SpeechVoice, session: PocketTtsSession)?

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
          String(
            localized:
              "The Pocket TTS installation is incomplete. Reinstall it in Settings → Voices."))
      }
    }
    guard
      FileManager.default.fileExists(
        atPath: languageRoot.appendingPathComponent("constants_bin/bos_before_voice.bin").path)
    else {
      throw TTSError.unavailable(
        String(
          localized:
            "The Pocket TTS installation is missing a required resource. Reinstall it in Settings → Voices."
        )
      )
    }
    manager = PocketTtsManager(language: language, directory: configuration.directory)
    try await manager.initialize()
  }

  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
  {
    try await prepareVoice(request.voice)
    guard let session = prepared?.session else { throw TTSError.interrupted }
    prepared = nil
    session.enqueue(request.text)
    session.finish()
    do {
      for try await frame in session.frames {
        try Task.checkCancellation()
        try output(frame.samples, PocketTtsConstants.audioSampleRate)
      }
    } catch {
      await session.cancel()
      throw error
    }
  }

  func prepareVoice(_ voice: SpeechVoice) async throws {
    if prepared?.voice == voice { return }
    if let previous = prepared {
      prepared = nil
      await previous.session.cancel()
    }
    guard voice.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
      FileManager.default.fileExists(
        atPath: languageRoot.appendingPathComponent("constants_bin/\(voice.id).safetensors")
          .path)
    else { throw TTSError.unsupportedVoice }
    prepared = (voice, try await manager.makeSession(voice: voice.id))
  }
}
