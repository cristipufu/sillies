import Foundation
import SilliesAudio
import SilliesCore
import SilliesSpeech

/// Keeps one loaded model alive for both sources and language changes in this capture only.
actor SpeechCapturePreparation {
  private let registry: SpeechRuntimeRegistry
  private let model: SpeechModelDescriptor
  private let context: SpeechRecognitionContext
  private let backlogDirectory: URL?
  private var runtime: SpeechRuntimeRegistry.Runtime?
  init(
    registry: SpeechRuntimeRegistry, model: SpeechModelDescriptor,
    context: SpeechRecognitionContext = .init(), backlogDirectory: URL? = nil
  ) {
    self.registry = registry
    self.model = model
    self.context = context
    self.backlogDirectory = backlogDirectory
  }
  func makeChannel(
    language: SpeechLanguage, output: @escaping LocalSpeechFactory.Output,
    failure: @escaping LocalSpeechFactory.Failure
  ) async throws -> any LocalSpeechChannel {
    if runtime == nil { runtime = try await registry.prepare(model) }
    try Task.checkCancellation()
    guard let runtime else {
      throw SpeechError.unavailable(
        String(localized: "The transcription model could not be prepared."))
    }
    var request = SpeechChannelRequest(language: language, output: output, failure: failure)
    request.context = context
    if let backlogDirectory {
      request.audioBackingStore = DiskSpeechAudioStore(directory: backlogDirectory)
    }
    return try await runtime.makeChannel(request)
  }
}
