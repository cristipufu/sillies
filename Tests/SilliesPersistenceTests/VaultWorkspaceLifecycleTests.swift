import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultStarAndTrashCountsRemainCorrectAcrossProtectionAndDeletion() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  try database.commit(.init(records: [.insert(record)]))
  try database.editDocument(id: record.id, edit: .star, at: Date())
  #expect(try database.eligibleRetentionCount() == 0)
  record.isProtected = true
  try database.commit(.init(records: [.update(record)]))
  #expect(try database.eligibleRetentionCount() == 0)
  record.isProtected = false
  try database.commit(.init(records: [.update(record)]))
  #expect(try database.eligibleRetentionCount() == 0)
  try database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  #expect(try database.page(.init()).total == 0)
  try database.editDocument(id: record.id, edit: .restore, at: Date())
  #expect(try database.page(.init()).total == 1)
  try database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  try database.commit(.init(deletion: .records([record.id])))
  #expect(try database.page(.init()).total == 0)
  #expect(try database.eligibleRetentionCount() == 0)
  #expect(try database.sql.integer("SELECT coalesce(sum(total),0) FROM trash_counts") == 0)
}

@Test func vaultTextPreservesEmbeddedNULAndOriginalIsNeverAddedByIndexRebuild() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "Earlier mistakenword")))
  try database.commit(.init(records: [.insert(record)]))
  let location = VaultBlockLocation(recordID: record.id, section: .transcript)
  try database.editText(
    .init(
      location: location, expectedRevision: database.sectionRevision(location),
      text: "corrected\0retained"), at: Date())
  #expect(try database.sectionText(location) == "corrected\0retained")
  try database.sql.execute("INSERT INTO content_search(content_search) VALUES('rebuild')")
  #expect(try database.workspacePage(.init(text: "mistakenword")).records.isEmpty)
  #expect(try database.record(id: record.id)?.transcript == "corrected\0retained")
}

@Test func vaultMetadataDraftSurvivesRestartAndDoesNotReplaceUneditedFields() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
  _ = try database.createDocument(
    record: record, metadata: .init(kind: .note, title: "Original", modifiedAt: Date()))
  let draft = VaultMetadataDraft(recordID: record.id, title: "Recovered title", tags: nil)
  try database.saveMetadataDraft(draft)
  try database.editDocument(id: record.id, edit: .tags(["concurrent"]), at: Date())
  let reopened = try VaultDatabase(directory: directory)
  let recovered = try #require(try reopened.metadataDraft(id: record.id))
  #expect(recovered.id == draft.id)
  let saved = try reopened.commitMetadataDraft(recovered, at: Date())
  #expect(saved.title == "Recovered title")
  #expect(saved.metadata.tags == ["concurrent"])
  try reopened.saveMetadataDraft(draft)
  try reopened.commit(.init(deletion: .records([record.id])))
  #expect(try reopened.metadataDraft(id: record.id) == nil)
}

@Test func vaultRejectsOverflowingLocationsAndFindsURLsBeyondOrdinaryNotes() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  for index in 0..<110 {
    let record = SessionRecord(
      kind: .stash,
      origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
    let title = "Note \(index)"
    _ = try database.createDocument(
      record: record, metadata: .init(kind: .note, title: title, modifiedAt: Date()))
  }
  let linkRecord = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
  var metadata = VaultDocumentMetadata(kind: .link, title: "Reference", modifiedAt: Date())
  metadata.link = try VaultLink(url: #require(URL(string: "https://example.com/reference")))
  _ = try database.createDocument(record: linkRecord, metadata: metadata)
  #expect(
    try database.search(.init(query: "", category: .links)).map(\.header.id) == [linkRecord.id])
  #expect(throws: VaultEditingError.self) {
    try database.sectionPage(.init(recordID: linkRecord.id, section: .notes, ordinal: Int.max))
  }
}

@Test func vaultSearchNeverReturnsSupersededSourceWhileOtherRecordsAwaitMigration() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let origin = SessionOrigin(
    characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture"))
  let edited = SessionRecord(
    kind: .record, origin: origin, content: .init(text: .init(transcript: "supersededword")))
  let pending = SessionRecord(
    kind: .record, origin: origin, content: .init(text: .init(transcript: "Different source")))
  try database.commit(.init(records: [.insert(edited), .insert(pending)]))
  let location = VaultBlockLocation(recordID: edited.id, section: .transcript)
  try database.editText(
    .init(
      location: location, expectedRevision: database.sectionRevision(location),
      text: "correctedword"), at: Date())
  try database.sql.execute(
    "INSERT INTO content_backfill SELECT sequence,id FROM records WHERE id=?",
    [.text(pending.id.uuidString)])
  #expect(try database.search(.init(query: "supersededword")).isEmpty)
  #expect(try database.search(.init(query: "correctedword")).map(\.header.id) == [edited.id])
}

@Test func vaultFinalizedSourceKeepsItsOriginalTranscriptAndPlaybackAnchor() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "Partial")))
  try database.commit(.init(records: [.insert(record)]))
  record.transcript = "Final words"
  record.transcriptSegments = [
    .init(sequence: 0, source: "microphone", start: 4, end: 7, text: "Final words")
  ]
  try database.commit(.init(records: [.update(record)]))
  let transcript = VaultBlockLocation(recordID: record.id, section: .transcript)
  #expect(try database.sectionPage(transcript).blocks.first?.startSeconds == 4)
  #expect(
    try database.sectionText(.init(recordID: record.id, section: .originalTranscript))
      == "Final words")
  try database.editText(
    .init(
      location: transcript, expectedRevision: database.sectionRevision(transcript),
      text: "Corrected words"), at: Date())
  #expect(try database.sectionPage(transcript).blocks.first?.startSeconds == nil)
  var regenerated = try #require(try database.record(id: record.id))
  regenerated.summary = "Refreshed summary of the corrected words"
  try database.commit(.init(records: [.update(regenerated)]))
  #expect(
    try database.sectionText(.init(recordID: record.id, section: .originalTranscript))
      == "Final words")
}

@Test func vaultStarredScopeKeepsPreviouslyProtectedCapturesDiscoverable() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(
      characterID: "pogo", characterName: "Pogo", source: .init(appName: "Protected meeting")))
  record.isProtected = true
  try database.commit(.init(records: [.insert(record)]))
  #expect(try database.workspacePage(.init(scope: .starred)).records.map(\.id) == [record.id])
  try database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  #expect(try database.workspacePage(.init(scope: .starred)).records.isEmpty)
}
