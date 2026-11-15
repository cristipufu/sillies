import Synchronization
import Testing

@testable import SilliesSpeech

@Test func acousticConfirmationIsScopedToNewShortInputsAndDoesNotConstructValidatorsForLongAudio()
  async throws
{
  let creations = Mutex(0)
  let policy = SpeechInputValidation.shortWindows(maximumSamples: 4) {
    creations.withLock { $0 += 1 }
    return InputValidationFixture.noise
  }
  #expect(try await !policy.accepts([Float](repeating: 0.1, count: 4)))
  #expect(try await policy.accepts([Float](repeating: 0.1, count: 5)))
  #expect(creations.withLock { $0 } == 1)
  #expect(try await SpeechInputValidation.unchecked.accepts([0.1]))
}

@Test func acousticConfirmationPreservesFailuresAndCancellationAndRejectsInvalidPolicyBounds()
  async throws
{
  for fixture in [InputValidationFixture.failed, .cancelled] {
    let policy = SpeechInputValidation.shortWindows(maximumSamples: 4, factory: { fixture })
    await #expect(throws: (any Error).self) { try await policy.accepts([0.1]) }
    #expect(try await policy.accepts([Float](repeating: 0.1, count: 5)))
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

@Test func partitionedAcousticValidationPreservesQualifiedShortInputs() async throws {
  let shortCreations = Mutex(0)
  let longCreations = Mutex(0)
  let policy = SpeechInputValidation.partitioned(
    maximumShortSamples: 16_000,
    short: {
      shortCreations.withLock { $0 += 1 }
      return InputValidationFixture.failed
    },
    remaining: {
      longCreations.withLock { $0 += 1 }
      return InputValidationFixture.noise
    })
  await #expect(throws: SpeechError.self) { try await policy.accepts([0.1]) }
  await #expect(throws: SpeechError.self) {
    try await policy.accepts([Float](repeating: 0.1, count: 16_000))
  }
  #expect(try await !policy.accepts([Float](repeating: 0.1, count: 16_001)))
  #expect(shortCreations.withLock { $0 } == 2)
  #expect(longCreations.withLock { $0 } == 1)
}
