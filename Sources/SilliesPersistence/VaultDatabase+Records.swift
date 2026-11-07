import Foundation
import SilliesCore

extension VaultDatabase {
  public func page(_ request: VaultPageRequest) throws -> VaultPage {
    var filter = queryFilter(request.search)
    let total = try totalMatching(request.search, filter: filter)
    metrics.pageReads += 1
    guard total > 0 else { return VaultPage(records: [], total: 0, nextCursor: nil) }
    if let cursor = request.after {
      filter.sql += filter.sql.isEmpty ? "WHERE " : " AND "
      filter.sql += "(created < ? OR (created = ? AND r.id < ?))"
      let created = cursor.createdAt.timeIntervalSince1970
      filter.values += [.real(created), .real(created), .text(cursor.id.uuidString)]
    }
    let records = try headers(
      "SELECT header FROM available_records r \(filter.sql) ORDER BY created DESC, id DESC LIMIT ?",
      filter.values + [.integer(Int64(min(request.limit, total)))])
    return VaultPage(
      records: records, total: total,
      nextCursor: records.count == request.limit ? records.last.map(VaultPageCursor.init) : nil)
  }

  public func matchingHeaders(_ ids: Set<UUID>, search: SessionRecordSearch) throws
    -> VaultHeaderMatches
  {
    let filter = queryFilter(search)
    let total = try totalMatching(search, filter: filter)
    let identifiers = Array(ids)
    var matches: [SessionRecordHeader] = []
    let chunkSize = VaultPageRequest.maximumPageSize
    for start in stride(from: 0, to: identifiers.count, by: chunkSize) {
      let chunk = identifiers[start..<min(start + chunkSize, identifiers.count)]
      let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
      let conjunction = filter.sql.isEmpty ? "WHERE" : "AND"
      matches += try headers(
        "SELECT header FROM available_records r \(filter.sql) \(conjunction) r.id IN (\(placeholders))",
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

  private func totalMatching(
    _ search: SessionRecordSearch, filter: (sql: String, values: [VaultSQLConnection.Value])
  ) throws -> Int {
    guard search.query.isEmpty, try !cleanupProgress().isPending else {
      return try sql.integer(
        "SELECT count(*) FROM available_records r \(filter.sql)", filter.values)
    }
    return try sql.integer(
      "SELECT coalesce(sum(c.total-coalesce(t.total,0)),0) FROM library_counts c LEFT JOIN trash_counts t ON t.kind=c.kind\(search.kind == nil ? "" : " WHERE c.kind=?")",
      search.kind.map { [.text($0.rawValue)] } ?? [])
  }

  public func record(id: UUID) throws -> SessionRecord? {
    var record: SessionRecord?
    try sql.rows("SELECT body,protected FROM available_records WHERE id=?", [.text(id.uuidString)])
    {
      let data = try VaultSQLConnection.data($0)
      record = try decoder.decode(SessionRecord.self, from: data)
      record?.isProtected = try VaultSQLConnection.text($0, column: 1) == "1"
      metrics.decodedBodyBytes += data.count
      metrics.loadedBodies += 1
    }
    if var updated = record {
      let transcript = VaultBlockLocation(recordID: id, section: .transcript)
      if try sectionState(transcript)?.isEdited == true {
        updated.originalSpeakerTranscript = updated.originalSpeakerTranscript ?? updated.transcript
        updated.transcript = try sectionText(transcript)
      }
      let screenshot = VaultBlockLocation(recordID: id, section: .screenshotText)
      if try sectionState(screenshot)?.isEdited == true {
        updated.extractedText = try sectionText(screenshot)
      }
      if updated.kind == .stash, let workspace = try documentHeader(id: id),
        workspace.metadata.kind != .capture
      {
        let notes = try sectionText(.init(recordID: id, section: .notes))
        updated.stashedItems = [
          workspace.title, workspace.metadata.link?.url.absoluteString, notes,
        ].compactMap { $0 }.filter { !$0.isEmpty }
      }
      return updated
    }
    return nil
  }

  public func pendingSummaryIDs() throws -> [UUID] {
    try identifiers(
      "SELECT id FROM available_records WHERE pending_summary=1 ORDER BY created ASC, sequence ASC LIMIT 100"
    )
  }

  public func pendingScreenshot() throws -> SessionRecordHeader? {
    var header: SessionRecordHeader?
    try sql.rows(
      "SELECT header FROM available_records WHERE screenshot_state=? ORDER BY sequence ASC LIMIT 1",
      [.text(ScreenshotTextState.pending.rawValue)]
    ) {
      header = try decoder.decode(SessionRecordHeader.self, from: VaultSQLConnection.data($0))
    }
    return header
  }

  public func eligibleRetentionCount() throws -> Int {
    if try cleanupProgress().isPending {
      return try sql.integer(
        "SELECT count(*) FROM available_records r WHERE kind!='stash' AND protected=0 AND NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=r.id AND starred=1)"
      )
    }
    return try sql.integer("SELECT coalesce(sum(eligible),0) FROM library_counts")
  }

  func isRecordAvailable(_ id: UUID) throws -> Bool {
    try sql.integer(
      "SELECT EXISTS(SELECT 1 FROM available_records WHERE id=?)", [.text(id.uuidString)]) != 0
  }

  public func identifiers() throws -> [UUID] {
    try identifiers("SELECT id FROM available_records ORDER BY created DESC, id DESC")
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
    try updateSourceSections(record)
    metrics.encodedBodyBytes += body.count
    metrics.writtenBodies += 1
  }

  private func queryFilter(_ request: SessionRecordSearch) -> (
    sql: String, values: [VaultSQLConnection.Value]
  ) {
    var conditions = [
      "NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=r.id AND trashed IS NOT NULL)"
    ]
    var values: [VaultSQLConnection.Value] = []
    if let kind = request.kind {
      conditions.append("r.kind=?")
      values.append(.text(kind.rawValue))
    }
    if !request.query.isEmpty {
      if let expression = VaultSearchTerms.expression(request.query) {
        conditions.append(
          "(r.id IN (SELECT b.record_id FROM content_search JOIN content_blocks b ON b.id=content_search.rowid WHERE content_search MATCH ?) OR r.id IN (SELECT d.id FROM documents d JOIN content_backfill f ON f.record_id=d.id WHERE documents MATCH ?))"
        )
        values += [.text(expression), .text(expression)]
      } else {
        conditions.append("0")
      }
    }
    return (conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND "), values)
  }
}
