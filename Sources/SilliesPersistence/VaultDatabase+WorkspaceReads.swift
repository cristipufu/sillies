import Foundation
import SilliesCore

extension VaultDatabase {
  private static let maximumWorkspaceHeaderBytes = 65_536
  private static let maximumWorkspaceMetadataBytes = 65_536
  public func workspacePage(
    _ query: VaultWorkspaceQuery, after cursor: VaultWorkspaceCursor? = nil
  ) throws -> VaultWorkspacePage {
    guard cursor?.value.isFinite != false,
      query.source?.isValid != false,
      query.from?.timeIntervalSince1970.isFinite != false,
      query.until?.timeIntervalSince1970.isFinite != false
    else { throw VaultEditingError.invalidValue }
    return try sql.readSnapshot {
      try sql.cancellableRead {
        guard try hasPotentiallyVisibleRecords() else { return .init(records: [], next: nil) }
        if !query.text.isEmpty {
          return try query.ordering == .relevance
            ? rankedWorkspacePage(query, after: cursor)
            : dateOrderedSearchPage(query, after: cursor)
        }
        return try chronologicalWorkspacePage(query, after: cursor)
      }
    }
  }

  public func documentHeader(id: UUID) throws -> VaultDocumentHeader? {
    var result: VaultDocumentHeader?
    try sql.rows(
      "SELECT r.header,w.metadata FROM available_records r LEFT JOIN workspace w ON w.record_id=r.id WHERE r.id=?",
      [.text(id.uuidString)]
    ) { row in result = try workspaceHeader(row) }
    return result
  }

  private func chronologicalWorkspacePage(
    _ query: VaultWorkspaceQuery, after cursor: VaultWorkspaceCursor?
  ) throws -> VaultWorkspacePage {
    let filter = VaultWorkspaceFilter(query)
    let order = VaultChronologicalOrder(query.ordering)
    let values = filter.values + order.values(after: cursor)
    var headers: [VaultDocumentHeader] = []
    var lastValues: [Double] = []
    try sql.rows(
      """
      SELECT r.header,w.metadata,\(order.value) FROM available_records r LEFT JOIN workspace w ON w.record_id=r.id
      WHERE \(filter.sql) \(order.continuation(after: cursor)) ORDER BY \(order.value) \(order.direction),r.id \(order.direction) LIMIT ?
      """, values + [.integer(Int64(VaultWorkspacePage.maximumCount + 1))]
    ) { row in
      headers.append(try workspaceHeader(row))
      lastValues.append(try VaultSQLConnection.real(row, column: 2))
    }
    return workspacePage(headers, values: lastValues)
  }

  func rankedWorkspacePage(
    _ query: VaultWorkspaceQuery, after cursor: VaultWorkspaceCursor?
  ) throws -> VaultWorkspacePage {
    guard let plan = try VaultTextSearchPlan(query) else {
      return .init(records: [], next: nil)
    }
    let filter = VaultWorkspaceFilter(query)
    let usesRank = query.ordering == .relevance
    let selectedValue =
      usesRank
      ? "d.relevance"
      : (query.ordering == .modified ? "coalesce(r.modified,r.created)" : "r.created")
    let ascending = usesRank || query.ordering == .oldest
    let comparison = ascending ? ">" : "<"
    let direction = ascending ? "ASC" : "DESC"
    let continuation =
      cursor == nil ? "" : "AND (score\(comparison)? OR (score=? AND d.record_id\(comparison)?))"
    var matches: [VaultWorkspaceMatch] = []
    // Materialize FTS scores once per block, before grouping.
    // Apply record-level filters once per document, then decode only the visible headers.
    try sql.rows(
      """
      WITH scored AS MATERIALIZED (
        SELECT rowid AS block_id,rank AS relevance FROM \(plan.table) WHERE \(plan.table) MATCH ?),
      documents AS (
        SELECT b.record_id,min(s.relevance) AS relevance,b.id AS block_id
        FROM scored s JOIN content_blocks b INDEXED BY content_block_identity ON b.id=s.block_id
        GROUP BY b.record_id),
      matches AS (
        SELECT d.record_id,\(selectedValue) AS score,d.block_id
        FROM documents d JOIN available_records r ON r.id=d.record_id
        LEFT JOIN workspace w ON w.record_id=r.id
        WHERE \(filter.sql) \(continuation)
        ORDER BY score \(direction),d.record_id \(direction) LIMIT ?)
      SELECT r.header,w.metadata,m.score,b.section,b.ordinal,b.id,coalesce(b.start_seconds,-1)
      FROM matches m JOIN available_records r ON r.id=m.record_id
      LEFT JOIN workspace w ON w.record_id=r.id JOIN content_blocks b ON b.id=m.block_id
      ORDER BY m.score \(direction),m.record_id \(direction)
      """,
      [.text(plan.expression)] + filter.values + cursorValues(cursor)
        + [.integer(Int64(VaultWorkspacePage.maximumCount + 1))]
    ) { row in
      matches.append(try workspaceMatch(row))
    }
    let headers = try workspaceMatchHeaders(matches, plan: plan)
    return workspacePage(headers, values: matches.map(\.position))
  }

