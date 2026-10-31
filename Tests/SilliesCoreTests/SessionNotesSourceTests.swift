import Foundation
import Testing

@testable import SilliesCore

@Test func extractedHighlightsAreIdentifiedInSavedRecordsAndExports() throws {
  var record = SessionRecord(
    kind: .record,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Microphone")),
    content: .init(notes: .init(summary: "• O propoziție din înregistrare.")))
  record.notesSource = .extracted
  record.notesNotice = "Local model unavailable"
  record.processingNote = "Speaker detection unavailable"
  let data = try JSONEncoder().encode(record)
  let loaded = try JSONDecoder().decode(SessionRecord.self, from: data)
  #expect(loaded.notesSource == .extracted)
  #expect(loaded.notesNotice == record.notesNotice)
  #expect(loaded.processingNote == record.processingNote)
  #expect(SessionMarkdownFormatter.format(loaded).contains("## Extracted Highlights"))
  #expect(!SessionMarkdownFormatter.format(loaded).contains("## Summary"))
  var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  legacy.removeValue(forKey: "notesSource")
  legacy.removeValue(forKey: "notesNotice")
  let old = try JSONDecoder().decode(
    SessionRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
  #expect(old.notesSource == .unspecified)
  #expect(old.notesNotice.isEmpty)
  #expect(old.summary == record.summary)
}
