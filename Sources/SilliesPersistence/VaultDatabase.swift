import Foundation
import SilliesCore

/// Authoritative versioned storage. Confined to one worker, with bodies read only by explicit ID.
public final class VaultDatabase {
  public static let filename = "vault.sqlite"
  private static let schemaVersion = 4
  private static let directoryPermissions = 0o700
  let sql: VaultSQLConnection
  let files: VaultFileStorage
  let encoder: JSONEncoder
  let decoder: JSONDecoder
  let supportsSearchMetadata: Bool
  public internal(set) var metrics = VaultStorageMetrics()

  public convenience init(directory: URL) throws {
    try self.init(directory: directory, access: .readWrite)
  }

  public convenience init(reading directory: URL) throws {
    try self.init(directory: directory, access: .readOnly)
  }

  private init(directory: URL, access: VaultSQLConnection.Access) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    files = VaultFileStorage(directory: directory)
    if access == .readWrite {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: Self.directoryPermissions])
    }
    sql = try VaultSQLConnection(
      url: directory.appendingPathComponent(Self.filename), access: access)
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let storedVersion = try sql.integer("PRAGMA user_version")
    supportsSearchMetadata = access == .readWrite || storedVersion >= 4
    guard access == .readWrite else {
      // A previous workspace backup can be copied before launch upgrades its private copy.
      guard (3...Self.schemaVersion).contains(storedVersion) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return
    }
    try sql.execute("PRAGMA journal_mode=WAL")
    try sql.execute("PRAGMA synchronous=FULL")
    try sql.execute("PRAGMA secure_delete=ON")
    try prepareSchema()
    try recoverAttachments()
  }

  private func prepareSchema() throws {
    let version = try sql.integer("PRAGMA user_version")
    guard version <= Self.schemaVersion else {
      throw VaultStorageError(
        message: String(
          localized:
            "This Vault was created by a newer Sillies version. Its files have been preserved.")
      )
    }
    if version == 0 { try prepareInitialSchema() }
    if version < 2 { try preparePassageSchema() }
    if version < 3 { try prepareWorkspaceSchema() }
    if version < 4 { try prepareSearchMetadataSchema() }
  }

  private func prepareInitialSchema() throws {
    try sql.transaction {
      try sql.execute(
        "CREATE TABLE IF NOT EXISTS records(sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, created REAL NOT NULL, kind TEXT NOT NULL, protected INTEGER NOT NULL, pending_summary INTEGER NOT NULL, screenshot_state TEXT NOT NULL, image TEXT, audio TEXT, header BLOB NOT NULL, body BLOB NOT NULL)"
      )
      try sql.execute(
        "CREATE INDEX IF NOT EXISTS records_listing ON records(created DESC, id DESC)")
      try sql.execute(
        "CREATE INDEX IF NOT EXISTS records_kind_listing ON records(kind, created DESC, id DESC)"
      )
      try sql.execute("CREATE INDEX IF NOT EXISTS records_image ON records(image)")
      try sql.execute("CREATE INDEX IF NOT EXISTS records_audio ON records(audio)")
      try sql.execute("CREATE TABLE IF NOT EXISTS attachment_cleanup(filename TEXT PRIMARY KEY)")
      try sql.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS documents USING fts5(id UNINDEXED, body, tokenize='unicode61 remove_diacritics 2')"
      )
      try sql.execute("PRAGMA user_version=1")
    }
  }

}
