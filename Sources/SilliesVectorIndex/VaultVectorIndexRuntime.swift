import Foundation
import SilliesCore
import SilliesPersistence

/// Each call does one bounded maintenance slice. Queries never train or rebuild an index.
package actor VaultVectorIndexRuntime {
  private static let maximumExactVectors = 8_192
  private static let exactMemoryBytes = 32 * 1_024 * 1_024
  private static let vectorsPerPartition = 64
  private static let maximumPartitions = 256
  private static let retrainingGrowth = 4
  private struct OpenIndex {
    let directory: URL
    let space: String
    let files: VectorIndexFiles
    let index: NativeVectorIndex
    var checkpoint: VectorIndexCheckpoint
  }
  private var reader: VaultVectorIndexDatabase?
  private var sourceDirectory: URL?
  private var current: OpenIndex?

  package init() {}

  package func advance(directory: URL, provider: String) throws -> Bool {
    let database = try storage(directory)
    let snapshots = try database.snapshots(provider: provider)
    let activeNames = Set(
      snapshots.map {
        VectorIndexFiles(vault: directory, provider: provider, space: $0.space).directory
          .lastPathComponent
      })
    if let current, !activeNames.contains(current.directory.lastPathComponent) {
      self.current = nil
    }
    if try VectorIndexFiles.removeObsolete(in: directory, preserving: activeNames) { return true }
    for snapshot in snapshots {
      try Task.checkCancellation()
      let files = VectorIndexFiles(vault: directory, provider: provider, space: snapshot.space)
      let stored = try files.read()
      if let stored, stored.accepts(snapshot), !needsTraining(stored, snapshot: snapshot),
        stored.isComplete, stored.changeSequence >= snapshot.latestChange
      {
        continue
      }
      try openForMaintenance(
        snapshot, directory: directory, provider: provider, files: files, stored: stored)
      guard var state = current else { throw SearchEmbeddingError.unavailable }
      try state.files.beginWrite()
      if !state.checkpoint.isComplete {
        let batch = try database.vectors(
          provider: provider, snapshot: snapshotForBuild(snapshot, checkpoint: state.checkpoint),
          after: state.checkpoint.lastID)
        try state.index.add(batch)
        if let last = batch.ids.last { state.checkpoint.lastID = last }
        if batch.ids.count < VaultVectorIndexDatabase.batchSize {
          state.checkpoint.isComplete = true
        }
      } else {
        let changes = try database.changes(
          provider: provider, snapshot: snapshot, after: state.checkpoint.changeSequence)
        try state.index.remove(changes.removed)
        try state.index.add(changes.inserted)
        state.checkpoint.changeSequence =
          changes.removed.isEmpty ? snapshot.latestChange : changes.through
      }
      try state.files.publish(state.checkpoint, index: state.index)
      current = state
      return true
    }
    return false
  }

  package func search(_ query: VaultVectorQuery, provider: String) throws -> [Int64]? {
    let database = try storage(query.directory)
    guard
      let snapshot = try database.snapshots(provider: provider).first(where: {
        $0.space == query.embedding.space
      }),
      snapshot.dimensions == query.embedding.values.count
    else { return nil }
    let files = VectorIndexFiles(vault: query.directory, provider: provider, space: snapshot.space)
    guard let checkpoint = try files.read(), checkpoint.accepts(snapshot), checkpoint.isComplete
    else { return nil }
    if current?.directory != files.directory || current?.checkpoint != checkpoint {
      current = nil
      current = .init(
        directory: files.directory, space: snapshot.space, files: files,
        index: try files.openIndex(dimensions: snapshot.dimensions), checkpoint: checkpoint)
    }
    return try current?.index.search(query.embedding.values, limit: query.limit)
  }

  private func openForMaintenance(
    _ snapshot: VaultVectorIndexSnapshot, directory: URL, provider: String,
    files: VectorIndexFiles, stored: VectorIndexCheckpoint?
  ) throws {
    if let stored, stored.accepts(snapshot), !needsTraining(stored, snapshot: snapshot) {
      if current?.directory == files.directory, current?.checkpoint == stored { return }
      current = nil
      current = .init(
        directory: files.directory, space: snapshot.space, files: files,
        index: try files.openIndex(dimensions: snapshot.dimensions), checkpoint: stored)
      return
    }
    current = nil
    try files.reset()
    let sample = try storage(directory).training(provider: provider, snapshot: snapshot)
    let partitions =
      snapshot.count <= exactLimit(dimensions: snapshot.dimensions)
      ? 0
      : min(Self.maximumPartitions, sample.ids.count / Self.vectorsPerPartition)
    let index = try NativeVectorIndex(
      dimensions: snapshot.dimensions, partitions: partitions,
      training: sample, backing: files.backing)
    current = .init(
      directory: files.directory, space: snapshot.space, files: files,
      index: index, checkpoint: .init(snapshot: snapshot, partitions: partitions))
  }

  private func needsTraining(
    _ checkpoint: VectorIndexCheckpoint, snapshot: VaultVectorIndexSnapshot
  ) -> Bool {
    guard checkpoint.isComplete else { return false }
    if checkpoint.partitions == 0 {
      return snapshot.count > exactLimit(dimensions: snapshot.dimensions)
        && snapshot.count > checkpoint.trainedCount
    }
    return snapshot.count / Self.retrainingGrowth > checkpoint.trainedCount
  }
  private func exactLimit(dimensions: Int) -> Int {
    min(Self.maximumExactVectors, Self.exactMemoryBytes / (dimensions * MemoryLayout<Float>.size))
  }
  private func storage(_ directory: URL) throws -> VaultVectorIndexDatabase {
    if sourceDirectory != directory {
      current = nil
      reader = try VaultVectorIndexDatabase(directory: directory)
      sourceDirectory = directory
    }
    guard let reader else { throw SearchEmbeddingError.unavailable }
    return reader
  }
  private func snapshotForBuild(
    _ snapshot: VaultVectorIndexSnapshot, checkpoint: VectorIndexCheckpoint
  ) -> VaultVectorIndexSnapshot {
    snapshot.bounded(through: checkpoint.baseMaximumID)
  }
}
