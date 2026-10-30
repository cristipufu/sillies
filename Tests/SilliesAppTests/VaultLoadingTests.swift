import AppKit
import SilliesCore
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
func quittingBeforeVaultLoadFinishesFlushesInTheModalRunLoop() throws {
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
  let deadline = ProcessInfo.processInfo.systemUptime + 3
  while !finished, ProcessInfo.processInfo.systemUptime < deadline {
    CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString), 0.01, true)
  }
  #expect(finished)
  let data = try Data(contentsOf: directory.appendingPathComponent("sessions.json"))
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  #expect(try decoder.decode([SessionRecord].self, from: data).map(\.id) == [record.id])
}

private func makeLoadTestRecord(_ summary: String) -> SessionRecord {
  SessionRecord(
    kind: .focus,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")),
    content: .init(notes: .init(summary: summary)))
}

@Test @MainActor
func vaultPreservesCorruptMetadataAndMergesPendingChangesAfterRecovery() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let original = SessionVaultStore(directory: directory)
  let retained = makeLoadTestRecord("Retain after recovery")
  let removed = makeLoadTestRecord("Remove during failed load")
  original.add(retained)
  original.add(removed)
  await original.flush()
  let url = directory.appendingPathComponent("sessions.json")
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
  let vault = SessionVaultStore(directory: directory)
  let stash = SessionRecord(
    kind: .stash,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Pocket Stash")),
    content: .init(text: .init(stashedItems: ["Keep until I delete it"])))
  vault.add(stash)
  for index in 0..<(SessionVaultStore.maxStoredRecords + 2) {
    vault.add(
      SessionRecord(
        kind: .snap,
        origin: .init(
          characterID: "mochi", characterName: "Mochi", source: .init(appName: "Capture \(index)")))
    )
  }
  await vault.flush()
  #expect(vault.records.count == SessionVaultStore.maxStoredRecords + 1)
  let loaded = SessionVaultStore(directory: directory)
  await loaded.waitUntilLoaded()
  #expect(loaded.records.contains { $0.id == stash.id })
  loaded.remove(id: stash.id)
  await loaded.flush()
  #expect(!loaded.records.contains { $0.id == stash.id })
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
