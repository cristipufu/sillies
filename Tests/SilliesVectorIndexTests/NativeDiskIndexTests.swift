import Foundation
import Testing

@testable import SilliesPersistence
@testable import SilliesVectorIndex

@Test func nativeDiskIndexSearchesAfterCheckpointAndRemovesRetiredVectors() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let dimensions = 16
  let vectors = (1...10_000).map { sampleVector($0, dimensions: dimensions) }
  let training = VaultVectorBatch(
    ids: (1...512).map(Int64.init), values: vectors.prefix(512).flatMap { $0 })
  let index = try NativeVectorIndex(
    dimensions: dimensions, partitions: 8, training: training,
    backing: directory.appendingPathComponent("vectors.ivf"))
  for start in stride(from: 0, to: vectors.count, by: 500) {
    let end = min(start + 500, vectors.count)
    try index.add(
      .init(ids: ((start + 1)...end).map(Int64.init), values: vectors[start..<end].flatMap { $0 }))
  }
  let target: Int64 = 42
  #expect(try index.search(vectors[Int(target) - 1], limit: 10).contains(target))
  let checkpoint = directory.appendingPathComponent("vectors.index")
  try index.checkpoint(to: checkpoint)
  let reopened = try NativeVectorIndex(opening: checkpoint, dimensions: dimensions)
  #expect(try reopened.search(vectors[Int(target) - 1], limit: 10).contains(target))
  try reopened.remove([target])
  #expect(try reopened.search(vectors[Int(target) - 1], limit: 10).contains(target) == false)
  try reopened.checkpoint(to: checkpoint)
  let final = try NativeVectorIndex(opening: checkpoint, dimensions: dimensions)
  #expect(try final.search(vectors[Int(target) - 1], limit: 10).contains(target) == false)
}

private func sampleVector(_ index: Int, dimensions: Int) -> [Float] {
  let values = (0..<dimensions).map { Float(sin(Double(index * ($0 + 1)) * 0.731)) }
  let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
  return values.map { $0 / norm }
}
