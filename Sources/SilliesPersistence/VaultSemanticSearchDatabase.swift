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

  public func search(_ request: VaultSearchRequest, embedding: SearchEmbedding, provider: String)
    throws -> [VaultSearchMatch]
  {
    try sql.cancellableRead {
      let vectorQuery = SearchVectorQuery(embedding)
      var ranking = VaultPassageRanking(limit: request.limit)
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
        JOIN passages p ON p.id=v.passage_id JOIN records r ON r.id=p.record_id
        WHERE v.provider=? AND v.space=? \(filter)
        """, [.text(provider), .text(embedding.space)]
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
          SELECT r.header,p.text FROM passages p JOIN records r ON r.id=p.record_id WHERE p.id=?
          """, [.text(id)]
        ) { row in
          let header = try decoder.decode(
            SessionRecordHeader.self, from: VaultSQLConnection.data(row))
          guard seen.insert(header.id).inserted else { return }
          records.append(
            .init(
              header: header, excerpt: try VaultSQLConnection.text(row, column: 1),
              retrieval: .semantic))
        }
      }
      return records
    }
  }
}
