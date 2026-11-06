import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

/// Optional release measurements use synthetic vectors and an independent scalar oracle.
/// Setup is outside the timer; every query still reads the production SQLite index.
@Test(
  .enabled(if: ProcessInfo.processInfo.environment["SILLIES_MEMORY_SCALE_CHECK"] == "1"),
  arguments: [1_000, 10_000, 100_000])
func memoryVectorRankingMatchesScalarOracleAtScale(_ count: Int) async throws {
  let fixture = try MemoryVectorScaleFixture(count: count)
  defer { fixture.remove() }
  let reader = try ConversationSearchDatabase(directory: fixture.directory)
  let scanStarted = ContinuousClock.now
  var scannedBytes = 0
  try reader.sql.rows(
    """
    SELECT id,vector FROM memory_embeddings WHERE owner=? AND provider=? AND space=?
    """,
    [
      .text(fixture.handle.companionID), .text(MemoryVectorScaleFixture.provider),
      .text(fixture.query.space),
    ]
  ) { row in
    scannedBytes += try VaultSQLConnection.withBlob(
      row, column: 1, maximumBytes: SearchVectorStorage.maximumBytes
    ) { $0.count }
  }
  print("VECTOR SCAN count=\(count) bytes=\(scannedBytes) query=\(scanStarted.duration(to: .now))")
  for repetition in 0..<3 {
    let started = ContinuousClock.now
    let matches = try reader.semanticMemories(
      .init(handle: fixture.handle, text: "synthetic query"),
      embedding: fixture.query, provider: MemoryVectorScaleFixture.provider)
    let elapsed = started.duration(to: .now)
    #expect(matches.map(\.key) == fixture.expected)
    print("VECTOR SCALE count=\(count) repetition=\(repetition) query=\(elapsed)")
  }
}

private struct MemoryVectorScaleFixture {
  static let provider = "synthetic-scale"
  private static let dimensions = 384
  private static let resultCount = 4
  let directory: URL
  let handle: ConversationHandle
  let query: SearchEmbedding
  let expected: [String]

  init(count: Int) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let database = try ConversationDatabase(directory: directory)
    handle = try database.open(.init(id: "pogo", name: "Pogo")).handle
    var random = VectorRandom(seed: 0x718B_26F4)
    query = try SearchEmbedding(space: Self.provider, values: random.vector(Self.dimensions))
    let source = MemorySource(messageID: UUID(), quote: "Synthetic measurement fixture.")
    var best: [(key: String, score: Double)] = []
    let owner = handle.companionID
    let queryValues = query.values
    // Bulk fixture insertion avoids measuring fsync and receipt maintenance as vector ranking.
    try database.sql.transaction {
      for index in 0..<count {
        let memory = CompanionMemory(
          replacing: nil, fact: .init(key: "fact_\(index)", value: "Synthetic fact \(index)"),
          source: source, savedAt: .distantPast)
        let vector = try SearchEmbedding(
          space: Self.provider, values: random.vector(Self.dimensions))
        try database.sql.execute(
          "INSERT INTO companion_memories(id,owner,key,updated,body) VALUES(?,?,?,0,?)",
          [
            .text(memory.id.uuidString), .text(owner), .text(memory.key),
            .data(try database.encoder.encode(memory)),
          ])
        try database.sql.execute(
          "INSERT INTO memory_embeddings(provider,id,owner,space,vector) VALUES(?,?,?,?,?)",
          [
            .text(Self.provider), .text(memory.id.uuidString), .text(owner), .text(Self.provider),
            .data(SearchVectorStorage.encode(vector.values)),
          ])
        // Deliberately independent of the production scoring and top-k implementations.
        var dot = 0.0
        var norm = 0.0
        for dimension in vector.values.indices {
          let value = Double(vector.values[dimension])
          dot += value * Double(queryValues[dimension])
          norm += value * value
        }
        best.append((memory.key, dot / sqrt(norm)))
        best.sort { $0.score > $1.score }
        if best.count > Self.resultCount { best.removeLast() }
      }
    }
    expected = best.map(\.key)
  }

  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}

private struct VectorRandom {
  var seed: UInt64
  mutating func vector(_ dimensions: Int) -> [Float] {
    (0..<dimensions).map { _ in
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max)
    }
  }
}
