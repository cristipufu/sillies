import Foundation
import SilliesCore

/// Dedicated cancellable reader. Ranking cannot hold the actor responsible for saves and pages.
public final class VaultSemanticSearchDatabase {
  private let sql: VaultSQLConnection
  private let decoder: JSONDecoder

  public init(directory: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    sql = try VaultSQLConnection(
      url: directory.appendingPathComponent(VaultDatabase.filename), access: .readOnly)
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
  }

  public func search(
    _ request: VaultSearchRequest, embedding: SearchEmbedding, provider: String,
    candidates: [Int64]? = nil
  )
    throws -> [VaultSearchMatch]
  {
    try sql.cancellableRead {
      let vectorQuery = SearchVectorQuery(embedding)
      var ranking = VaultPassageRanking(limit: request.limit)
      if candidates?.isEmpty == true { return [] }
      guard (candidates?.count ?? 0) <= 256 else { throw CocoaError(.coderInvalidValue) }
      var values: [VaultSQLConnection.Value] = [.text(provider), .text(embedding.space)]
      let candidateFilter: String
      if let candidates {
        candidateFilter =
          " AND p.id IN (" + Array(repeating: "?", count: candidates.count).joined(separator: ",")
          + ")"
        values += candidates.map(VaultSQLConnection.Value.integer)
      } else {
        candidateFilter = ""
      }
      let workspaceFilter = request.workspaceQuery.map(VaultWorkspaceFilter.init)
      let workspaceConditions = workspaceFilter.map { " AND " + $0.sql } ?? ""
      values += workspaceFilter?.values ?? []
      let filter: String
      switch request.category {
      case .all: filter = ""
      case .screenshots: filter = " AND r.image IS NOT NULL"
      case .meetings: filter = " AND r.kind IN ('listen','participate','record')"
      case .stash: filter = " AND r.kind='stash'"
      case .links: return []  // URL listing and exact URL matching retain their keyword contract.
      }
      try sql.rows(
        """
        SELECT CAST(p.id AS TEXT),v.vector,p.record_id FROM passage_vectors v
        JOIN passages p ON p.id=v.passage_id JOIN available_records r ON r.id=p.record_id
        LEFT JOIN workspace w ON w.record_id=r.id
        WHERE v.provider=? AND v.space=? AND w.trashed IS NULL \(candidateFilter) \(workspaceConditions) \(filter)
        """, values
      ) { row in
        try Task.checkCancellation()
        let score = try VaultSQLConnection.withBlob(
          row, column: 1,
          maximumBytes: SearchVectorStorage.maximumBytes, consume: vectorQuery.similarity)
        try ranking.consider(score: score) {
          try (VaultSQLConnection.text(row, column: 2), VaultSQLConnection.text(row))
        }
      }
      var records: [VaultSearchMatch] = []
      var seen: Set<UUID> = []
      for id in ranking.passages {
        guard records.count < request.limit else { break }
        try sql.rows(
          """
          SELECT r.header,p.text,w.metadata,b.section,b.ordinal FROM passages p JOIN available_records r ON r.id=p.record_id
          JOIN content_blocks b ON b.id=p.block_id LEFT JOIN workspace w ON w.record_id=r.id WHERE p.id=? AND w.trashed IS NULL
          """, [.text(id)]
        ) { row in
          let header = try decoder.decode(
            SessionRecordHeader.self, from: VaultSQLConnection.data(row))
          guard seen.insert(header.id).inserted else { return }
          let bytes = try VaultSQLConnection.data(row, column: 2, maximumBytes: 65_536)
          let metadata =
            bytes.isEmpty
            ? VaultDocumentMetadata(modifiedAt: header.createdAt)
            : try decoder.decode(VaultDocumentMetadata.self, from: bytes)
          guard
            let section = VaultDocumentSection(
              rawValue: try VaultSQLConnection.text(row, column: 3)),
            let ordinal = Int(try VaultSQLConnection.text(row, column: 4)), ordinal >= 0
          else { throw CocoaError(.fileReadCorruptFile) }
          records.append(
            VaultSearchMatch(
              header: header, excerpt: try VaultSQLConnection.text(row, column: 1),
              retrieval: .semantic
            ).located(
              in: .init(source: header, metadata: metadata),
              at: .init(recordID: header.id, section: section, ordinal: ordinal)))
        }
      }
      return records
    }
  }
}
