import Foundation
import SilliesSpeech

package struct NemotronDiarizationProvider: DiarizationProvider {
  package let id = "nemotron-diarization"
  package init() {}
  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedDiarizationModel {
    guard let directory = request.directory else {
      throw SpeechError.unavailable("Download the speaker detection model in Settings first.")
    }
    let runtime = NemotronDiarizationRuntime()
    try await runtime.load(directory)
    return runtime
  }
}
