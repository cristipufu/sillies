import Foundation
import SilliesCore
import Testing

@testable import SilliesVault

@Test func vaultDeletionDuringEmbeddingCannotPublishAnObsoleteResult() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
  let library = VaultLibrary(directory: directory)
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "We commute by bicycle")))
  _ = try await library.commit(.init(records: [.insert(record)]))
  let started = AsyncStream<Void>.makeStream()
  let resume = AsyncStream<Void>.makeStream()
  try await library.useSearchEmbeddings(
    .init(identity: "test") { input in
      if input.purpose == .passage {
        started.continuation.yield(())
        for await _ in resume.stream { break }
      }
      try Task.checkCancellation()
      return try .init(space: "test", values: [1, 0])
    })
  for await _ in started.stream { break }
  #expect(try await library.search(.init(query: "bicycle")).map(\.header.id) == [record.id])
  _ = try await library.commit(.init(deletion: .records([record.id])))
  resume.continuation.finish()
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while await library.indexTask != nil, ContinuousClock.now < deadline { await Task.yield() }
  #expect(await library.indexTask == nil)
  #expect(try await library.relatedMatches(.init(query: "commute")).isEmpty)
  #expect(try await library.searchIndexStatus().0?.searchable == 0)
  try await library.useSearchEmbeddings(nil)
  #expect(try await library.searchIndexStatus().0 == nil)
}

@Test func vaultSemanticFailurePreservesKeywordSearch() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
  let library = VaultLibrary(directory: directory)
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "bicycle commute")))
  _ = try await library.commit(.init(records: [.insert(record)]))
  try await library.useSearchEmbeddings(
    .init(identity: "failed") { _ in throw SearchEmbeddingError.unavailable })
  #expect(try await library.search(.init(query: "bicycle")).map(\.header.id) == [record.id])
  #expect(try await library.metrics().loadedBodies == 0)
  try await library.useSearchEmbeddings(nil)
}
