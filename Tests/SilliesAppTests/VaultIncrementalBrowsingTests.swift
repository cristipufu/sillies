import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault
import Testing

@testable import SilliesApp

@Test @MainActor func vaultShowMoreReadsOnlyTheNextPageAndUnrelatedEditsKeepDetailStable()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  let records = (0..<401).map { index in
    SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting \(index)")),
      metadata: .init(createdAt: Date(timeIntervalSince1970: Double(10_000 - index))))
  }
  for record in records { vault.add(record) }
  await vault.flush()
  let model = SessionVaultModel(vault: vault, initialRecordID: records[0].id)
  await model.refreshSearch()
  #expect(model.filteredRecords.count == 200)
  let before = try await vault.library.metrics()
  model.showMore()
  await model.refreshSearch()
  let after = try await vault.library.metrics()
  #expect(model.filteredRecords.count == 400)
  #expect(after.pageReads - before.pageReads == 1)
  #expect(after.loadedHeaders - before.loadedHeaders == 200)
  let detailIdentity = model.detailIdentity
  try await vault.edit(id: records[400].id, .protection(.protected))
  await vault.flush()
  let beforeRefresh = try await vault.library.metrics()
  await model.refreshSearch()
  let afterRefresh = try await vault.library.metrics()
  #expect(afterRefresh.pageReads == beforeRefresh.pageReads)
  #expect(afterRefresh.loadedHeaders - beforeRefresh.loadedHeaders == 1)
  #expect(model.detailIdentity == detailIdentity)
  #expect(model.selectedRecordID == records[0].id)
  #expect(model.filteredRecords.map(\.id) == Array(records.prefix(400)).map(\.id))
  model.showMore()
  await model.refreshSearch()
  #expect(model.filteredRecords.count == 401)
  #expect(model.filteredRecords.last?.isProtected == true)
  #expect(!model.hasMoreResults)
  model.stop()
}

@Test @MainActor func incrementalNotesRefreshUpdatesSearchMembershipAndSelectedDetails()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  func record(_ title: String) -> SessionRecord {
    .init(
      kind: .record,
      origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: title)),
      content: .init(processing: .init(summaryPending: true)))
  }
  let first = record("First")
  let second = record("Second")
  vault.add(first)
  vault.add(second)
  await vault.flush()
  let model = SessionVaultModel(vault: vault, initialRecordID: first.id)
  model.searchQuery = "decision"
  await model.refreshSearch()
  #expect(model.filteredRecords.isEmpty)
  let previousIdentity = model.detailIdentity
  try await vault.edit(
    id: first.id,
    .completeNotes(
      .init(summary: "A decision", actions: []), revision: first.processingRevision.notes))
  await vault.flush()
  let beforeFirstRefresh = try await vault.library.metrics()
  await model.refreshSearch()
  #expect(try await vault.library.metrics().pageReads == beforeFirstRefresh.pageReads)
  #expect(model.filteredRecords.map(\.id) == [first.id])
  #expect(model.detailIdentity != previousIdentity)
  await model.loadSelection()
  #expect(model.visibleDetail?.summary == "A decision")
  try await vault.edit(id: first.id, .requestNotes)
  let revised = try #require(try await vault.record(id: first.id))
  try await vault.edit(
    id: first.id,
    .completeNotes(
      .init(summary: "No matching word", actions: []), revision: revised.processingRevision.notes))
  await vault.flush()
  let before = try await vault.library.metrics()
  await model.refreshSearch()
  #expect(model.filteredRecords.isEmpty)
  #expect(model.selectedRecordID == first.id)
  #expect(try await vault.library.metrics().pageReads == before.pageReads)
  model.stop()
}

@Test @MainActor func backgroundRefreshesStaySelectiveAfterJournalRotation() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  let selected = SessionRecord(
    kind: .record,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Selected")))
  let other = SessionRecord(
    kind: .record,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Background")))
  vault.add(selected)
  vault.add(other)
  await vault.flush()
  let model = SessionVaultModel(vault: vault, initialRecordID: selected.id)
  await model.refreshSearch()
  let identity = model.detailIdentity
  for _ in 0..<300 {
    try await vault.edit(id: other.id, .protection(.protected))
    await model.refreshSearch()
    #expect(model.detailIdentity == identity)
  }
  #expect(model.selectedRecordID == selected.id)
  model.stop()
}
