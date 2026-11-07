import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func broadDateSearchPagesAllMatchesWithShuffledInsertionOrderAndEqualDates() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let count = 4_105
  let records = (0..<count).map { index in
    SessionRecord(
      kind: .snap,
      origin: .init(
        characterID: "pogo", characterName: "Pogo",
        source: .init(
          appName: index.isMultiple(of: 31) ? "Chosen app" : "Other app",
          windowTitle: "sharedmarker")),
      metadata: .init(createdAt: Date(timeIntervalSince1970: Double(((index * 47) % count) / 3))))
  }
  try database.commit(.init(records: records.map(VaultRecordWrite.insert)))
  let newest = records.sorted {
    $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt
  }
  for ordering in [VaultWorkspaceQuery.Ordering.newest, .oldest] {
    var query = VaultWorkspaceQuery(text: "sharedmarker", ordering: ordering)
    let expected = ordering == .newest ? newest : newest.reversed()
    #expect(try allDateResults(database, query: query) == expected.map(\.id))
    query.source = .init(appName: "Chosen app")
    #expect(
      try allDateResults(database, query: query)
        == expected.filter { $0.appName == "Chosen app" }.map(\.id))
  }
  let changed = records[0]
  try database.editDocument(id: changed.id, edit: .star, at: Date(timeIntervalSince1970: 1_000_000))
  #expect(
    try database.workspacePage(.init(text: "sharedmarker", ordering: .modified)).records.first?.id
      == changed.id)
  try database.editDocument(id: changed.id, edit: .moveToTrash, at: Date())
  let page = try database.workspacePage(.init(text: "sharedmarker", ordering: .modified))
  #expect(!page.records.contains { $0.id == changed.id })
  #expect(page.records.count == VaultWorkspacePage.maximumCount)
}

private func allDateResults(_ database: VaultDatabase, query: VaultWorkspaceQuery) throws -> [UUID]
{
  var cursor: VaultWorkspaceCursor?
  var result: [UUID] = []
  for _ in 0..<100 {
    let page = try database.workspacePage(query, after: cursor)
    #expect(page.records.allSatisfy { $0.excerpt.contains("sharedmarker") && $0.match != nil })
    result += page.records.map(\.id)
    guard let next = page.next else { return result }
    #expect(next != cursor)
    cursor = next
  }
  Issue.record("Search did not reach the end of the bounded fixture")
  return result
}
