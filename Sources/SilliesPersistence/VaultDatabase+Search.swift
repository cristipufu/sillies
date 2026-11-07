import Foundation
import SilliesCore

extension VaultDatabase {
  /// Rank indexed text without decoding record bodies. Empty queries return recent matching items.
  public func search(_ request: VaultSearchRequest) throws -> [VaultSearchMatch] {
    var query =
      request.workspaceQuery ?? VaultWorkspaceQuery(text: request.query, ordering: .relevance)
    switch request.category {
    case .all: break
    case .meetings: query.scope = .meetings
    case .screenshots: query.scope = .screenshots
    case .stash: query.kind = .stash
    case .links: query.content = .savedURLs
    }
    var matches = try workspacePage(query).records.filter { header in
      request.category != .links || header.metadata.kind == .link || header.source.kind == .stash
    }.prefix(request.limit).map {
      VaultSearchMatch(
        header: $0.source, excerpt: $0.excerpt.isEmpty ? $0.source.preview : $0.excerpt
      ).located(in: $0)
    }
    if request.workspaceQuery == nil, matches.count < request.limit,
      try sql.integer("SELECT EXISTS(SELECT 1 FROM content_backfill)") == 1
    {
      let known = Set(matches.map(\.header.id))
      matches += try legacySearch(request).filter { !known.contains($0.header.id) }.prefix(
        request.limit - matches.count)
    }
    return matches
  }

  private func legacySearch(_ request: VaultSearchRequest) throws -> [VaultSearchMatch] {
    var conditions: [String] = [
      "NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=r.id AND trashed IS NOT NULL)",
      "EXISTS(SELECT 1 FROM content_backfill WHERE record_id=r.id)",
    ]
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
      "SELECT r.header, \(snippet) FROM available_records r \(joined) \(filter) ORDER BY \(ordering) LIMIT ?",
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
