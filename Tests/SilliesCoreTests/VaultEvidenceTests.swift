import Foundation
import Testing

@testable import SilliesCore

@Test func evidenceRangesPreserveUnicodeAndRejectChangedOrMalformedSources() throws {
  let prefix = "Ședință 👩🏽‍💻 e\u{301}\0 "
  let block = evidenceBlock(text: prefix + "Decizie: joi.")
  let passage = try #require(
    VaultEvidencePassage(
      block: block, scalarOffset: prefix.unicodeScalars.count, text: "Decizie: joi."))
  let range = try #require(passage.range(in: block))
  #expect(String(block.text[range]) == passage.text)
  #expect(NSRange(range, in: block.text).location == (prefix as NSString).length)
  let edited = evidenceBlock(text: block.text, revision: UUID())
  #expect(passage.range(in: edited) == nil)
  #expect(VaultEvidencePassage(block: block, scalarOffset: Int.max, text: "wrong") == nil)
  #expect(VaultEvidencePassage(block: block, scalarOffset: -1, text: "wrong") == nil)
  #expect(VaultEvidencePassage(block: block, scalarOffset: 0, text: "wrong") == nil)
}

@Test func sourceEvidenceKeepsOnlyTheExcerptAdmittedByTheBudget() throws {
  let first = evidenceBlock(text: "First 👩🏽‍💻 passage.")
  let second = evidenceBlock(text: "Another passage.", id: 2, recordID: first.location.recordID)
  let a = try #require(VaultEvidencePassage(block: first, scalarOffset: 0, text: first.text))
  let b = try #require(VaultEvidencePassage(block: second, scalarOffset: 0, text: second.text))
  let source = evidenceSource(id: first.location.recordID, text: first.text + "\n\n" + second.text)
    .withPassages([a, b])
  let trimmed = source.withExcerpt(first.text + "\n\nAno")
  #expect(trimmed.passages.map(\.text) == [first.text, "Ano"])
  #expect(source.withExcerpt("").passages.isEmpty)
  #expect(source.withExcerpt("Different evidence").passages.isEmpty)
}

@Test func sourceEvidenceMergesDistinctPassagesAndSurvivesMessagePersistence() throws {
  let first = evidenceBlock(text: "Budget: 900.")
  let second = evidenceBlock(text: "Deadline: Thursday.", id: 2, recordID: first.location.recordID)
  let a = try #require(VaultEvidencePassage(block: first, scalarOffset: 0, text: first.text))
  let b = try #require(VaultEvidencePassage(block: second, scalarOffset: 0, text: second.text))
  let source = evidenceSource(id: first.location.recordID, text: first.text).withPassages([a])
  let combined = source.mergingEvidence(from: source.withPassages([b])).mergingEvidence(
    from: source)
  #expect(combined.id == source.id)
  #expect(combined.passages == [a, b])
  let shorter = try #require(a.prefix(4))
  let expanded = source.withPassages([shorter, b]).mergingEvidence(from: source)
  #expect(expanded.passages == [a, b])
  let message = ChatMessage(
    role: .companion, text: "Thursday", evidence: .init(sources: [combined]))
  #expect(
    try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message)) == message)
}

@Test func evidenceDecodingRejectsUntrustedOffsetsAndOversizedQuotations() throws {
  let block = evidenceBlock(text: "Source")
  let passage = try #require(VaultEvidencePassage(block: block, scalarOffset: 0, text: "Source"))
  let encoded = try JSONEncoder().encode(passage)
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  object["scalarOffset"] = -1
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(
      VaultEvidencePassage.self, from: JSONSerialization.data(withJSONObject: object))
  }
  object["scalarOffset"] = 0
  object["text"] = String(repeating: "x", count: VaultEvidencePassage.maximumCharacters + 1)
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(
      VaultEvidencePassage.self, from: JSONSerialization.data(withJSONObject: object))
  }
}

@Test func sourceDecodingRejectsEvidenceThatBelongsToAnotherRecord() throws {
  let block = evidenceBlock(text: "Source")
  let passage = try #require(VaultEvidencePassage(block: block, scalarOffset: 0, text: "Source"))
  let source = evidenceSource(id: block.location.recordID, text: block.text).withPassages([passage])
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
  object["id"] = UUID().uuidString
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(ChatSource.self, from: JSONSerialization.data(withJSONObject: object))
  }
}

private func evidenceBlock(
  text: String, id: Int64 = 1, recordID: UUID = UUID(), revision: UUID = UUID()
) -> VaultContentBlock {
  .init(
    id: id, location: .init(recordID: recordID, section: .transcript), revision: revision,
    text: text,
    startSeconds: 522, speaker: "Speaker 2")
}

private func evidenceSource(id: UUID, text: String) -> ChatSource {
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    metadata: .init(id: id))
  return .init(header: .init(record), excerpt: text)
}
