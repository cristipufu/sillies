import Testing

@testable import SilliesTextModels

@Test func generatedTextRejectsConsecutiveLoopsWithoutMatchingSpecificWords() {
  for phrase in ["I'm 100% sure ", "încă o dată ", "你好世界", "another unrelated repeated phrase. "] {
    #expect(
      TextRepetitionGuard.containsLoop("Answer: " + String(repeating: phrase, count: 40) + "trunca")
    )
  }
  #expect(!TextRepetitionGuard.containsLoop("Very, very, very happy to meet you!"))
  #expect(!TextRepetitionGuard.containsLoop("Ha ha ha!"))
  #expect(!TextRepetitionGuard.containsLoop(""))
  #expect(
    !TextRepetitionGuard.containsLoop(
      "First, check the request. Next, check the reply. Finally, check the result. Nothing here repeats in a continuous cycle, even though some words appear several times."
    ))
}
