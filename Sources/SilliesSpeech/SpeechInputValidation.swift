package enum SpeechInputValidation: Sendable {
  case unchecked
  case shortWindows(maximumSamples: Int, factory: SpeechWindowValidatorFactory)

  case partitioned(
    maximumShortSamples: Int, short: SpeechWindowValidatorFactory,
    remaining: SpeechWindowValidatorFactory)

  var isValid: Bool {
    switch self {
    case .unchecked: true
    case .shortWindows(let maximum, _), .partitioned(let maximum, _, _):
      (0...SpeechWindowConfiguration.maximumSampleCount).contains(maximum)
    }
  }

  func accepts(_ samples: [Float]) async throws -> Bool {
    guard let factory = validator(forSampleCount: samples.count) else { return true }
    try Task.checkCancellation()
    let accepted = try await factory().containsSpeech(samples)
    try Task.checkCancellation()
    return accepted
  }

  private func validator(forSampleCount count: Int) -> SpeechWindowValidatorFactory? {
    switch self {
    case .unchecked: nil
    case .shortWindows(let maximum, let factory): count <= maximum ? factory : nil
    case .partitioned(let maximum, let short, let remaining): count <= maximum ? short : remaining
    }
  }
}
