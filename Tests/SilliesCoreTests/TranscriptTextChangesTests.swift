import Foundation
import SilliesCore
import Testing

@Test(arguments: [
  ("", "First\nSecond"), ("First\nSecond", ""), ("First\n", "First\nLast\n"),
  ("First\nSecond\nThird", "Second\nThird\nFourth"),
  ("A\n\nB\n", "\nB\nC"), ("Repeated\nRepeated\nLast", "Repeated\nLast\nRepeated"),
  ("🐈‍⬛ old\r\nCafé\nEnd", "🐈‍⬛ new\r\nCafe\u{301}\nEnd"),
])
func transcriptParagraphEditsReproduceLiteralText(_ previous: String, _ current: String) {
  let changes = TranscriptTextChanges(replacing: previous, with: current)
  let text = NSMutableString(string: previous)
  for edit in changes.edits {
    text.replaceCharacters(
      in: NSRange(location: edit.utf16Range.lowerBound, length: edit.utf16Range.count),
      with: edit.replacement)
  }
  #expect((text as String).utf8.elementsEqual(current.utf8))
}

@Test func rollingTranscriptEditsPreserveUnchangedParagraphs() {
  let middle = String(repeating: "Unchanged meeting passage.\n", count: 200)
  let changes = TranscriptTextChanges(
    replacing: "Old prefix\n" + middle + "Old draft", with: "New prefix\n" + middle + "New draft")
  #expect(changes.edits.count == 4)
  #expect(changes.edits.allSatisfy { !$0.replacement.contains("Unchanged") })
}
