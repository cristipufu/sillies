import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultSourceFiltersAndFacetCountsFollowUpdatesAndDeletion() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var first = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Teams")),
    content: .init(text: .init(transcript: "A searchable decision")))
  first.languageIdentifier = "fr"
  let other = SessionRecord(
    kind: .record,
    origin: .init(characterID: "bolt", characterName: "Bolt", source: .init(appName: "Zoom")),
    content: .init(text: .init(transcript: "Another searchable decision")))
  try database.commit(.init(records: [.insert(first), .insert(other)]))
  var query = VaultWorkspaceQuery(text: "decision", ordering: .relevance)
  query.source = .init(appName: "Teams", companionID: "pogo", languageIdentifier: "fr")
  #expect(try database.workspacePage(query).records.map(\.id) == [first.id])
  query.source?.languageIdentifier = "en"
  #expect(try database.workspacePage(query).records.isEmpty)
  #expect(try database.sourceFacets(.app, matching: "team").map(\.id) == ["Teams"])
  #expect(try database.sourceFacets(.companion, matching: "Pogo").map(\.id) == ["pogo"])
  first.isProtected = true
  first.languageIdentifier = "en"
  try database.commit(.init(records: [.update(first)]))
  #expect(try database.workspacePage(query).records.map(\.id) == [first.id])
  #expect(try database.sourceFacets(.language, matching: "").map(\.id) == ["en"])
  #expect(try database.sql.integer("SELECT sum(total) FROM source_facets WHERE kind='app'") == 2)
  try database.commit(.init(deletion: .records([first.id])))
  #expect(try database.sourceFacets(.app, matching: "").map(\.id) == ["Zoom"])
  #expect(try database.sourceFacets(.language, matching: "").isEmpty)
  #expect(database.metrics.loadedBodies == 0)
}

@Test func vaultSourceLanguageFacetAppearsWhenAnOlderHeaderIsPrepared() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  record.languageIdentifier = "ja"
  try database.commit(.init(records: [.insert(record)]))
  try database.sql.execute(
    "UPDATE records SET header=json_remove(CAST(header AS TEXT),'$.languageIdentifier')")
  try database.sql.execute("INSERT INTO content_backfill SELECT sequence,id FROM records")
  #expect(try database.sourceFacets(.language, matching: "").isEmpty)
  #expect(try database.prepareNextContent())
  #expect(try database.sourceFacets(.language, matching: "").map(\.id) == ["ja"])
}
