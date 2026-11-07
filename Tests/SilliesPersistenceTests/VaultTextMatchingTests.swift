import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func phraseAndLiteralSearchCrossBlockBoundariesAndInvalidateAfterRangeEdits() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  let padding = String(repeating: " ", count: VaultTextBlocks.maximumScalars - 4)
  _ = try database.createDocument(
    record: record, metadata: .init(kind: .note, title: "Boundary", modifiedAt: Date()),
    notes: padding + "deep blue sea")
  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  #expect(try database.sectionPage(location).blocks.count == 2)
  for mode in [VaultTextMatching.phrase, .literal] {
    var query = VaultWorkspaceQuery(text: "deep blue")
    query.textMatching = mode
    #expect(try database.workspacePage(query).records.map(\.id) == [record.id])
  }
  _ = try database.editText(
    .init(
      location: location, expectedRevision: database.sectionRevision(location),
      text: padding + "new!", region: .blocks(0..<1)), at: Date())
  var query = VaultWorkspaceQuery(text: "deep blue")
  query.textMatching = .literal
  #expect(try database.workspacePage(query).records.isEmpty)
  query.text = "new! blue"
  #expect(try database.workspacePage(query).records.map(\.id) == [record.id])
  _ = try database.editText(
    .init(
      location: location, expectedRevision: database.sectionRevision(location), text: "",
      region: .blocks(0..<1)), at: Date())
  #expect(try database.workspacePage(query).records.isEmpty)
  for table in ["content_search", "content_substrings"] {
    try database.sql.execute("INSERT INTO \(table)(\(table),rank) VALUES('integrity-check',1)")
  }
}

@Test func vaultExactTextSearchFindsCodeURLsAndNonLatinSubstringsAndTracksEdits() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  _ = try database.createDocument(
    record: record, metadata: .init(kind: .note, title: "Search fixture", modifiedAt: Date()),
    notes:
      "didSave_workspace_id https://example.com/a-b?x=1 \"quoted\"\n今天开会讨论项目\nتخطيط المشروع\nÎnvățăm împreună"
  )
  for text in ["ave_work", "com/a-b?x=1", "\"quoted\"", "开会讨论", "مشروع"] {
    var query = VaultWorkspaceQuery(text: text, ordering: .relevance)
    query.textMatching = .literal
    #expect(try database.workspacePage(query).records.map(\.id) == [record.id])
    #expect(try database.matchingPassages(recordID: record.id, query: query).count == 1)
  }
  var phrase = VaultWorkspaceQuery(text: "invatam impreuna", ordering: .relevance)
  phrase.textMatching = .phrase
  #expect(try database.workspacePage(phrase).records.map(\.id) == [record.id])
  phrase.text = "impreuna invatam"
  #expect(try database.workspacePage(phrase).records.isEmpty)
  var short = VaultWorkspaceQuery(text: "ab")
  short.textMatching = .literal
  #expect(throws: VaultEditingError.self) { try database.workspacePage(short) }
  var injection = VaultWorkspaceQuery(text: "\" OR * --")
  injection.textMatching = .literal
  #expect(try database.workspacePage(injection).records.isEmpty)
  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  _ = try database.editText(
    .init(
      location: location, expectedRevision: database.sectionRevision(location),
      text: "Changed notes"), at: Date())
  phrase.text = "invatam impreuna"
  #expect(try database.workspacePage(phrase).records.isEmpty)
  var deleted = VaultWorkspaceQuery(text: "anged")
  deleted.textMatching = .literal
  #expect(try database.workspacePage(deleted).records.map(\.id) == [record.id])
  try database.commit(.init(deletion: .records([record.id])))
  #expect(try database.workspacePage(deleted).records.isEmpty)
}
