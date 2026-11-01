import Foundation
import SilliesTTS

/// Only the isolated inference executable sees vendor runtimes and their synchronous callbacks.
typealias NativeSpeechSink = @Sendable ([Float], Int) throws -> Void

protocol NativeTTSModel: Sendable {
  func prepareVoice(_ voice: SpeechVoice) async throws
  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
}

actor NativeTTSRuntime {
  typealias Factory = @Sendable (TTSPreparation) async throws -> any NativeTTSModel
  private let factories: [String: Factory]
  private var loaded: (configuration: TTSPreparation, model: any NativeTTSModel)?

  init(factories: [String: Factory]) { self.factories = factories }

  func prepare(_ configuration: TTSPreparation, voice: SpeechVoice) async throws {
    try voice.validate()
    if loaded?.configuration != configuration {
      loaded = nil
      guard let factory = factories[configuration.providerID] else {
        throw TTSError.unavailable(
          String(localized: "This voice needs a newer version of Sillies."))
      }
      loaded = (configuration, try await factory(configuration))
    }
    guard let loaded else { throw TTSError.interrupted }
    try await loaded.model.prepareVoice(voice)
  }

  func synthesize(_ request: TTSInferenceRequest, output: @escaping NativeSpeechSink) async throws {
    try request.synthesis.validate()
    try await prepare(request.configuration, voice: request.synthesis.voice)
    guard let loaded else { throw TTSError.interrupted }
    try await loaded.model.synthesize(request.synthesis, output: output)
  }
}
