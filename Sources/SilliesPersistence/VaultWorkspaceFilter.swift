import Foundation
import SilliesCore

/// Only domain-owned fragments enter SQL. All user-supplied text is bound separately.
struct VaultWorkspaceFilter {
  private(set) var conditions: [String] = []
  private(set) var values: [VaultSQLConnection.Value] = []
  var sql: String { conditions.joined(separator: " AND ") }

  init(_ query: VaultWorkspaceQuery) {
    conditions.append(query.scope == .trash ? "w.trashed IS NOT NULL" : "w.trashed IS NULL")
    switch query.scope {
    case .all, .trash: break
    case .starred: conditions.append("w.starred=1 OR r.protected=1")
    case .notes: conditions.append("w.kind='note'")
    case .links:
      conditions.append(
        "w.kind='link' OR (r.kind='stash' AND coalesce(w.kind,'capture')='capture')")
    case .meetings: conditions.append("r.kind IN ('listen','participate','record')")
    case .screenshots: conditions.append("r.image IS NOT NULL")
    case .conversations: conditions.append("0")
    }
    if let from = query.from { append("r.created>=?", .real(from.timeIntervalSince1970)) }
    if let until = query.until { append("r.created<?", .real(until.timeIntervalSince1970)) }
    if let collection = query.collectionID {
      append(
        "EXISTS(SELECT 1 FROM vault_collection_items c WHERE c.record_id=r.id AND c.collection_id=?)",
        .text(collection.uuidString))
    }
    if let tag = query.tag {
      append("EXISTS(SELECT 1 FROM vault_tags t WHERE t.record_id=r.id AND t.tag=?)", .text(tag))
    }
    if let kind = query.kind { append("r.kind=?", .text(kind.rawValue)) }
    if let app = query.source?.appName {
      append("json_extract(CAST(r.header AS TEXT),'$.appName')=?", .text(app))
    }
    if let companion = query.source?.companionID {
      append("json_extract(CAST(r.header AS TEXT),'$.characterID')=?", .text(companion))
    }
    if let language = query.source?.languageIdentifier {
      append("json_extract(CAST(r.header AS TEXT),'$.languageIdentifier')=?", .text(language))
    }
    if query.content == .savedURLs {
      conditions.append(
        """
        w.kind='link' OR (r.kind='stash' AND EXISTS(
          SELECT 1 FROM content_search WHERE content_search MATCH 'http OR https'
          AND rowid IN (SELECT id FROM content_blocks WHERE record_id=r.id)))
        """)
    }
    conditions = conditions.map { "(\($0))" }
  }

  private mutating func append(_ condition: String, _ value: VaultSQLConnection.Value) {
    conditions.append(condition)
    values.append(value)
  }
}
