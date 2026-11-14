import SilliesSpeech
import WhisperKit

/// The native seek loop requires input strictly longer than its trailing seek guard.
struct WhisperTranscriptionInput {
  enum Context: Sendable { case captured, extended }
  let samples: [Float]
  let context: Context

  init(_ samples: [Float], options: DecodingOptions) throws {
    self.samples = try SpeechInputPadding.extending(
      samples, toMinimumSampleCount: Self.minimumSampleCount(options: options))
    context = self.samples.count == samples.count ? .captured : .extended
  }

  static func minimumSampleCount(options: DecodingOptions) throws -> Int {
    let guardSamples = options.windowClipTime * Float(WhisperKit.sampleRate)
    guard options.windowClipTime >= 0,
      let count = Int(exactly: guardSamples.rounded(.towardZero)), count >= 0, count < Int.max
    else { throw SpeechError.invalidAudioFormat }
    return count + 1
  }
}
