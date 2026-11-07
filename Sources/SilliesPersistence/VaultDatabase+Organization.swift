import Foundation
import SilliesCore

extension VaultDatabase {
  private static let maximumOrganizationItems = 500
  private static let maximumOrganizationNameScalars = 120
  private static let maximumSavedSearchScalars = 2_048
  private enum OrganizationTable: String {
    case collections = "vault_collections"
    case searches = "vault_saved_searches"
  }
  public func collections() throws -> [VaultCollection] {
    var result: [VaultCollection] = []
    try sql.rows(
      "SELECT id,name FROM vault_collections ORDER BY name COLLATE NOCASE LIMIT ?",
      [.integer(Int64(Self.maximumOrganizationItems + 1))]
    ) {
      row in
      guard let id = UUID(uuidString: try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      result.append(
        .init(
          id: id,
          name: try VaultSQLConnection.text(
            row, column: 1, maximumBytes: Self.maximumOrganizationNameScalars * 4)))
    }
    guard result.count <= Self.maximumOrganizationItems else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return result
  }

  public func saveCollection(_ collection: VaultCollection) throws {
    guard !collection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      collection.name.unicodeScalars.count <= Self.maximumOrganizationNameScalars
    else { throw VaultEditingError.invalidValue }
    try validateOrganizationCapacity(.collections, id: collection.id)
    try sql.execute(
      "INSERT INTO vault_collections(id,name) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name",
      [.text(collection.id.uuidString), .text(collection.name)])
  }

  public func removeCollection(id: UUID) throws {
    try sql.transaction {
      try sql.execute(
        "DELETE FROM vault_collection_items WHERE collection_id=?", [.text(id.uuidString)])
      try sql.execute("DELETE FROM vault_collections WHERE id=?", [.text(id.uuidString)])
    }
  }

  public func savedSearches() throws -> [VaultSavedSearch] {
    var result: [VaultSavedSearch] = []
    try sql.rows(
      "SELECT body FROM vault_saved_searches ORDER BY id LIMIT ?",
      [.integer(Int64(Self.maximumOrganizationItems + 1))]
    ) { row in
      result.append(
        try decoder.decode(
          VaultSavedSearch.self, from: VaultSQLConnection.data(row, maximumBytes: 16_384)))
    }
    guard result.count <= Self.maximumOrganizationItems else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public func saveSearch(_ search: VaultSavedSearch) throws {
    guard !search.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      search.name.unicodeScalars.count <= Self.maximumOrganizationNameScalars,
      search.query.text.unicodeScalars.count <= Self.maximumSavedSearchScalars
    else {
      throw VaultEditingError.invalidValue
    }
    try validateOrganizationCapacity(.searches, id: search.id)
    try sql.execute(
      "INSERT INTO vault_saved_searches(id,body) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body",
      [.text(search.id.uuidString), .data(try encoder.encode(search))])
  }

  public func removeSavedSearch(id: UUID) throws {
    try sql.execute("DELETE FROM vault_saved_searches WHERE id=?", [.text(id.uuidString)])
  }

  private func validateOrganizationCapacity(_ table: OrganizationTable, id: UUID) throws {
    let exists =
      try sql.integer(
        "SELECT EXISTS(SELECT 1 FROM \(table.rawValue) WHERE id=?)", [.text(id.uuidString)]) == 1
    if exists { return }
    guard try sql.integer("SELECT count(*) FROM \(table.rawValue)") < Self.maximumOrganizationItems
    else {
      throw VaultEditingError.invalidValue
    }
  }
}
