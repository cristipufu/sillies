import FluidAudio
import SilliesSpeech

/// Adapts the streaming pipeline's final partial window to Parakeet's input contract.
struct ParakeetTranscriptionInput {
  static let minimumSampleCount = ASRConstants.minimumRequiredSamples(
    forSampleRate: ASRConstants.sampleRate)
  let samples: [Float]
  let language: Language?

  init(_ request: SpeechWindowRequest) throws {
    if request.language.isAutomatic {
      language = nil
    } else {
      let code = request.language.locale.language.languageCode?.identifier ?? request.language.id
      guard let hint = Language(rawValue: code) else {
        throw SpeechError.unavailable("Parakeet does not support this language hint.")
      }
      language = hint
    }
    // Keep every captured sample. Padding is decoder context only: the channel still retires
    // the original window, so silence never extends session time or shifts subsequent speech.
    let missing = max(0, Self.minimumSampleCount - request.samples.count)
    samples = missing == 0 ? request.samples : request.samples + Array(repeating: 0, count: missing)
  }
}
