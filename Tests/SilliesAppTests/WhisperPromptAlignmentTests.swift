import CoreML
import Testing

@testable import SilliesSpeechWhisper

@Test func whisperPromptAlignmentKeepsGeneratedRowsAndDoesNotChangeTheSource() throws {
  for type in [MLMultiArrayDataType.float16, .float32, .double] {
    let original = try MLMultiArray(shape: [8, 3], dataType: type)
    for index in 0..<original.count { original[index] = NSNumber(value: index) }
    let shifted = try PromptAlignmentWeights.removingPrefix(3, from: original)
    #expect(shifted.shape == [5, 3])
    for index in 0..<shifted.count { #expect(shifted[index].intValue == index + 9) }
    #expect(original[0].intValue == 0)
    #expect(try PromptAlignmentWeights.removingPrefix(0, from: original) === original)
    #expect(throws: (any Error).self) {
      try PromptAlignmentWeights.removingPrefix(8, from: original)
    }
  }
}
