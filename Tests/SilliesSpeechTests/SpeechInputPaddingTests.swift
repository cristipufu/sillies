import Testing

@testable import SilliesSpeech

@Test func decoderPaddingPreservesOriginalSamplesAndLeavesEmptyOrLongInputIntact() throws {
  #expect(try SpeechInputPadding.extending([], toMinimumSampleCount: 5).isEmpty)
  #expect(
    try SpeechInputPadding.extending([0.5, -0.5], toMinimumSampleCount: 5) == [0.5, -0.5, 0, 0, 0])
  #expect(try SpeechInputPadding.extending([0.5, -0.5], toMinimumSampleCount: 1) == [0.5, -0.5])
}

@Test func decoderPaddingRejectsUnsafeNativeRequirementsAndInvalidSamplesBeforeAllocating() {
  for minimum in [-1, Int.max, 192_001] {
    #expect(throws: SpeechError.self) {
      try SpeechInputPadding.extending([0.5], toMinimumSampleCount: minimum)
    }
  }
  for sample: Float in [.nan, .infinity, -.infinity] {
    #expect(throws: SpeechError.self) {
      try SpeechInputPadding.extending([sample], toMinimumSampleCount: 0)
    }
  }
}
