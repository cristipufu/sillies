/// Adds decoder context without changing the captured window or its transcript clock.
package enum SpeechInputPadding {
  package static func extending(_ samples: [Float], toMinimumSampleCount minimum: Int) throws
    -> [Float]
  {
    guard (0...SpeechWindowConfiguration.maximumSampleCount).contains(minimum),
      samples.allSatisfy(\.isFinite)
    else {
      throw SpeechError.invalidAudioFormat
    }
    guard !samples.isEmpty, samples.count < minimum else { return samples }
    return samples + Array(repeating: 0, count: minimum - samples.count)
  }
}
