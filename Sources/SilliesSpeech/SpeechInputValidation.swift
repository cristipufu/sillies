package enum SpeechInputValidation: Sendable {
  case unchecked
  case shortWindows(maximumSamples: Int, factory: SpeechWindowValidatorFactory)

  var isValid: Bool {
    switch self {
    case .unchecked: true
    case .shortWindows(let maximum, _):
      (0...SpeechWindowConfiguration.maximumSampleCount).contains(maximum)
    }
  }

  func accepts(_ samples: [Float]) throws -> Bool {
    switch self {
    case .unchecked: return true
    case .shortWindows(let maximum, let factory):
      guard samples.count <= maximum else { return true }
      try Task.checkCancellation()
      return try factory().containsSpeech(samples)
    }
  }
}
