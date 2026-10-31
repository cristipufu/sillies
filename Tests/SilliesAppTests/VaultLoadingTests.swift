import AppKit
import SilliesCore
import SilliesPersistence
import SilliesVault
import Testing

@testable import SilliesApp

@Test @MainActor
func vaultLoadingMergesEarlyChangesWithoutOverwritingSavedSessions() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-load-\(UUID().uuidString)")
  defer { removeTestFile(at: directory) }
  let original = SessionVaultStore(directory: directory)
  let retained = makeLoadTestRecord("Retained")
  let removed = makeLoadTestRecord("Removed during load")
  original.add(retained)
  original.add(removed)
  await original.flush()

  let loading = SessionVaultStore(directory: directory)
  #expect(loading.records.isEmpty)
  let added = makeLoadTestRecord("Added during load")
  loading.add(added)
  loading.remove(id: removed.id)
  await loading.flush()
  #expect(loading.records.map(\.id) == [added.id, retained.id])

  let reloaded = SessionVaultStore(directory: directory)
  await reloaded.waitUntilLoaded()
  #expect(reloaded.records.map(\.id) == [added.id, retained.id])

  let clearing = SessionVaultStore(directory: directory)
  clearing.clearAll()
  clearing.add(added)
  await clearing.flush()
  #expect(clearing.records.map(\.id) == [added.id])
  let final = SessionVaultStore(directory: directory)
  await final.waitUntilLoaded()
  #expect(final.records.map(\.id) == [added.id])
}

@Test @MainActor
func quittingBeforeVaultLoadFinishesFlushesInTheModalRunLoop() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-load-quit-\(UUID().uuidString)")
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let record = makeLoadTestRecord("Saved while loading")
  vault.add(record)
  var finished = false
  vault.flushOnIOQueue {
    MainActor.assumeIsolated { finished = true }
  }
  pumpVaultModalRunLoop { finished }
  #expect(finished)
  #expect(try await vault.record(id: record.id)?.summary == record.summary)
}

private func makeLoadTestRecord(_ summary: String) -> SessionRecord {
  SessionRecord(
    kind: .focus,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")),
    content: .init(notes: .init(summary: summary)))
}

@Test @MainActor
func vaultLoadingSearchToleratesRepeatedRecordIdentifiers() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let record = makeLoadTestRecord("Repeated capture")
  vault.add(record)
  vault.add(record)
  await vault.flush()
  #expect(vault.persistenceError == nil)
  #expect(
    Set(try await vault.page(.init(search: .init(kind: nil, query: "Repeated"))).records.map(\.id))
      == [record.id])
}

@Test @MainActor
func vaultPreservesCorruptMetadataAndMergesPendingChangesAfterRecovery() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let retained = makeLoadTestRecord("Retain after recovery")
  let removed = makeLoadTestRecord("Remove during failed load")
  try await Task.detached {
    let database = try VaultDatabase(directory: directory)
    try database.commit(.init(records: [.insert(retained), .insert(removed)]))
  }.value
  let url = directory.appendingPathComponent(VaultDatabase.filename)
  let recoverable = try Data(contentsOf: url)
  let corrupted = Data("{ interrupted metadata".utf8)
  try corrupted.write(to: url)

  let vault = SessionVaultStore(directory: directory)
  let added = makeLoadTestRecord("Added while storage is unavailable")
  vault.add(added)
  vault.remove(id: removed.id)
  await vault.flush()
  #expect(vault.persistenceError != nil)
  #expect(try Data(contentsOf: url) == corrupted)
  vault.retrySaving()
  await vault.flush()
  #expect(vault.persistenceError != nil)
  #expect(try Data(contentsOf: url) == corrupted)

  try recoverable.write(to: url)
  vault.retrySaving()
  await vault.flush()
  #expect(vault.persistenceError == nil)
  #expect(vault.records.map(\.id) == [added.id, retained.id])
  let reloaded = SessionVaultStore(directory: directory)
  await reloaded.waitUntilLoaded()
  #expect(reloaded.records.map(\.id) == [added.id, retained.id])
}

@Test @MainActor func deliberateStashesSurviveHistoryLimitAndRelaunch() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let domain = "sillies-retention-tests-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let vault = SessionVaultStore(directory: directory, defaults: defaults)
  let stash = SessionRecord(
    kind: .stash,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Pocket Stash")),
    content: .init(text: .init(stashedItems: ["Keep until I delete it"])))
  vault.add(stash)
  for index in 0..<(VaultPageRequest.maximumPageSize + 2) {
    vault.add(
      SessionRecord(
        kind: .snap,
        origin: .init(
          characterID: "mochi", characterName: "Mochi", source: .init(appName: "Capture \(index)")))
    )
  }
  await vault.flush()
  #expect(vault.recordCount == VaultPageRequest.maximumPageSize + 3)
  vault.applyRetention(.recent200)
  await vault.flush()
  #expect(vault.recordCount == VaultPageRequest.maximumPageSize + 1)
  let loaded = SessionVaultStore(directory: directory, defaults: defaults)
  await loaded.waitUntilLoaded()
  #expect(try await loaded.record(id: stash.id) != nil)
  loaded.remove(id: stash.id)
  await loaded.flush()
  #expect(try await loaded.record(id: stash.id) == nil)
}

@Test @MainActor func vaultReportsUnwritableStorageInsteadOfAcknowledgingASave() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try Data("occupied".utf8).write(to: directory)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.add(makeLoadTestRecord("Cannot persist here"))
  let error: String? = await withCheckedContinuation { continuation in
    vault.whenPersisted { continuation.resume(returning: $0) }
  }
  #expect(error != nil)
  #expect(vault.persistenceError != nil)
}

@MainActor private func pumpVaultModalRunLoop(_ complete: () -> Bool) {
  let deadline = ProcessInfo.processInfo.systemUptime + 3
  while !complete(), ProcessInfo.processInfo.systemUptime < deadline {
    CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString), 0.01, true)
  }
}

@Test @MainActor func quittingFlushesFieldEditsWhileOnlyTheModalRunLoopIsPumping() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let record = makeLoadTestRecord("Protected during quit")
  vault.add(record)
  await vault.flush()
  let model = SessionVaultModel(vault: vault)
  model.toggleProtection(record)
  var finished = false
  vault.flushOnIOQueue { MainActor.assumeIsolated { finished = true } }
  pumpVaultModalRunLoop { finished }
  #expect(finished)
  let reloaded = SessionVaultStore(directory: directory)
  #expect(try await reloaded.record(id: record.id)?.isProtected == true)
  model.stop()
}
