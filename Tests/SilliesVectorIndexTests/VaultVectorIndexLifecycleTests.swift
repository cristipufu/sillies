import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@testable import SilliesVectorIndex

@Test func nativeVaultIndexSurvivesRestartAndRejectsDeletedEvidence() async throws {
  let fixture = try VectorFixture()
  defer { fixture.remove() }
  let record = try fixture.add("amber bicycle")
  try fixture.embedPending()
  let runtime = VaultVectorIndexRuntime()
  try await fixture.prepare(runtime)
  let query = fixture.query([1, 0])
  let ids = try #require(try await runtime.search(query, provider: VectorFixture.provider))
  let reader = try VaultSemanticSearchDatabase(directory: fixture.directory)
  #expect(
    try reader.search(
      .init(query: "commute"), embedding: query.embedding,
      provider: VectorFixture.provider, candidates: ids
    ).map(\.header.id) == [record.id])
  let reopened = VaultVectorIndexRuntime()
  #expect(try await reopened.search(query, provider: VectorFixture.provider) == ids)

  try fixture.database.commit(.init(deletion: .records([record.id])))
  #expect(
    try reader.search(
      .init(query: "commute"), embedding: query.embedding,
      provider: VectorFixture.provider, candidates: ids
    ).isEmpty)
  #expect(try await reopened.search(query, provider: VectorFixture.provider) == nil)
  let files = VectorIndexFiles(
    vault: fixture.directory, provider: VectorFixture.provider, space: VectorFixture.space)
  try await fixture.prepare(reopened)
  #expect(!FileManager.default.fileExists(atPath: files.directory.path))
}

@Test func nativeVaultIndexAppliesCorrectionsAndProviderResets() async throws {
  let fixture = try VectorFixture()
  defer { fixture.remove() }
  let record = try fixture.add("amber bicycle")
  try fixture.embedPending()
  let runtime = VaultVectorIndexRuntime()
  try await fixture.prepare(runtime)
  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  try fixture.database.editText(
    .init(
      location: location,
      expectedRevision: fixture.database.sectionRevision(location), text: "blue train"), at: Date())
  try fixture.embedPending()
  try await fixture.prepare(runtime)
  let query = fixture.query([0, 1])
  let ids = try #require(try await runtime.search(query, provider: VectorFixture.provider))
  let reader = try VaultSemanticSearchDatabase(directory: fixture.directory)
  let matches = try reader.search(
    .init(query: "journey"), embedding: query.embedding,
    provider: VectorFixture.provider, candidates: ids)
  #expect(matches.first?.excerpt == "blue train")
  try fixture.database.resetVaultEmbeddings(provider: VectorFixture.provider)
  try fixture.embedPending()
  #expect(try await runtime.search(query, provider: VectorFixture.provider) == nil)
  try await fixture.prepare(runtime)
  #expect(try await runtime.search(query, provider: VectorFixture.provider)?.isEmpty == false)
}

@Test func interruptedNativeIndexWriteRebuildsFromAuthoritativeVectors() async throws {
  let fixture = try VectorFixture()
  defer { fixture.remove() }
  _ = try fixture.add("amber bicycle")
  try fixture.embedPending()
  let runtime = VaultVectorIndexRuntime()
  try await fixture.prepare(runtime)
  let files = VectorIndexFiles(
    vault: fixture.directory, provider: VectorFixture.provider, space: VectorFixture.space)
  try files.beginWrite()
  let reopened = VaultVectorIndexRuntime()
  #expect(
    try await reopened.search(fixture.query([1, 0]), provider: VectorFixture.provider) == nil)
  try await fixture.prepare(reopened)
  #expect(
    try await reopened.search(fixture.query([1, 0]), provider: VectorFixture.provider)?.count == 1)
}

private struct VectorFixture {
  static let provider = "fixture-v1"
  static let space = "fixture-2d"
  let directory: URL
  let database: VaultDatabase
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    database = try VaultDatabase(directory: directory)
  }
  func add(_ text: String) throws -> SessionRecord {
    let record = SessionRecord(
      kind: .stash,
      origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
    _ = try database.createDocument(
      record: record,
      metadata: .init(kind: .note, title: "Test note", modifiedAt: Date()), notes: text)
    return record
  }
  func embedPending() throws {
    while let passage = try database.pendingPassage() { try database.savePassage(passage) }
    while let item = try database.pendingVaultEmbedding(provider: Self.provider) {
      let values: [Float]? =
        item.text.contains("amber") ? [1, 0] : item.text.contains("blue") ? [0, 1] : nil
      let embedding = try values.map { try SearchEmbedding(space: Self.space, values: $0) }
      try database.saveVaultEmbedding(embedding, for: item, provider: Self.provider)
    }
  }
  func prepare(_ runtime: VaultVectorIndexRuntime) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while try await runtime.advance(directory: directory, provider: Self.provider) {
      guard ContinuousClock.now < deadline else { throw CocoaError(.executableRuntimeMismatch) }
    }
  }
  func query(_ values: [Float]) -> VaultVectorQuery {
    // Fixture vectors are finite unit axes.
    .init(directory: directory, embedding: try! .init(space: Self.space, values: values), limit: 10)
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}

@Test func nativeVaultIndexRebuildsAnOversizedManifestWithoutTrustingIt() async throws {
  let fixture = try VectorFixture()
  defer { fixture.remove() }
  _ = try fixture.add("amber bicycle")
  try fixture.embedPending()
  let runtime = VaultVectorIndexRuntime()
  try await fixture.prepare(runtime)
  let files = VectorIndexFiles(
    vault: fixture.directory, provider: VectorFixture.provider, space: VectorFixture.space)
  try Data(repeating: 32, count: 20_000).write(
    to: files.directory.appendingPathComponent("checkpoint.json"))
  #expect(try files.read() == nil)
  try await fixture.prepare(runtime)
  #expect(
    try await runtime.search(fixture.query([1, 0]), provider: VectorFixture.provider)?.count == 1)
}
