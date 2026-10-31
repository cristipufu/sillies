import Foundation
import SilliesCore

extension VaultDatabase {
  private static let maximumSearchTokens = 32
  public func page(_ request: VaultPageRequest) throws -> VaultPage {
    var filter = queryFilter(request.search)
    let total = try sql.integer("SELECT count(*) FROM records r \(filter.sql)", filter.values)
    if let cursor = request.after {
      filter.sql += filter.sql.isEmpty ? "WHERE " : " AND "
      filter.sql += "(created < ? OR (created = ? AND r.id < ?))"
      let created = cursor.createdAt.timeIntervalSince1970
      filter.values += [.real(created), .real(created), .text(cursor.id.uuidString)]
    }
    let records = try headers(
      "SELECT header FROM records r \(filter.sql) ORDER BY created DESC, id DESC LIMIT ?",
      filter.values + [.integer(Int64(request.limit))])
    metrics.pageReads += 1
    return VaultPage(
      records: records, total: total,
      nextCursor: records.count == request.limit ? records.last.map(VaultPageCursor.init) : nil)
  }

  public func matchingHeaders(_ ids: Set<UUID>, search: SessionRecordSearch) throws
    -> VaultHeaderMatches
  {
    let filter = queryFilter(search)
    let total = try sql.integer("SELECT count(*) FROM records r \(filter.sql)", filter.values)
    let identifiers = Array(ids)
    var matches: [SessionRecordHeader] = []
    let chunkSize = VaultPageRequest.maximumPageSize
    for start in stride(from: 0, to: identifiers.count, by: chunkSize) {
      let chunk = identifiers[start..<min(start + chunkSize, identifiers.count)]
      let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
      let conjunction = filter.sql.isEmpty ? "WHERE" : "AND"
      matches += try headers(
        "SELECT header FROM records r \(filter.sql) \(conjunction) r.id IN (\(placeholders))",
        filter.values + chunk.map { .text($0.uuidString) })
    }
    return .init(records: matches, total: total)
  }

  private func headers(_ query: String, _ values: [VaultSQLConnection.Value]) throws
    -> [SessionRecordHeader]
  {
    var records: [SessionRecordHeader] = []
    try sql.rows(query, values) {
      records.append(
        try decoder.decode(SessionRecordHeader.self, from: VaultSQLConnection.data($0)))
      metrics.loadedHeaders += 1
    }
    return records
  }

  public func record(id: UUID) throws -> SessionRecord? {
    var record: SessionRecord?
    try sql.rows("SELECT body FROM records WHERE id=?", [.text(id.uuidString)]) {
      let data = try VaultSQLConnection.data($0)
      record = try decoder.decode(SessionRecord.self, from: data)
      metrics.decodedBodyBytes += data.count
      metrics.loadedBodies += 1
    }
    return record
  }

  public func pendingSummaryIDs() throws -> [UUID] {
    try identifiers(
      "SELECT id FROM records WHERE pending_summary=1 ORDER BY created ASC, sequence ASC")
  }

  public func pendingScreenshot() throws -> SessionRecordHeader? {
    var header: SessionRecordHeader?
    try sql.rows(
      "SELECT header FROM records WHERE screenshot_state=? ORDER BY sequence ASC LIMIT 1",
      [.text(ScreenshotTextState.pending.rawValue)]
    ) {
      header = try decoder.decode(SessionRecordHeader.self, from: VaultSQLConnection.data($0))
    }
    return header
  }

  public func eligibleRetentionCount() throws -> Int {
    try sql.integer(
      "SELECT count(*) FROM records WHERE kind != ? AND protected=0",
      [.text(CompanionSkillKind.stash.rawValue)])
  }

  public func identifiers() throws -> [UUID] {
    try identifiers("SELECT id FROM records ORDER BY created DESC, id DESC")
  }

  func identifiers(_ query: String, _ values: [VaultSQLConnection.Value] = []) throws -> [UUID] {
    var result: [UUID] = []
    try sql.rows(query, values) {
      guard let id = UUID(uuidString: try VaultSQLConnection.text($0)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      result.append(id)
    }
    return result
  }

  func store(_ record: SessionRecord) throws {
    for filename in [record.imageFilename, record.audioFilename].compactMap({ $0 }) {
      _ = try files.attachmentURL(for: filename)
    }
    let body = try encoder.encode(record)
    let header = try encoder.encode(SessionRecordHeader(record))
    try sql.execute(
      "INSERT INTO records(id,created,kind,protected,pending_summary,screenshot_state,image,audio,header,body) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET created=excluded.created,kind=excluded.kind,protected=excluded.protected,pending_summary=excluded.pending_summary,screenshot_state=excluded.screenshot_state,image=excluded.image,audio=excluded.audio,header=excluded.header,body=excluded.body",
      [
        .text(record.id.uuidString), .real(record.createdAt.timeIntervalSince1970),
        .text(record.kind.rawValue),
        .integer(record.isProtected ? 1 : 0), .integer(record.summaryPending ? 1 : 0),
        .text(record.screenshotTextState.rawValue),
        record.imageFilename.map(VaultSQLConnection.Value.text) ?? .null,
        record.audioFilename.map(VaultSQLConnection.Value.text) ?? .null, .data(header),
        .data(body),
      ])
    try sql.execute("DELETE FROM documents WHERE id=?", [.text(record.id.uuidString)])
    try sql.execute(
      "INSERT INTO documents(id,body) VALUES(?,?)",
      [.text(record.id.uuidString), .text(Self.searchableText(record))])
    metrics.encodedBodyBytes += body.count
    metrics.writtenBodies += 1
    metrics.indexedDocuments += 1
  }

  private static func searchableText(_ record: SessionRecord) -> String {
    ([
      record.displayTitle, record.appName, record.summary, record.transcript, record.extractedText,
      record.explanation,
    ]
      + record.actionItems + record.stashedItems).joined(separator: "\n")
  }

  private func queryFilter(_ request: SessionRecordSearch) -> (
    sql: String, values: [VaultSQLConnection.Value]
  ) {
    var conditions: [String] = []
    var values: [VaultSQLConnection.Value] = []
    if let kind = request.kind {
      conditions.append("r.kind=?")
      values.append(.text(kind.rawValue))
    }
    if !request.query.isEmpty {
      let tokens = request.query.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.prefix(
        Self.maximumSearchTokens)
      if tokens.isEmpty {
        conditions.append("0")
      } else {
        let expression = tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
        conditions.append("r.id IN (SELECT id FROM documents WHERE documents MATCH ?)")
        values.append(.text(expression))
      }
    }
    return (conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND "), values)
  }
}
