import Foundation
import SilliesCore
import SilliesSpeech

/// Keeps one loaded model alive for both sources and language changes in this capture only.
actor SpeechCapturePreparation {
  private let registry: SpeechRuntimeRegistry
  private let model: SpeechModelDescriptor
  private let context: SpeechRecognitionContext
  private var runtime: SpeechRuntimeRegistry.Runtime?
  init(
    registry: SpeechRuntimeRegistry, model: SpeechModelDescriptor,
    context: SpeechRecognitionContext = .init()
  ) {
    self.registry = registry
    self.model = model
    self.context = context
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
    var request = SpeechChannelRequest(language: language, output: output, failure: failure)
    request.context = context
    return try await runtime.makeChannel(request)
  }
}
