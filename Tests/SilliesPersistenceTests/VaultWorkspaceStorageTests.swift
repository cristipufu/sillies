import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultProtectionKeepsSearchDocumentsAndEmbeddingsStable() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeWorkspaceFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: "We agreed to make offline access dependable.")))
  try database.commit(.init(records: [.insert(record)]))
  let passage = try #require(try database.pendingPassage())
  try database.savePassage(passage)
  let item = try #require(try database.pendingVaultEmbedding(provider: "fixture"))
  try database.saveVaultEmbedding(
    .init(space: "fixture", values: [1, 0]), for: item, provider: "fixture")
  let before = database.metrics.indexedSections
  record.isProtected = true
  try database.commit(.init(records: [.update(record)]))
  #expect(database.metrics.indexedSections == before)
  #expect(try database.vaultIndexProgress(provider: "fixture").searchable == 1)
  #expect(try database.eligibleRetentionCount() == 0)
  record.isProtected = false
  try database.commit(.init(records: [.update(record)]))
  #expect(try database.eligibleRetentionCount() == 1)
  try database.commit(.init(deletion: .records([record.id])))
  #expect(try database.search(.init(query: "offline")).isEmpty)
  #expect(try database.sql.integer("SELECT count(*) FROM document_identities") == 0)
  #expect(try database.eligibleRetentionCount() == 0)
}

private func removeWorkspaceFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Could not remove Vault workspace fixture: \(error)")
  }
}

@Test func vaultVisiblePagesAndMetadataEditsDoNotReadSourceBodies() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeWorkspaceFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(
      text: .init(
        transcript: String(repeating: "A long meeting with careful decisions.\n", count: 4_000))))
  try database.commit(.init(records: [.insert(record)]))
  let page = try database.sectionPage(.init(recordID: record.id, section: .transcript))
  #expect(page.blocks.count == VaultSectionPage.maximumBlocks)
  #expect(page.nextOrdinal != nil)
  let bodyWrites = database.metrics.writtenBodies
  try database.editDocument(id: record.id, edit: .rename("The decision review"), at: Date())
  #expect(
    try database.workspacePage(.init(text: "decision review")).records.map(\.id) == [record.id])
  let indexed = database.metrics.indexedSections
  try database.editDocument(id: record.id, edit: .star, at: Date())
  #expect(
    try database.workspacePage(.init(scope: .starred)).records.first?.title == "The decision review"
  )
  #expect(database.metrics.loadedBodies == 0)
  #expect(database.metrics.writtenBodies == bodyWrites)
  #expect(database.metrics.indexedSections == indexed)
  let unchanged = try database.sectionPage(.init(recordID: record.id, section: .transcript))
  #expect(unchanged.blocks == page.blocks)
}

@Test func vaultEditsPreserveUnloadedTextAndRejectStaleDrafts() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeWorkspaceFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "", characterName: "", source: .init(appName: "Sillies")))
  let text =
    String(repeating: "A long set of notes.\n", count: 6_000) + "Keep this final paragraph."
  try database.createDocument(
    record: record, metadata: .init(kind: .note, title: "My note", modifiedAt: Date()), notes: text)
  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  let first = try database.sectionPage(location)
  let block = try #require(first.blocks.first)
  let replacement = "A revised beginning.\n"
  let revision = try database.editText(
    .init(
      location: location, expectedRevision: block.revision, text: replacement,
      region: .blocks(0..<1)), at: Date())
  let expected = replacement + String(text.dropFirst(block.text.count))
  #expect(try database.sectionText(location) == expected)
  #expect(throws: VaultEditingError.revisionConflict) {
    try database.editText(
      .init(location: location, expectedRevision: block.revision, text: "stale"), at: Date())
  }
  #expect(try database.sectionRevision(location) == revision)
  let reopened = try VaultDatabase(reading: directory)
  #expect(try reopened.sectionPage(location).blocks.first?.text == replacement)
  #expect(try reopened.sectionText(location).hasSuffix("Keep this final paragraph."))
}

@Test func vaultSearchFindsNotesAndCorrectionsAndOmitsTrash() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeWorkspaceFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Zoom")),
    content: .init(text: .init(transcript: "The original incorrect amount is twenty.")))
  try database.commit(.init(records: [.insert(record)]))
  let location = VaultBlockLocation(recordID: record.id, section: .transcript)
  let revision = try database.sectionRevision(location)
  try database.editText(
    .init(location: location, expectedRevision: revision, text: "The corrected amount is thirty."),
    at: Date())
  let found = try database.workspacePage(.init(text: "thirty"))
  #expect(found.records.map(\.id) == [record.id])
  #expect(found.records.first?.match?.section == .transcript)
  #expect(try database.workspacePage(.init(text: "twenty")).records.isEmpty)
  #expect(
    try database.sectionText(.init(recordID: record.id, section: .originalTranscript)).contains(
      "twenty"))
  try database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  #expect(try database.workspacePage(.init(text: "thirty")).records.isEmpty)
  #expect(try database.workspacePage(.init(scope: .trash)).records.map(\.id) == [record.id])
  try database.editDocument(id: record.id, edit: .restore, at: Date())
  #expect(try database.workspacePage(.init(text: "thirty")).records.map(\.id) == [record.id])
}
