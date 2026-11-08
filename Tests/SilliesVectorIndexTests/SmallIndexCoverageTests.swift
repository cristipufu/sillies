import Foundation
import Testing

@testable import SilliesPersistence
@testable import SilliesVectorIndex

/// After deletion or distribution changes, a small disk index can retain many trained partitions.
/// A nearest passage must not disappear merely because its old centroid is far from the query.
@Test func smallPartitionedIndexIncludesOffCentroidCandidatesAfterReopening() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let dimensions = 128
  let samplesPerPartition = 40
  let axes = (0..<dimensions).map { axis in
    (0..<dimensions).map { $0 == axis ? Float(1) : Float(0) }
  }
  let trainingCount = dimensions * samplesPerPartition
  let training = VaultVectorBatch(
    ids: (1...trainingCount).map(Int64.init),
    values: (0..<trainingCount).flatMap { axes[$0 % dimensions] })
  let index = try NativeVectorIndex(
    dimensions: dimensions, partitions: dimensions, training: training,
    backing: directory.appendingPathComponent("vectors.ivf"))
  var outlier = Array(repeating: Float(-1), count: dimensions)
  outlier[0] = -0.1
  let norm = sqrt(outlier.reduce(0) { $0 + $1 * $1 })
  outlier = outlier.map { $0 / norm }
  let identities = (1...dimensions + 1).map(Int64.init)
  try index.add(.init(ids: identities, values: axes.flatMap { $0 } + outlier))
  let query = axes[0].map { -$0 }
  #expect(Set(try index.search(query, limit: 256)) == Set(identities))

  let checkpoint = directory.appendingPathComponent("vectors.index")
  try index.checkpoint(to: checkpoint)
  let reopened = try NativeVectorIndex(opening: checkpoint, dimensions: dimensions)
  #expect(Set(try reopened.search(query, limit: 256)) == Set(identities))
  try reopened.remove([Int64(dimensions + 1)])
  #expect(Set(try reopened.search(query, limit: 256)) == Set(identities.dropLast()))
}
