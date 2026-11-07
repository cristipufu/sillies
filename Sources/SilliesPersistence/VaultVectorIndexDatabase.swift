import Foundation
import SilliesCore

/// Cancellable, bounded input to the isolated native index. SQLite remains the source of truth.
public final class VaultVectorIndexDatabase {
  private static let maximumSpaces = 64
  public static let batchSize = 512
  public static let trainingSize = 16_384
  private static let trainingBytes = 32 * 1_024 * 1_024
  private let sql: VaultSQLConnection

  public init(directory: URL) throws {
    guard directory.isFileURL else { throw CocoaError(.fileReadInvalidFileName) }
    sql = try VaultSQLConnection(
      url: directory.appendingPathComponent(VaultDatabase.filename), access: .readOnly)
  }

  public func snapshots(provider: String) throws -> [VaultVectorIndexSnapshot] {
    try sql.cancellableRead {
      var result: [VaultVectorIndexSnapshot] = []
      let latest = try sql.integer("SELECT coalesce(max(sequence),0) FROM vector_changes")
      let earliest = try sql.integer("SELECT coalesce(min(sequence),0) FROM vector_changes")
      try sql.rows(
        """
        SELECT s.space,c.epoch,s.dimensions,s.total,
          coalesce((SELECT max(passage_id) FROM passage_vectors WHERE provider=s.provider AND space=s.space),0)
        FROM embedding_spaces s JOIN embedding_cursors c ON c.provider=s.provider
        WHERE s.provider=? AND s.space!='' AND s.total>0 ORDER BY s.space LIMIT ?
        """, [.text(provider), .integer(Int64(Self.maximumSpaces))]
      ) { row in
        guard let dimensions = Int(try VaultSQLConnection.text(row, column: 2)),
          (1...SearchEmbedding.maximumDimensions).contains(dimensions),
          let count = Int(try VaultSQLConnection.text(row, column: 3)), count > 0,
          let maximumID = Int64(try VaultSQLConnection.text(row, column: 4)), maximumID > 0
        else {
          throw CocoaError(.fileReadCorruptFile)
        }
        result.append(
          .init(
            space: try VaultSQLConnection.text(row),
            epoch: try VaultSQLConnection.text(row, column: 1),
            dimensions: dimensions, count: count, maximumID: maximumID,
            latestChange: Int64(latest), earliestChange: Int64(earliest)))
      }
      return result
    }
  }

  public func vectors(provider: String, snapshot: VaultVectorIndexSnapshot, after id: Int64) throws
    -> VaultVectorBatch
  {
    try sql.cancellableRead {
      var ids: [Int64] = []
      var values: [Float] = []
      try sql.rows(
        """
        SELECT passage_id,vector FROM passage_vectors WHERE provider=? AND space=? AND passage_id>? AND passage_id<=?
        ORDER BY passage_id LIMIT ?
        """,
        [
          .text(provider), .text(snapshot.space), .integer(id), .integer(snapshot.maximumID),
          .integer(Int64(Self.batchSize)),
        ]
      ) { row in
        guard let id = Int64(try VaultSQLConnection.text(row)), id > 0 else {
          throw CocoaError(.fileReadCorruptFile)
        }
        ids.append(id)
        values += try Self.decode(
          VaultSQLConnection.data(row, column: 1, maximumBytes: SearchVectorStorage.maximumBytes),
          dimensions: snapshot.dimensions)
      }
      return .init(ids: ids, values: values)
    }
  }

  public func training(provider: String, snapshot: VaultVectorIndexSnapshot) throws
    -> VaultVectorBatch
  {
    try sql.cancellableRead {
      let count = min(
        Self.trainingSize, snapshot.count,
        Self.trainingBytes / (snapshot.dimensions * MemoryLayout<Float>.size))
      let step = max(1, snapshot.maximumID / Int64(count))
      var ids: [Int64] = []
      var seen: Set<Int64> = []
      var values: [Float] = []
      values.reserveCapacity(count * snapshot.dimensions)
      for index in 0..<count {
        try Task.checkCancellation()
        try sql.rows(
          "SELECT passage_id,vector FROM passage_vectors WHERE provider=? AND space=? AND passage_id>=? ORDER BY passage_id LIMIT 1",
          [.text(provider), .text(snapshot.space), .integer(1 + Int64(index) * step)]
        ) { row in
          guard let id = Int64(try VaultSQLConnection.text(row)), id > 0 else {
            throw CocoaError(.fileReadCorruptFile)
          }
          guard seen.insert(id).inserted else { return }
          ids.append(id)
          values += try Self.decode(
            VaultSQLConnection.data(row, column: 1, maximumBytes: SearchVectorStorage.maximumBytes),
            dimensions: snapshot.dimensions)
        }
      }
      // Large ID gaps can map many probes to the same row. Fill the sample with bounded
      // distinct rows so sparse archives never fall back to an unbounded exact index.
      if ids.count < count {
        try sql.rows(
          "SELECT passage_id,vector FROM passage_vectors WHERE provider=? AND space=? ORDER BY passage_id LIMIT ?",
          [.text(provider), .text(snapshot.space), .integer(Int64(count))]
        ) { row in
          guard ids.count < count else { return }
          guard let id = Int64(try VaultSQLConnection.text(row)), id > 0 else {
            throw CocoaError(.fileReadCorruptFile)
          }
          guard seen.insert(id).inserted else { return }
          ids.append(id)
          values += try Self.decode(
            VaultSQLConnection.data(row, column: 1, maximumBytes: SearchVectorStorage.maximumBytes),
            dimensions: snapshot.dimensions)
        }
      }
      return .init(ids: ids, values: values)
    }
  }

  public func changes(provider: String, snapshot: VaultVectorIndexSnapshot, after sequence: Int64)
    throws -> VaultVectorChanges
  {
    try sql.cancellableRead {
      var removed: Set<Int64> = []
      var inserted: [Int64: [Float]] = [:]
      var through = sequence
      try sql.rows(
        """
        SELECT c.sequence,c.passage_id,v.vector FROM vector_changes c
        LEFT JOIN passage_vectors v ON v.passage_id=c.passage_id AND v.provider=c.provider AND v.space=c.space
        WHERE c.provider=? AND c.space=? AND c.sequence>? ORDER BY c.sequence LIMIT ?
        """,
        [
          .text(provider), .text(snapshot.space), .integer(sequence),
          .integer(Int64(Self.batchSize)),
        ]
      ) { row in
        guard let next = Int64(try VaultSQLConnection.text(row)),
          let id = Int64(try VaultSQLConnection.text(row, column: 1)), id > 0
        else {
          throw CocoaError(.fileReadCorruptFile)
        }
        through = next
        removed.insert(id)
        let data = try VaultSQLConnection.data(
          row, column: 2, maximumBytes: SearchVectorStorage.maximumBytes)
        if data.isEmpty {
          inserted.removeValue(forKey: id)
        } else {
          inserted[id] = try Self.decode(data, dimensions: snapshot.dimensions)
        }
      }
      let ordered = inserted.keys.sorted()
      return .init(
        removed: removed.sorted(),
        inserted: .init(ids: ordered, values: ordered.flatMap { inserted[$0] ?? [] }),
        through: through)
    }
  }

  private static func decode(_ data: Data, dimensions: Int) throws -> [Float] {
    guard data.count == dimensions * MemoryLayout<UInt32>.size else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return try data.withUnsafeBytes { bytes in
      try (0..<dimensions).map { index in
        let value = Float(
          bitPattern: UInt32(
            littleEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
        guard value.isFinite else { throw CocoaError(.fileReadCorruptFile) }
        return value
      }
    }
  }
}
