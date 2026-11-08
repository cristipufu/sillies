import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func workspaceExcerptSelectionRecoversAfterRollbackOnAReadOnlyArchive() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let writer = try VaultDatabase(directory: directory)
  let records = (0..<130).map { index in
    SessionRecord(
      kind: .record,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
      content: .init(text: .init(transcript: "Meeting receipt\(index) contains the decision.")))
  }
  try writer.commit(.init(records: records.map(VaultRecordWrite.insert)))
  let reader = try VaultDatabase(reading: directory)
  let query = VaultWorkspaceQuery(text: "meeting", ordering: .relevance)
  #expect(throws: CancellationError.self) {
    try reader.sql.readSnapshot {
      let page = try reader.rankedWorkspacePage(query, after: nil)
      #expect(page.records.count == 100)
      #expect(
        try reader.sql.integer("SELECT count(*) FROM temp.workspace_excerpt_selection") == 100)
      throw CancellationError()
    }
  }
  #expect(
    try reader.sql.integer(
      "SELECT count(*) FROM sqlite_temp_master WHERE name='workspace_excerpt_selection'") == 0)
  let first = try reader.workspacePage(query)
  let second = try reader.workspacePage(query, after: #require(first.next))
  #expect((first.records + second.records).allSatisfy { $0.excerpt.contains("receipt") })
  #expect(Set((first.records + second.records).map(\.id)) == Set(records.map(\.id)))
  #expect(try reader.sql.integer("SELECT count(*) FROM temp.workspace_excerpt_selection") == 30)
  #expect(reader.metrics.loadedBodies == 0)
}

@Test func workspaceSearchExcerptsKeepTheirOwnSourceAndTimestampAcrossPages() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let records = (0..<120).map { index in
    let text = "Meeting receipt\(index) contains the decision for this recording."
    var record = SessionRecord(
      kind: .record,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
      content: .init(text: .init(transcript: text)),
      metadata: .init(createdAt: Date(timeIntervalSince1970: Double(index))))
    record.transcriptSegments = [
      .init(
        sequence: 0, source: "microphone", start: Double(index), end: Double(index + 1), text: text)
    ]
    return record
  }
  try database.commit(.init(records: records.map(VaultRecordWrite.insert)))
  let expected = Dictionary(
    uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
  for ordering in [VaultWorkspaceQuery.Ordering.newest, .relevance] {
    let query = VaultWorkspaceQuery(text: "meet", ordering: ordering)
    let first = try database.workspacePage(query)
    let cursor = try #require(first.next)
    let second = try database.workspacePage(query, after: cursor)
    #expect(first.records.count == VaultWorkspacePage.maximumCount)
    #expect(second.records.count == 20)
    #expect(second.next == nil)
    let headers = first.records + second.records
    #expect(Set(headers.map(\.id)) == Set(expected.keys))
    for header in headers {
      let index = try #require(expected[header.id])
      #expect(header.excerpt.contains("receipt\(index) "))
      #expect(header.match == .init(recordID: header.id, section: .transcript))
      #expect(header.matchSeconds == Double(index))
    }
  }
  #expect(database.metrics.loadedBodies == 0)
}

@Test func workspaceReadSnapshotKeepsRevisionsTogetherAndReleasesAfterFailure() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let writer = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  try writer.commit(.init(records: [.insert(record)]))
  let reader = try VaultDatabase(reading: directory)
  try reader.sql.readSnapshot {
    let before = try reader.documentHeader(id: record.id)
    try writer.editDocument(id: record.id, edit: .rename("Updated title"), at: Date())
    #expect(try reader.documentHeader(id: record.id) == before)
  }
  #expect(try reader.documentHeader(id: record.id)?.title == "Updated title")
  #expect(throws: CancellationError.self) {
    try reader.sql.readSnapshot {
      _ = try reader.documentHeader(id: record.id)
      throw CancellationError()
    }
  }
  try writer.editDocument(id: record.id, edit: .rename("After cancellation"), at: Date())
  #expect(try reader.workspacePage(.init()).records.first?.title == "After cancellation")
}

@Test func workspaceDateCursorsPreserveSubsecondTies() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let date = Date(timeIntervalSince1970: 1_700_000_000.1234567)
  let records = (0..<120).map { _ in
    SessionRecord(
      kind: .stash,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
      metadata: .init(createdAt: date))
  }
  try database.commit(.init(records: records.map(VaultRecordWrite.insert)))
  for ordering in [VaultWorkspaceQuery.Ordering.newest, .oldest, .modified] {
    let query = VaultWorkspaceQuery(ordering: ordering)
    let first = try database.workspacePage(query)
    let cursor = try #require(first.next)
    let second = try database.workspacePage(query, after: cursor)
    #expect(first.records.count == 100)
    #expect(second.records.count == 20)
    #expect(Set((first.records + second.records).map(\.id)) == Set(records.map(\.id)))
    #expect(second.next == nil)
  }
}
