import Foundation
import SilliesCore

extension ConversationDatabase {
  public func memoryPage(_ request: CompanionMemoryPageRequest) throws -> CompanionMemoryPage {
    try sql.cancellableRead {
      try validate(request.handle)
      var predicate = "owner=?"
      var values: [VaultSQLConnection.Value] = [.text(request.handle.companionID)]
      let cursor: CompanionMemoryCursor?
      let comparison: String
      let order: String
      switch request.position {
      case .latest: (cursor, comparison, order) = (nil, "<", "DESC")
      case .before(let value): (cursor, comparison, order) = (value, "<", "DESC")
      case .after(let value): (cursor, comparison, order) = (value, ">", "ASC")
      }
      if let cursor {
        let timestamp = cursor.savedAt.timeIntervalSince1970
        guard timestamp.isFinite else { throw ConversationStorageError.invalidData }
        predicate += " AND (updated,id)\(comparison)(?,?)"
        values += [.real(timestamp), .text(cursor.id.uuidString)]
      }
      let limit = CompanionMemoryPageRequest.pageSize
      var facts = try CompanionMemoryRows.read(
        from: sql,
        statement:
          "SELECT body FROM companion_memories WHERE \(predicate) ORDER BY updated \(order),id \(order) LIMIT ?",
        values: values + [.integer(Int64(limit))])
      if case .after = request.position { facts.reverse() }
      let next = try pageCursor(facts.last, owner: request.handle.companionID, comparison: "<")
      let previous = try pageCursor(facts.first, owner: request.handle.companionID, comparison: ">")
      return .init(facts: facts, next: next, previous: previous)
    }
  }

  private func pageCursor(_ boundary: CompanionMemory?, owner: String, comparison: String) throws
    -> CompanionMemoryCursor?
  {
    guard let boundary else { return nil }
    let exists = try sql.integer(
      "SELECT EXISTS(SELECT 1 FROM companion_memories WHERE owner=? AND (updated,id)\(comparison)(?,?))",
      [.text(owner), .real(boundary.savedAt.timeIntervalSince1970), .text(boundary.id.uuidString)])
    return exists == 1 ? .init(boundary) : nil
  }

}
