import SilliesCore
import Testing

@Test func spokenPhrasesPreserveDecimalsAbbreviationsAndUnicodeAcrossTokenBoundaries() {
  var buffer = SpokenPhraseBuffer()
  var phrases: [String] = []
  let text = "Dr. Ada paid 3.14 euros. Ștefan said hello! こんにちは。次の文です。 👋🏽 Done"
  for character in text { phrases += buffer.append(String(character)) }
  phrases += buffer.finish()
  #expect(phrases.first == "Dr. Ada paid 3.14 euros.")
  #expect(phrases.contains("Ștefan said hello!"))
  #expect(phrases.contains("こんにちは。"))
  #expect(phrases.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
  #expect(buffer.finish().isEmpty)
}

@Test func spokenPhrasesStayBoundedEvenWhenOneDeltaContainsAnEntireLongSentence() {
  for text in [
    String(repeating: "longword ", count: 100) + ". Next", String(repeating: "x", count: 1_000),
  ] {
    var buffer = SpokenPhraseBuffer()
    let phrases = buffer.append(text) + buffer.finish()
    #expect(
      phrases.allSatisfy { !$0.isEmpty && $0.count <= SpokenPhraseBuffer.maximumPhraseCharacters })
    #expect(phrases.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
  }
}

@Test func spokenPhrasesWaitForSentenceLookaheadAndFlushTheLastFragment() {
  var buffer = SpokenPhraseBuffer()
  #expect(buffer.append("Hello there.").isEmpty)
  #expect(buffer.append(" Another") == ["Hello there."])
  #expect(buffer.finish() == ["Another"])
  #expect(buffer.append(" \n \n").isEmpty)
  #expect(buffer.finish().isEmpty)
}
