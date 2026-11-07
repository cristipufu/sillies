import Foundation
import SQLite3

/// A pinned WAL read snapshot and bounded page copies leave the live writer available.
public final class VaultSQLiteBackup {
  private let destinationURL: URL
  private var transfer: Transfer?
  private var isComplete = false

  public init(source: URL, destination: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    destinationURL = destination
    transfer = try Transfer(source: source, destination: destination)
  }

  /// Returns true when the destination contains a complete snapshot.
  public func step() throws -> Bool {
    try Task.checkCancellation()
    guard !isComplete else { return true }
    guard try transfer?.step() ?? true else { return false }
    transfer = nil
    try finalizeDestination()
    isComplete = true
    return true
  }

  private func finalizeDestination() throws {
    // A fresh connection reads the copied WAL header. The original destination connection still
    // remembers its initial DELETE mode, so changing that connection's mode can be a no-op.
    let destination = try VaultSQLConnection(url: destinationURL)
    // This private, unopened snapshot needs no inter-process WAL index during finalization.
    try destination.execute("PRAGMA locking_mode=EXCLUSIVE")
    var journalMode = ""
    try destination.rows("PRAGMA journal_mode=DELETE") { row in
      journalMode = try VaultSQLConnection.text(row)
    }
    guard journalMode == "delete" else { throw CocoaError(.fileWriteUnknown) }
  }

  /// The transfer owns both connections until the final copy step releases its transaction.
  private final class Transfer {
    private static let pagesPerStep: Int32 = 256
    private let source: VaultSQLConnection
    private let destination: VaultSQLConnection
    private var handle: OpaquePointer?

    init(source: URL, destination: URL) throws {
      self.source = try VaultSQLConnection(url: source, access: .readOnly)
      self.destination = try VaultSQLConnection(url: destination)
      try self.source.execute("BEGIN")
      _ = try self.source.integer("PRAGMA user_version")
      handle = self.source.startBackup(to: self.destination)
      guard handle != nil else { throw CocoaError(.fileWriteUnknown) }
    }

    func step() throws -> Bool {
      guard let handle else { return true }
      let status = sqlite3_backup_step(handle, Self.pagesPerStep)
      if status == SQLITE_DONE {
        self.handle = nil
        let finished = sqlite3_backup_finish(handle)
        guard finished == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        try source.execute("ROLLBACK")
        return true
      }
      guard status == SQLITE_OK else {
        throw VaultStorageError(
          message: String(localized: "Could not complete the Vault backup (\(status))."))
      }
      return false
    }

    deinit { if let handle { sqlite3_backup_finish(handle) } }
  }
}
