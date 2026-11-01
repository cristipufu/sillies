import Foundation
import SilliesCore
import Testing

@Test func spokenOpeningUsesAShorterBoundaryWithoutLosingTheRestOfTheSentence() throws {
  var buffer = SpokenPhraseBuffer()
  let text = String(repeating: "helpful words ", count: 30)
  let phrases = buffer.append(text) + buffer.finish()
  let opening = try #require(phrases.first)
  #expect(opening.count <= SpokenPhraseBuffer.maximumOpeningCharacters)
  #expect(phrases.dropFirst().contains { $0.count > SpokenPhraseBuffer.maximumOpeningCharacters })
  #expect(phrases.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
}

@Test func spokenOpeningWaitsForLongIdentifiersWithoutSplittingThemEarly() {
  var buffer = SpokenPhraseBuffer()
  let identifier = String(repeating: "a", count: 100)
  #expect(buffer.append(identifier).isEmpty)
  #expect(buffer.flushOpeningPhrase().isEmpty)
  #expect(buffer.finish() == [identifier])
  buffer = SpokenPhraseBuffer()
  let longerText = identifier + " " + String(repeating: "words ", count: 30)
  let phrases = buffer.append(longerText) + buffer.finish()
  #expect(phrases.first?.hasPrefix(identifier + " ") == true)
  #expect(phrases.joined(separator: " ") == longerText.trimmingCharacters(in: .whitespaces))
}

@Test func spokenOpeningDeadlinePreservesPartialWordsNumbersAndUnicode() {
  var buffer = SpokenPhraseBuffer()
  #expect(buffer.append("The total is 12.50 for Ștefan and API_").isEmpty)
  let first = buffer.flushOpeningPhrase()
  #expect(first == ["The total is 12.50 for Ștefan and"])
  #expect(buffer.flushOpeningPhrase().isEmpty)
  let rest = buffer.append("v2 tomorrow.") + buffer.finish()
  #expect(rest == ["API_v2 tomorrow."])
}

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
