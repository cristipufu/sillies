import SilliesCore

struct VaultChronologicalOrder {
  let value: String
  let direction: String
  let comparison: String

  init(_ ordering: VaultWorkspaceQuery.Ordering) {
    value = ordering == .modified ? "coalesce(r.modified,r.created)" : "r.created"
    direction = ordering == .oldest ? "ASC" : "DESC"
    comparison = ordering == .oldest ? ">" : "<"
  }

  func continuation(after cursor: VaultWorkspaceCursor?) -> String {
    cursor == nil ? "" : " AND (\(value),r.id) \(comparison) (?,?)"
  }

  func values(after cursor: VaultWorkspaceCursor?) -> [VaultSQLConnection.Value] {
    cursor.map { [.real($0.value), .text($0.id.uuidString)] } ?? []
  }
}
