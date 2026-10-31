import FluidAudio
import Foundation
import SilliesSpeech

package struct ParakeetSpeechProvider: SpeechProvider {
  package let id = "fluidaudio"
  package init() {}

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    guard let directory = request.directory else {
      throw SpeechError.unavailable("Parakeet has not been downloaded.")
    }
    let engine = ParakeetWindowEngine()
    try await engine.load(directory)
    return WindowSpeechModel(engine: SpeechInferenceScheduler(engine: engine))
  }
}
