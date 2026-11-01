import Foundation
import SilliesSpeech

package struct NemotronSpeechProvider: SpeechProvider {
  package let id = "nemotron-unified"
  package init() {}

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    guard let directory = request.directory else {
      throw SpeechError.unavailable(
        String(localized: "Download Nemotron Unified ASR in Settings → Speech & Meetings."))
    }
    let engine = NemotronStreamingEngine()
    try await engine.load(directory, language: .automatic)
    return NemotronSpeechModel(directory: directory, preparedEngine: engine)
  }
}
