import Foundation
import SilliesSpeech
@preconcurrency import WhisperKit

package struct WhisperSpeechProvider: SpeechProvider {
  package let id = "whisperkit"
  private enum Validation: Sendable {
    case shortInputs(SpeechWindowValidatorFactory)
    case longInputs(
      SpeechWindowValidatorFactory, @Sendable () async throws -> any SpeechWindowValidating)
  }
  private let validation: Validation
  package init(makeShortInputValidator: @escaping SpeechWindowValidatorFactory) {
    validation = .shortInputs(makeShortInputValidator)
  }

  package init(
    makeShortInputValidator: @escaping SpeechWindowValidatorFactory,
    prepareLongInputValidator: @escaping @Sendable () async throws -> any SpeechWindowValidating
  ) {
    validation = .longInputs(makeShortInputValidator, prepareLongInputValidator)
  }

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    guard let directory = request.directory else {
      throw SpeechError.unavailable(String(localized: "Whisper has not been downloaded."))
    }
    let inputValidation = try await prepareValidation()
    let engine = WhisperWindowEngine()
    try await engine.load(directory)
    return WindowSpeechModel(
      engine: SpeechInferenceScheduler(engine: engine),
      configuration: .init(inputValidation: inputValidation))
  }

  private func prepareValidation() async throws -> SpeechInputValidation {
    let minimum = try WhisperTranscriptionInput.minimumSampleCount(options: .init())
    switch validation {
    case .shortInputs(let factory):
      return .shortWindows(maximumSamples: minimum - 1, factory: factory)
    case .longInputs(let short, let prepare):
      let validator = try await prepare()
      try Task.checkCancellation()
      return .partitioned(maximumShortSamples: minimum - 1, short: short, remaining: { validator })
    }
  }
}
