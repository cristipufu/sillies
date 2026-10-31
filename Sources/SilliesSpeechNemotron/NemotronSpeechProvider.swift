import Foundation
import SilliesSpeech

package struct NemotronSpeechProvider: SpeechProvider {
  package let id = "nemotron-unified"
  package init() {}

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    guard let directory = request.directory else {
      throw SpeechError.unavailable(
        "Download Nemotron Unified ASR in Settings → Speech & Meetings.")
    }
    let engine = NemotronStreamingEngine()
    try await engine.load(directory, language: .automatic)
    return NemotronSpeechModel(directory: directory, preparedEngine: engine)
  }
}

private actor NemotronSpeechModel: PreparedSpeechModel {
  let directory: URL
  private var preparedEngine: NemotronStreamingEngine?

  init(directory: URL, preparedEngine: NemotronStreamingEngine) {
    self.directory = directory
    self.preparedEngine = preparedEngine
  }

  func makeChannel(_ request: SpeechChannelRequest) async throws -> any LocalSpeechChannel {
    let engine = try await makeEngine(language: request.language)
    try Task.checkCancellation()
    return try WindowSpeechChannel(
      engine: SpeechInferenceScheduler(engine: engine), request: request, cadence: .streaming)
  }

  func validate() async throws {
    let engine = try await makeEngine(language: .automatic)
    try await WindowSpeechModel(engine: SpeechInferenceScheduler(engine: engine)).validate()
  }

  private func makeEngine(language: SpeechLanguage) async throws -> NemotronStreamingEngine {
    try Task.checkCancellation()
    let prepared = preparedEngine
    preparedEngine = nil
    if language.isAutomatic, let prepared { return prepared }
    let engine = NemotronStreamingEngine()
    try await engine.load(directory, language: language)
    return engine
  }
}