  func workspaceMatch(_ row: OpaquePointer) throws -> VaultWorkspaceMatch {
    let header = try workspaceHeader(row)
    let score = try VaultSQLConnection.real(row, column: 2)
    guard let section = VaultDocumentSection(rawValue: try VaultSQLConnection.text(row, column: 3)),
      let ordinal = Int(try VaultSQLConnection.text(row, column: 4)),
      let blockID = Int64(try VaultSQLConnection.text(row, column: 5))
    else { throw CocoaError(.fileReadCorruptFile) }
    let matched: VaultDocumentHeader =
      .init(
        source: header.source, metadata: header.metadata,
        match: .init(recordID: header.id, section: section, ordinal: ordinal)
      )
      .timed(at: Double(try VaultSQLConnection.text(row, column: 6)))
    return .init(header: matched, position: score, blockID: blockID)
  }

  private func cursorValues(_ cursor: VaultWorkspaceCursor?) -> [VaultSQLConnection.Value] {
    guard let cursor else { return [] }
    return [.real(cursor.value), .real(cursor.value), .text(cursor.id.uuidString)]
  }

  func workspacePage(_ headers: [VaultDocumentHeader], values: [Double])
    -> VaultWorkspacePage
  {
    let more = headers.count > VaultWorkspacePage.maximumCount
    let visible = Array(headers.prefix(VaultWorkspacePage.maximumCount))
    let next =
      more && !visible.isEmpty
      ? VaultWorkspaceCursor(value: values[visible.count - 1], id: visible[visible.count - 1].id)
      : nil
    return .init(records: visible, next: next)
  }

  private func workspaceHeader(_ row: OpaquePointer) throws -> VaultDocumentHeader {
    let header = try decoder.decode(
      SessionRecordHeader.self,
      from: VaultSQLConnection.data(row, maximumBytes: Self.maximumWorkspaceHeaderBytes))
    let stored = try VaultSQLConnection.data(
      row, column: 1, maximumBytes: Self.maximumWorkspaceMetadataBytes)
    var metadata =
      stored.isEmpty
      ? VaultDocumentMetadata(modifiedAt: header.createdAt)
      : try decoder.decode(VaultDocumentMetadata.self, from: stored)
    metadata.tags = []
    metadata.collectionIDs = []
    try sql.rows(
      "SELECT tag FROM vault_tags WHERE record_id=? ORDER BY tag LIMIT ?",
      [.text(header.id.uuidString), .integer(Int64(VaultDocumentMetadata.maximumTags + 1))]
    ) { value in
      metadata.tags.append(
        try VaultSQLConnection.text(
          value, maximumBytes: VaultDocumentMetadata.maximumTagScalars * 4))
    }
    try sql.rows(
      "SELECT collection_id FROM vault_collection_items WHERE record_id=? ORDER BY collection_id LIMIT ?",
      [.text(header.id.uuidString), .integer(Int64(VaultDocumentMetadata.maximumCollections + 1))]
    ) { value in
      guard let id = UUID(uuidString: try VaultSQLConnection.text(value)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      metadata.collectionIDs.append(id)
    }
    guard metadata.isValid else { throw CocoaError(.fileReadCorruptFile) }
    var excerpt = ""
    if metadata.kind != .capture {
      try sql.rows(
        "SELECT substr(text,1,?) FROM content_blocks WHERE record_id=? AND section='notes' ORDER BY ordinal LIMIT 1",
        [.integer(Int64(SessionRecordHeader.previewLimit)), .text(header.id.uuidString)]
      ) { value in
        excerpt = try VaultSQLConnection.text(value)
      }
      if excerpt.isEmpty, let link = metadata.link {
        excerpt = String(link.description.prefix(SessionRecordHeader.previewLimit))
      }
    }
    return .init(source: header, metadata: metadata, excerpt: excerpt)
  }
}
