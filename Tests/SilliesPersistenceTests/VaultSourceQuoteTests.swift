import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultQuotationsAppendWithoutLoadingTheDocumentAndSurviveTheirSource() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let source = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "The decision was to ship on Friday.")))
  let target = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  try database.commit(.init(records: [.insert(source)]))
  let original = String(repeating: "A durable thought.\n", count: 10_000)
  _ = try database.createDocument(
    record: target, metadata: .init(kind: .note, title: "Plan", modifiedAt: Date()), notes: original
  )
  let block = try #require(
    database.sectionPage(.init(recordID: source.id, section: .transcript)).blocks.first)
  let reference = VaultSourceReference(block: block)
  #expect(VaultSourceReference(link: reference.link) == reference)
  let quote = try VaultQuotedPassage(
    reference: reference, title: "The [decision]", text: block.text)
  let location = try database.appendQuote(quote, to: target.id, at: Date())
  #expect(location.ordinal > 0)
  #expect(try database.authoredNotes(recordID: target.id) == original + "\n\n" + quote.markdown)
  #expect(try database.sourceLocation(reference) == block.location)
  try database.commit(.init(deletion: .records([source.id])))
  #expect(try database.sourceLocation(reference) == nil)
  #expect(try database.sectionPage(location).blocks.map(\.text).joined().contains(reference.link))
  #expect(database.metrics.loadedBodies == 0)
}

@Test func vaultQuotationsPreserveUnsavedNotesAndRejectUntrustedSourceLinks() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  _ = try database.createDocument(
    record: record, metadata: .init(kind: .note, title: "Plan", modifiedAt: Date()),
    notes: "Existing notes")
  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  let block = try #require(database.sectionPage(location).blocks.first)
  let reference = VaultSourceReference(block: block)
  let quote = try VaultQuotedPassage(reference: reference, title: "Original", text: "Quoted")
  try database.saveDraft(
    .init(location: location, revision: block.revision, range: 0..<1, text: "My unsaved draft"))
  #expect(throws: VaultEditingError.self) {
    try database.appendQuote(quote, to: record.id, at: Date())
  }
  #expect(try database.draft(location)?.text == "My unsaved draft")
  #expect(try database.authoredNotes(recordID: record.id) == "Existing notes")
  for link in [
    reference.link + "&block=1",
    reference.link.replacingOccurrences(of: "sillies-vault:", with: "https:"),
    "sillies-vault://source/../../etc/passwd",
    reference.link.replacingOccurrences(of: "/notes/0", with: "/notes/-1"),
  ] {
    #expect(VaultSourceReference(link: link) == nil)
  }
}
