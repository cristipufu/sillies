import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultNotesRejectChangedPersonalNotesAndTranscriptButPreserveUnrelatedEdits() throws {
  let fixture = try NotesRevisionFixture()
  defer { fixture.remove() }
  let database = fixture.database
  let id = fixture.record.id
  let first = try #require(try database.notesInput(id: id))
  #expect(first.personalNotes == "Agenda: launch and pricing.")
  try fixture.replace(.notes, with: "Focus on the new deadline.")
  var applied = false
  #expect(
    try database.editNotes(id: id, revision: first.revision) { _ in
      applied = true
      return true
    } == false)
  #expect(!applied)
  let second = try #require(try database.notesInput(id: id))
  try fixture.replace(.transcript, with: "The corrected deadline is Thursday.")
  #expect(
    try database.editNotes(id: id, revision: second.revision) { _ in
      applied = true
      return true
    } == false)
  #expect(!applied)
  let current = try #require(try database.notesInput(id: id))
  #expect(current.record.transcript == "The corrected deadline is Thursday.")
  #expect(current.personalNotes == "Focus on the new deadline.")
  try database.setProtection(.protected, for: id)
  try database.editDocument(id: id, edit: .tags(["Review"]), at: Date())
  #expect(
    try database.editNotes(id: id, revision: current.revision) { record in
      record.summary = "Launch\n• The corrected deadline is Thursday."
      record.summaryPending = false
      return true
    })
  let saved = try #require(try database.record(id: id))
  #expect(saved.isProtected)
  #expect(saved.summary.contains("Thursday"))
  #expect(saved.transcript == current.record.transcript)
  #expect(saved.originalSpeakerTranscript == fixture.record.transcript)
  #expect(try database.authoredNotes(recordID: id) == current.personalNotes)
  #expect(try database.documentHeader(id: id)?.metadata.tags == ["Review"])
  #expect(try database.search(.init(query: "Thursday")).first?.header.id == id)
}

@Test func vaultNotesRefuseTrashedOrDeletedInputsAndRollBackFailedCompletion() throws {
  let fixture = try NotesRevisionFixture()
  defer { fixture.remove() }
  let database = fixture.database
  let id = fixture.record.id
  let input = try #require(try database.notesInput(id: id))
  try database.sql.execute(
    """
    CREATE TRIGGER reject_notes_completion BEFORE UPDATE ON content_sections
    WHEN NEW.section='summary' BEGIN SELECT RAISE(ABORT,'injected notes write failure'); END
    """)
  #expect(throws: (any Error).self) {
    try database.editNotes(id: id, revision: input.revision) { record in
      record.summary = "An incomplete write"
      return true
    }
  }
  #expect(try database.record(id: id)?.summary == fixture.record.summary)
  #expect(try database.notesInput(id: id)?.revision == input.revision)
  #expect(try database.search(.init(query: "incomplete")).isEmpty)
  try database.sql.execute("DROP TRIGGER reject_notes_completion")
  #expect(
    try database.editNotes(id: id, revision: input.revision) { record in
      record.summary = "Recovered generated notes"
      return true
    })
  try database.editDocument(id: id, edit: .moveToTrash, at: Date())
  #expect(try database.notesInput(id: id) == nil)
  #expect(
    try database.editNotes(id: id, revision: input.revision) { _ in
      Issue.record("Trashed source was edited")
      return true
    } == false)
  try database.editDocument(id: id, edit: .restore, at: Date())
  try database.commit(.init(deletion: .records([id])))
  #expect(
    try database.editNotes(id: id, revision: input.revision) { _ in
      Issue.record("Deleted source was recreated")
      return true
    } == false)
  #expect(try database.record(id: id) == nil)
}

private struct NotesRevisionFixture {
  let directory: URL
  let database: VaultDatabase
  let record: SessionRecord
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    database = try VaultDatabase(directory: directory)
    record = SessionRecord(
      kind: .listen,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
      content: .init(
        text: .init(transcript: "The original deadline is Tuesday."),
        notes: .init(summary: "Earlier notes"), processing: .init(summaryPending: true)))
    _ = try database.createDocument(
      record: record,
      metadata: .init(kind: .capture, title: "Planning", modifiedAt: Date()),
      notes: "Agenda: launch and pricing.")
  }
  func replace(_ section: VaultDocumentSection, with text: String) throws {
    let location = VaultBlockLocation(recordID: record.id, section: section)
    try database.editText(
      .init(
        location: location,
        expectedRevision: database.sectionRevision(location), text: text), at: Date())
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}
