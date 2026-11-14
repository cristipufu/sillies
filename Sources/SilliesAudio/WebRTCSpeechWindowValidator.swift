import SilliesCore
import SilliesSpeech

/// Fresh native classification confirms short input without trimming the audio sent to a decoder.
package struct WebRTCSpeechWindowValidator: SpeechWindowValidating {
  package init() {}

  package func containsSpeech(_ samples: [Float]) throws -> Bool {
    guard samples.count <= SpeechWindowConfiguration.maximumSampleCount else {
      throw SpeechError.invalidAudioFormat
    }
    guard !samples.isEmpty else { return false }
    let classifier = try WebRTCVoiceClassifier(mode: .transcription)
    var normalization = SpeechSignalNormalization(gain: .init(purpose: .detection))
    let adjustment = try normalization.prepare(samples)
    var endpoint = VoiceTurnEndpoint()
    for start in stride(from: 0, to: samples.count, by: WebRTCVoiceClassifier.frameSamples) {
      try Task.checkCancellation()
      let end = min(samples.count, start + WebRTCVoiceClassifier.frameSamples)
      let frame = adjustment.apply(to: Array(samples[start..<end]))
      if endpoint.consume(
        isSpeech: try classifier.isSpeech(frame),
        duration: Double(frame.count) / Double(MeetingAudioTimeline.sampleRate)) == .began
      {
        return true
      }
    }
    return false
  }
}
