import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func protectionEditsTouchMetadataWithoutReadingOrReindexingTheBody() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  record.transcript = String(repeating: "Long recording. ", count: 10_000)
  try database.commit(.init(records: [.insert(record)]))
  let before = database.metrics
  let passages = try database.vaultIndexProgress(provider: "fixture").total
  #expect(try database.setProtection(.protected, for: record.id))
  #expect(database.metrics.loadedBodies == before.loadedBodies)
  #expect(database.metrics.writtenBodies == before.writtenBodies)
  #expect(database.metrics.indexedSections == before.indexedSections)
  #expect(try database.vaultIndexProgress(provider: "fixture").total == passages)
  #expect(try database.documentHeader(id: record.id)?.source.isProtected == true)
  #expect(try database.eligibleRetentionCount() == 0)
  let reopened = try VaultDatabase(directory: directory)
  var current = try #require(try reopened.record(id: record.id))
  #expect(current.isProtected)
  current.summary = "Updated summary"
  try reopened.commit(.init(records: [.update(current)]))
  #expect(try reopened.record(id: record.id)?.isProtected == true)
  #expect(try reopened.setProtection(.unprotected, for: record.id))
  #expect(try reopened.eligibleRetentionCount() == 1)
  #expect(try reopened.record(id: record.id)?.isProtected == false)
  #expect(try !reopened.setProtection(.protected, for: UUID()))
}
