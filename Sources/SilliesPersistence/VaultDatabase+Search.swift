import Foundation
import SilliesCore

extension VaultDatabase {
  /// Rank indexed text without decoding record bodies. Empty queries return recent matching items.
  public func search(_ request: VaultSearchRequest) throws -> [VaultSearchMatch] {
    var conditions: [String] = []
    var values: [VaultSQLConnection.Value] = []
    var expression =
      request.query.isEmpty ? nil : VaultSearchTerms.expression(request.query, matching: .anyTerm)
    if !request.query.isEmpty, expression == nil { return [] }
    switch request.category {
    case .all: break
    case .screenshots: conditions.append("r.image IS NOT NULL")
    case .meetings: conditions.append("r.kind IN ('listen','participate','record')")
    case .stash: conditions.append("r.kind='stash'")
    case .links:
      conditions.append("r.kind='stash'")
      expression = expression.map { "(\($0)) AND (http OR https)" } ?? "http OR https"
    }
    let joined: String
    let ordering: String
    let snippet: String
    if let expression {
      joined = "JOIN documents ON documents.id=r.id"
      conditions.append("documents MATCH ?")
      values.append(.text(expression))
      ordering = "bm25(documents), r.created DESC, r.id DESC"
      snippet = "snippet(documents,1,'','',' … ',24)"
    } else {
      joined = ""
      ordering = "r.created DESC, r.id DESC"
      snippet = "''"
    }
    let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
    var result: [VaultSearchMatch] = []
    try sql.rows(
      "SELECT r.header, \(snippet) FROM records r \(joined) \(filter) ORDER BY \(ordering) LIMIT ?",
      values + [.integer(Int64(request.limit))]
    ) { row in
      let header = try decoder.decode(SessionRecordHeader.self, from: VaultSQLConnection.data(row))
      let excerpt = try VaultSQLConnection.text(row, column: 1)
      result.append(.init(header: header, excerpt: excerpt.isEmpty ? header.preview : excerpt))
      metrics.loadedHeaders += 1
    }
    metrics.pageReads += 1
    return result
  }
}
