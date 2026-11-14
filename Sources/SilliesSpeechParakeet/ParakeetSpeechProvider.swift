import FluidAudio
import Foundation
import SilliesSpeech

package struct ParakeetSpeechProvider: SpeechProvider {
  package let id = "fluidaudio"
  package init() {}

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    guard let directory = request.directory else {
      throw SpeechError.unavailable(String(localized: "Parakeet has not been downloaded."))
    }
    let engine = ParakeetWindowEngine()
    try await engine.load(directory)
    let model = WindowSpeechModel(
      engine: SpeechInferenceScheduler(engine: engine), boundaryMode: .adaptive)
    // Core ML may compile prediction kernels after loading. Exercise a bounded silent
    // window before capture so the user's first words do not pay that cost or time out.
    try await model.validate()
    try Task.checkCancellation()
    return model
  }
}
