import Foundation
import SilliesTTS

/// Only the isolated inference executable sees vendor runtimes and their synchronous callbacks.
typealias NativeSpeechSink = @Sendable ([Float], Int) throws -> Void

protocol NativeTTSModel: Sendable {
  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
}

actor NativeTTSRuntime {
  typealias Factory = @Sendable (TTSPreparation) async throws -> any NativeTTSModel
  private let factories: [String: Factory]
  private var loaded: (configuration: TTSPreparation, model: any NativeTTSModel)?

  init(factories: [String: Factory]) { self.factories = factories }

  func synthesize(_ request: TTSInferenceRequest, output: @escaping NativeSpeechSink) async throws {
    try request.synthesis.validate()
    if loaded?.configuration != request.configuration {
      loaded = nil
      guard let factory = factories[request.configuration.providerID] else {
        throw TTSError.unavailable(
          String(localized: "This voice needs a newer version of Sillies."))
      }
      loaded = (request.configuration, try await factory(request.configuration))
    }
    guard let loaded else { throw TTSError.interrupted }
    try await loaded.model.synthesize(request.synthesis, output: output)
  }
}
