import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@testable import SilliesVault

@Test func vaultRestoreWaitsForLaunchAndPreservesThePreviousArchive() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let current = root.appendingPathComponent("Current")
  let original = try await prepareVaultRestoreFixture(root: root, current: current)
  let ordinaryReader = VaultLibrary(directory: current)
  #expect(try await ordinaryReader.snapshot().page.records.map(\.id) == [original])
  let launched = VaultLibrary(directory: current, opening: .applicationLaunch)
  #expect(try await launched.snapshot().page.records.first?.appName == "Recovered")
  let receipt = try #require(await launched.restoreReceipt)
  let preserved = VaultLibrary(directory: try #require(receipt.previousDirectory))
  #expect(try await preserved.snapshot().page.records.map(\.id) == [original])
  #expect(try await launched.preparedRestoreDirectory() == nil)
}

@Test func cancellingPreparedVaultRestoreKeepsCurrentRecordsAndAllowsAnotherBackup() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let current = root.appendingPathComponent("Current")
  let original = try await prepareVaultRestoreFixture(root: root, current: current)
  let library = VaultLibrary(directory: current)
  let staged = try #require(try await library.preparedRestoreDirectory())
  try await library.cancelPreparedRestore()
  #expect(!FileManager.default.fileExists(atPath: staged.path))
  let launched = VaultLibrary(directory: current, opening: .applicationLaunch)
  #expect(try await launched.snapshot().page.records.map(\.id) == [original])
  #expect(await launched.restoreReceipt == nil)
  await #expect(throws: Error.self) {
    try await library.prepareRestore(from: root.appendingPathComponent("Missing backup"))
  }
  #expect(try await library.preparedRestoreDirectory() == nil)
  #expect(try await library.snapshot().page.records.map(\.id) == [original])
}

@Test func vaultRestoreResumesAfterTheOriginalDirectoryHasBeenPreserved() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let current = root.appendingPathComponent("Current")
  let original = try await prepareVaultRestoreFixture(root: root, current: current)
  let restore = VaultPreparedRestore(directory: current)
  let staged = try #require(try restore.preparedDirectory())
  let identifier = try #require(
    UUID(uuidString: String(staged.lastPathComponent.dropFirst("prepared-".count))))
  let preserved = root.appendingPathComponent("Current.before-restore-" + identifier.uuidString)
  try FileManager.default.moveItem(at: current, to: preserved)
  let launched = VaultLibrary(directory: current, opening: .applicationLaunch)
  #expect(try await launched.snapshot().page.records.first?.appName == "Recovered")
  #expect(await launched.restoreReceipt?.previousDirectory?.path == preserved.path)
  let prior = VaultLibrary(directory: preserved)
  #expect(try await prior.snapshot().page.records.map(\.id) == [original])
}

private func prepareVaultRestoreFixture(root: URL, current: URL) async throws -> UUID {
  let source = VaultLibrary(directory: root.appendingPathComponent("Source"))
  let recovered = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Recovered")))
  _ = try await source.commit(.init(records: [.insert(recovered)]))
  let backup = try await source.backup(to: root)
  let library = VaultLibrary(directory: current, opening: .applicationLaunch)
  let original = SessionRecord(
    kind: .stash,
    origin: .init(
      characterID: "pogo", characterName: "Pogo", source: .init(appName: "Before restore")))
  _ = try await library.commit(.init(records: [.insert(original)]))
  try await library.prepareRestore(from: backup)
  #expect(try await library.snapshot().page.records.map(\.id) == [original.id])
  return original.id
}

@Test func vaultRestoreAcknowledgesInstallationAfterAnInterruptedReceiptRemoval() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let current = root.appendingPathComponent("Current")
  _ = try await prepareVaultRestoreFixture(root: root, current: current)
  let restore = VaultPreparedRestore(directory: current)
  let staged = try #require(try restore.preparedDirectory())
  let identifier = String(staged.lastPathComponent.dropFirst("prepared-".count))
  let preserved = root.appendingPathComponent("Current.before-restore-" + identifier)
  try FileManager.default.moveItem(at: current, to: preserved)
  try FileManager.default.moveItem(at: staged, to: current)
  let launched = VaultLibrary(directory: current, opening: .applicationLaunch)
  #expect(try await launched.snapshot().page.records.first?.appName == "Recovered")
  #expect(await launched.restoreReceipt?.previousDirectory?.path == preserved.path)
  #expect(try restore.preparedDirectory() == nil)
}

@Test func vaultRestoreCanInstallWithoutAnExistingArchiveAndRejectsInvalidPlans() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let source = VaultLibrary(directory: root.appendingPathComponent("Source"))
  _ = try await source.snapshot()
  let backup = try await source.backup(to: root)
  let current = root.appendingPathComponent("New vault")
  let library = VaultLibrary(directory: current)
  try await library.prepareRestore(from: backup)
  let restore = VaultPreparedRestore(directory: current)
  let staged = try #require(try restore.preparedDirectory())
  try FileManager.default.moveItem(at: staged, to: current)
  let launched = VaultLibrary(directory: current, opening: .applicationLaunch)
  #expect(try await launched.snapshot().page.records.isEmpty)
  let receipt = try #require(await launched.restoreReceipt)
  #expect(receipt.previousDirectory == nil)
  let plan = restore.preparationDirectory.appendingPathComponent("pending.json")
  for invalid in [Data("{invalid}".utf8), Data(repeating: 32, count: 8_192)] {
    try invalid.write(to: plan)
    #expect(throws: Error.self) { try restore.activate() }
    #expect(
      FileManager.default.fileExists(
        atPath: current.appendingPathComponent(VaultDatabase.filename).path))
  }
}
