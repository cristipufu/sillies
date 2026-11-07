import Foundation

/// Installing a prepared backup happens before opening SQLite, never underneath live connections.
public struct VaultPreparedRestore: Sendable {
  public struct Receipt: Codable, Equatable, Sendable {
    public let id: UUID
    public let previousDirectory: URL?
  }
  private struct Plan: Codable {
    let id: UUID
    let hadOriginal: Bool
  }
  private static let maximumPlanBytes = 4_096
  private let directory: URL
  public let preparationDirectory: URL
  private var planURL: URL { preparationDirectory.appendingPathComponent("pending.json") }

  public init(directory: URL) {
    self.directory = directory
    preparationDirectory = directory.deletingLastPathComponent().appendingPathComponent(
      directory.lastPathComponent + ".restore", isDirectory: true)
  }
  public func preparedDirectory() throws -> URL? {
    try plan().map { staged($0.id) }
  }
  public func publish(_ prepared: URL) throws {
    guard try plan() == nil else { throw alreadyPrepared() }
    let id = UUID()
    let target = staged(id)
    try FileManager.default.moveItem(at: prepared, to: target)
    do {
      let plan = Plan(id: id, hadOriginal: FileManager.default.fileExists(atPath: directory.path))
      try JSONEncoder().encode(plan).write(to: planURL, options: .atomic)
    } catch {
      do { try FileManager.default.moveItem(at: target, to: prepared) } catch {
        fputs("Restore preparation rollback failed: \(error)\n", stderr)
      }
      throw error
    }
  }
  public func cancel() throws {
    guard let plan = try plan() else { return }
    guard !FileManager.default.fileExists(atPath: previous(plan.id).path) else {
      throw VaultStorageError(
        message: String(
          localized: "Vault restoration has already started. Restart Sillies to finish recovery."))
    }
    try FileManager.default.removeItem(at: planURL)
    // This path is generated solely from a decoded UUID inside our own preparation directory.
    if FileManager.default.fileExists(atPath: staged(plan.id).path) {
      try FileManager.default.removeItem(at: staged(plan.id))
    }
  }

  public func activate() throws -> Receipt? {
    guard let plan = try plan() else { return nil }
    let files = FileManager.default
    let prepared = staged(plan.id)
    let preserved = previous(plan.id)
    let hasPrepared = files.fileExists(atPath: prepared.path)
    let hasCurrent = files.fileExists(atPath: directory.path)
    let hasPreserved = files.fileExists(atPath: preserved.path)
    if !hasPrepared, hasCurrent, hasPreserved || !plan.hadOriginal {
      // The process stopped after installation and before acknowledging the receipt.
      _ = try VaultDatabase(reading: directory)
      try files.removeItem(at: planURL)
      return .init(id: plan.id, previousDirectory: hasPreserved ? preserved : nil)
    }
    guard hasPrepared, !(hasCurrent && hasPreserved) else {
      throw VaultStorageError(
        message: String(
          localized: "The prepared Vault backup is incomplete. Existing files were preserved."))
    }
    _ = try VaultDatabase(reading: prepared)
    if hasCurrent { try files.moveItem(at: directory, to: preserved) }
    do { try files.moveItem(at: prepared, to: directory) } catch {
      if files.fileExists(atPath: preserved.path), !files.fileExists(atPath: directory.path) {
        do { try files.moveItem(at: preserved, to: directory) } catch {
          fputs("Vault restore rollback failed: \(error)\n", stderr)
        }
      }
      throw error
    }
    try files.removeItem(at: planURL)
    return .init(id: plan.id, previousDirectory: hasCurrent || hasPreserved ? preserved : nil)
  }

  public func requireAvailable() throws {
    if try plan() != nil { throw alreadyPrepared() }
    try FileManager.default.createDirectory(
      at: preparationDirectory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
  }
  private func alreadyPrepared() -> VaultStorageError {
    .init(
      message: String(
        localized:
          "A Vault backup is already prepared for the next launch. Cancel it before choosing another."
      ))
  }
  private func staged(_ id: UUID) -> URL {
    preparationDirectory.appendingPathComponent("prepared-" + id.uuidString, isDirectory: true)
  }
  private func previous(_ id: UUID) -> URL {
    directory.deletingLastPathComponent().appendingPathComponent(
      directory.lastPathComponent + ".before-restore-" + id.uuidString, isDirectory: true)
  }
  private func plan() throws -> Plan? {
    guard FileManager.default.fileExists(atPath: planURL.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: planURL)
    defer {
      do { try handle.close() } catch { fputs("Restore plan close failed: \(error)\n", stderr) }
    }
    let bytes = try handle.read(upToCount: Self.maximumPlanBytes + 1) ?? Data()
    guard bytes.count <= Self.maximumPlanBytes else { throw CocoaError(.fileReadCorruptFile) }
    return try JSONDecoder().decode(Plan.self, from: bytes)
  }
}
