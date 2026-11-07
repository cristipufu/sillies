import Foundation
import SilliesCore
import SilliesPersistence

/// Publishes only complete backups. Cancellation or a concurrently removed attachment leaves no successful archive.
actor VaultBackupWorker {
  private let source: URL
  init(source: URL) { self.source = source }
  func usage() throws -> VaultStorageUsage { try VaultStorageInspection.measure(source) }

  func write(to destination: URL) async throws -> URL {
    let identifier = UUID().uuidString
    let staging = destination.appendingPathComponent(
      ".sillies-backup-" + identifier, isDirectory: true)
    let published = destination.appendingPathComponent(
      "Sillies Vault " + identifier, isDirectory: true)
    try FileManager.default.createDirectory(
      at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    do {
      try await copyDatabase(to: staging)
      try await copyAttachments(to: staging)
      try Data(
        "Sillies Vault backup\nContains captures, notes, links, collections, drafts and their files, including Trash. Companion conversations are stored separately. Downloaded models and derived native search caches are not included.\n"
          .utf8
      )
      .write(to: staging.appendingPathComponent("BACKUP.txt"), options: .atomic)
      try Task.checkCancellation()
      try FileManager.default.moveItem(at: staging, to: published)
      return published
    } catch {
      do { try FileManager.default.removeItem(at: staging) } catch {
        fputs("Incomplete backup cleanup failed: \(error)\n", stderr)
      }
      throw error
    }
  }

  private func copyDatabase(to directory: URL) async throws {
    let backup = try VaultSQLiteBackup(
      source: source.appendingPathComponent(VaultDatabase.filename),
      destination: directory.appendingPathComponent(VaultDatabase.filename))
    while try !backup.step() { await Task.yield() }
  }

  private func copyAttachments(to directory: URL) async throws {
    let snapshot = try VaultDatabase(reading: directory)
    var sequence: Int64 = 0
    while let batch = try snapshot.backupAttachments(after: sequence) {
      try Task.checkCancellation()
      for name in batch.filenames {
        try VaultAttachmentCopy.copy(
          name, from: .init(directory: source), to: .init(directory: directory))
      }
      sequence = batch.sequence
      await Task.yield()
    }
  }
}
