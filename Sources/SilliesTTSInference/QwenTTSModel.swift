import Foundation
import SilliesTTS
import Synchronization
import TTSKit

actor QwenTTSModel: NativeTTSModel {
  private static let sampleRate = 24_000
  private static let maximumGeneratedTokens = 500
  private static let languages = [
    "en": "english", "zh": "chinese", "ja": "japanese", "ko": "korean", "de": "german",
    "fr": "french", "ru": "russian", "pt": "portuguese", "es": "spanish", "it": "italian",
  ]
  private let model: TTSKit
  private var preparedVoice: SpeechVoice?

  init(configuration: TTSPreparation) async throws {
    guard let variant = TTSModelVariant(rawValue: configuration.variant) else {
      throw SilliesTTS.TTSError.invalidRequest
    }
    model = try await TTSKit(
      TTSKitConfig(
        model: variant, modelFolder: configuration.directory,
        tokenizerFolder: configuration.directory.appendingPathComponent("tokenizer"),
        download: false, load: true))
  }

  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
  {
    let language = try Self.modelLanguage(request.language)
    let failure = Mutex<(any Error)?>(nil)
    _ = try await model.generate(
      text: request.text, voice: request.voiceID, language: language,
      options: GenerationOptions(
        maxNewTokens: Self.maximumGeneratedTokens, concurrentWorkerCount: 1,
        chunkingStrategy: TextChunkingStrategy.none)
    ) { progress in
      guard !Task.isCancelled else { return false }
      do {
        if !progress.audio.isEmpty { try output(progress.audio, Self.sampleRate) }
        return true
      } catch {
        failure.withLock { $0 = error }
        return false
      }
    }
    if let error = failure.withLock({ $0 }) { throw error }
  }

  func prepareVoice(_ voice: SpeechVoice) async throws {
    guard preparedVoice != voice else { return }
    _ = try await model.buildPromptCache(
      voice: voice.id, language: Self.modelLanguage(voice.language))
    preparedVoice = voice
  }

  private static func modelLanguage(_ identifier: String) throws -> String {
    let languageCode =
      identifier.replacingOccurrences(of: "_", with: "-")
      .lowercased().split(separator: "-").first.map(String.init) ?? ""
    guard let language = Self.languages[languageCode] else {
      throw SilliesTTS.TTSError.unsupportedLanguage
    }
    return language
  }
}
