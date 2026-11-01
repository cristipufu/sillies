import Testing

@testable import SilliesSpeechWhisper

@Test func whisperDictionaryTokensAreReusedWithoutChangingTokenBoundaries() {
  var cache = WhisperVocabularyPrompt()
  var inputs: [String] = []
  let encode: (String) -> [Int] = { text in
    inputs.append(text)
    return Array(0..<200)
  }
  let words = ["Ștefan", "API_v2", "Élodie"]
  for _ in 0..<100 {
    #expect(cache.tokens(for: words, encode: encode) == Array(0..<160))
  }
  #expect(inputs == ["Ștefan, API_v2, Élodie"])
  _ = cache.tokens(for: ["API_v3"], encode: encode)
  #expect(inputs.count == 2)
  #expect(cache.tokens(for: [], encode: encode) == nil)
  _ = cache.tokens(for: words, encode: encode)
  #expect(inputs.count == 3)
}
