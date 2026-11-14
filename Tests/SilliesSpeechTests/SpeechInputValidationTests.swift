import Synchronization
import Testing

@testable import SilliesSpeech

@Test func acousticConfirmationIsScopedToNewShortInputsAndDoesNotConstructValidatorsForLongAudio()
  throws
{
  let creations = Mutex(0)
  let policy = SpeechInputValidation.shortWindows(maximumSamples: 4) {
    creations.withLock { $0 += 1 }
    return InputValidationFixture.noise
  }
  #expect(try !policy.accepts([Float](repeating: 0.1, count: 4)))
  #expect(try policy.accepts([Float](repeating: 0.1, count: 5)))
  #expect(creations.withLock { $0 } == 1)
  #expect(try SpeechInputValidation.unchecked.accepts([0.1]))
}

@Test func acousticConfirmationPreservesFailuresAndCancellationAndRejectsInvalidPolicyBounds()
  throws
{
  for fixture in [InputValidationFixture.failed, .cancelled] {
    let policy = SpeechInputValidation.shortWindows(maximumSamples: 4, factory: { fixture })
    #expect(throws: (any Error).self) { try policy.accepts([0.1]) }
    #expect(try policy.accepts([Float](repeating: 0.1, count: 5)))
  }
  for limit in [-1, Int.max] {
    let policy = SpeechInputValidation.shortWindows(
      maximumSamples: limit, factory: { InputValidationFixture.noise })
    #expect(!policy.isValid)
  }
}

private enum InputValidationFixture: SpeechWindowValidating {
  case noise, failed, cancelled
  func containsSpeech(_: [Float]) throws -> Bool {
    switch self {
    case .noise: return false
    case .failed: throw SpeechError.invalidAudioFormat
    case .cancelled: throw CancellationError()
    }
  }
}
