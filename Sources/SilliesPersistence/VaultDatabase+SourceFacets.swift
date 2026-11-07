import Foundation
import SilliesCore

extension VaultDatabase {
  private struct FacetColumn {
    let kind: VaultSourceFacet.Kind
    let identity: String
    let label: String
    func value(_ row: String) -> String {
      "json_extract(CAST(\(row).header AS TEXT),'$.\(identity)')"
    }
    func title(_ row: String) -> String { "json_extract(CAST(\(row).header AS TEXT),'$.\(label)')" }
  }

  func prepareSourceFacets() throws {
    try sql.execute(
      "CREATE TABLE source_facets(kind TEXT NOT NULL,value TEXT NOT NULL,label TEXT NOT NULL,total INTEGER NOT NULL,PRIMARY KEY(kind,value))"
    )
    for column in [
      FacetColumn(kind: .app, identity: "appName", label: "appName"),
      FacetColumn(kind: .companion, identity: "characterID", label: "characterName"),
      FacetColumn(kind: .language, identity: "languageIdentifier", label: "languageIdentifier"),
    ] { try prepareFacet(column) }
  }

  private func prepareFacet(_ column: FacetColumn) throws {
    let kind = column.kind.rawValue
    try sql.execute(
      "CREATE INDEX records_source_\(kind) ON records(json_extract(CAST(header AS TEXT),'$.\(column.identity)'))"
    )
    try sql.execute(
      """
      INSERT INTO source_facets SELECT ?,\(column.value("r")),coalesce(max(\(column.title("r"))),''),count(*)
      FROM records r WHERE coalesce(\(column.value("r")),'')!='' GROUP BY \(column.value("r"))
      """, [.text(kind)])
    let insert = """
      INSERT INTO source_facets(kind,value,label,total)
      SELECT '\(kind)',\(column.value("new")),coalesce(\(column.title("new")),''),1
      WHERE coalesce(\(column.value("new")),'')!=''
      ON CONFLICT(kind,value) DO UPDATE SET total=total+1,label=excluded.label;
      """
    let remove = """
      UPDATE source_facets SET total=total-1 WHERE kind='\(kind)' AND value=\(column.value("old"));
      DELETE FROM source_facets WHERE kind='\(kind)' AND value=\(column.value("old")) AND total=0;
      """
    try sql.execute(
      "CREATE TRIGGER source_\(kind)_insert AFTER INSERT ON records BEGIN \(insert) END")
    try sql.execute(
      "CREATE TRIGGER source_\(kind)_delete AFTER DELETE ON records BEGIN \(remove) END")
    try sql.execute(
      """
      CREATE TRIGGER source_\(kind)_update AFTER UPDATE OF header ON records
      WHEN \(column.value("old")) IS NOT \(column.value("new")) OR \(column.title("old")) IS NOT \(column.title("new"))
      BEGIN \(remove) \(insert) END
      """)
  }

  /// A transactional facet cache avoids rescanning the archive when a filter opens.
  public func sourceFacets(_ kind: VaultSourceFacet.Kind, matching text: String) throws
    -> [VaultSourceFacet]
  {
    try sql.cancellableRead {
      var result: [VaultSourceFacet] = []
      try sql.rows(
        "SELECT value,label FROM source_facets WHERE kind=? AND instr(lower(label),lower(?))>0 ORDER BY value LIMIT ?",
        [
          .text(kind.rawValue),
          .text(String(text.prefix(VaultSourceFilter.maximumIdentifierScalars))),
          .integer(Int64(VaultSourceFacet.maximumChoices)),
        ]
      ) { row in
        let maximumBytes = VaultSourceFilter.maximumIdentifierScalars * 4
        let id = try VaultSQLConnection.text(row, maximumBytes: maximumBytes)
        let title = try VaultSQLConnection.text(row, column: 1, maximumBytes: maximumBytes)
        result.append(.init(id: id, title: title.isEmpty ? id : title))
      }
      return result
    }
  }
}
