import Foundation
import SilliesSpeech
@preconcurrency import WhisperKit

package struct WhisperSpeechProvider: SpeechProvider {
  package let id = "whisperkit"
  private let makeShortInputValidator: SpeechWindowValidatorFactory
  package init(makeShortInputValidator: @escaping SpeechWindowValidatorFactory) {
    self.makeShortInputValidator = makeShortInputValidator
  }

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    guard let directory = request.directory else {
      throw SpeechError.unavailable(String(localized: "Whisper has not been downloaded."))
    }
    let engine = WhisperWindowEngine()
    try await engine.load(directory)
    let minimum = try WhisperTranscriptionInput.minimumSampleCount(options: .init())
    return WindowSpeechModel(
      engine: SpeechInferenceScheduler(engine: engine),
      configuration: .init(
        inputValidation: .shortWindows(
          maximumSamples: minimum - 1, factory: makeShortInputValidator)))
  }
}
