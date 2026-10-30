import Foundation
import SilliesCore
import SilliesSpeech

/// Keeps one loaded model alive for both sources and language changes in this capture only.
actor SpeechCapturePreparation {
  private let registry: SpeechRuntimeRegistry
  private let model: SpeechModelDescriptor
  private var runtime: SpeechRuntimeRegistry.Runtime?
  init(registry: SpeechRuntimeRegistry, model: SpeechModelDescriptor) {
    self.registry = registry
    self.model = model
  }
  func makeChannel(
    language: SpeechLanguage, output: @escaping LocalSpeechFactory.Output,
    failure: @escaping LocalSpeechFactory.Failure
  ) async throws -> any LocalSpeechChannel {
    if runtime == nil { runtime = try await registry.prepare(model) }
    try Task.checkCancellation()
    guard let runtime else {
      throw SpeechError.unavailable("The transcription model could not be prepared.")
    }
    return try await runtime.makeChannel(
      .init(language: language, output: output, failure: failure))
  }
}
