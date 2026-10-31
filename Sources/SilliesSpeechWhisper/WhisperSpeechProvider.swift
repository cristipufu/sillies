import Foundation
import SilliesSpeech
@preconcurrency import WhisperKit

package struct WhisperSpeechProvider: SpeechProvider {
  package let id = "whisperkit"
  package init() {}

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    guard let directory = request.directory else {
      throw SpeechError.unavailable("Whisper has not been downloaded.")
    }
    let engine = WhisperWindowEngine()
    try await engine.load(directory)
    return WindowSpeechModel(engine: SpeechInferenceScheduler(engine: engine))
  }
}
