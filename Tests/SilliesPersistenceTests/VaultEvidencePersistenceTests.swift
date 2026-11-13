import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultEvidenceLocatesLateUnicodeAndNULTextWithoutDecodingTheSourceBody() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let prefix = String(repeating: "Ședință 👩🏽‍💻 e\u{301}\0 earlier. ", count: 200)
  let excerpt = "Decizia este joi."
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: prefix + excerpt)))
  try database.commit(.init(records: [.insert(record)]))
  try database.prepareContent(id: record.id)
  let before = database.metrics.loadedBodies
  let passages = try database.evidence(
    recordID: record.id, section: .transcript,
    bytes: prefix.utf8.count..<(prefix.utf8.count + excerpt.utf8.count), expected: excerpt)
  #expect(passages.map(\.text).joined() == excerpt)
  #expect(database.metrics.loadedBodies == before)
  for passage in passages { #expect(try database.evidenceLocation(passage) != nil) }
  let saved = try #require(passages.first)
  let location = saved.reference.location
  try database.editText(
    .init(
      location: .init(recordID: record.id, section: .transcript),
      expectedRevision: database.sectionRevision(location), text: "Changed text"), at: Date())
  #expect(try database.evidenceLocation(saved) == nil)
}

@Test func vaultEvidenceRejectsTrashedDeletedAndUnmatchedText() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: "Original source")))
  try database.commit(.init(records: [.insert(record)]))
  try database.prepareContent(id: record.id)
  let passage = try #require(
    try database.evidence(
      recordID: record.id, section: .transcript,
      bytes: 0..<8, expected: "Original"
    ).first)
  #expect(
    try database.evidence(
      recordID: record.id, section: .transcript,
      bytes: 0..<8, expected: "Changed!"
    ).isEmpty)
  try database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  #expect(try database.evidenceLocation(passage) == nil)
  try database.commit(.init(deletion: .records([record.id])))
  #expect(try database.evidenceLocation(passage) == nil)
}
