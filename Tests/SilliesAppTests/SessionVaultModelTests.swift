import Foundation
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func vaultSavesExtractedHighlightsAlongsidePartialTranscriptFailures() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(
    directory: directory,
    notesGenerator: { _ in
      LocalNotes(
        summary: "• Ședința începe mâine.", actions: [], notice: "Generated notes unavailable.",
        source: .extracted)
    })
  await vault.waitUntilLoaded()
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting")),
    content: .init(
      text: .init(transcript: "Ședința începe mâine."),
      processing: .init(
        summaryPending: true,
        failure: SessionFailure(category: .finalization, message: "Partial audio failure"))))
  vault.add(record)
  await vault.flushPendingSummaries()
  let saved = try #require(vault.records.first)
  #expect(saved.notesSource == .extracted)
  #expect(!saved.summaryPending)
  #expect(saved.transcript == record.transcript)
  #expect(saved.failure == record.failure)
  await vault.flush()
}

@Test @MainActor func vaultSelectionStaysAdjacentWhenDeletingFilteredRecords() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  let records = (0..<3).map {
    SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting \($0)")))
  }
  for record in records.reversed() { vault.add(record) }
  let model = SessionVaultModel(vault: vault, initialRecordID: records[1].id)
  model.searchQuery = "Meeting"
  model.selectedFilter = .record
  await model.refreshSearch()
  model.delete(records[1])
  #expect(model.selectedRecordID == records[2].id)
  model.delete(records[2])
  #expect(model.selectedRecordID == records[0].id)
  model.delete(records[0])
  #expect(model.selectedRecord(in: model.filteredRecords) == nil)
  await vault.flush()
}

@Test @MainActor func stashSaveRevealsNewRecordAndUndoPreservesOtherRecords() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  let model = SessionVaultModel(vault: vault)
  model.saveStash(["   \n"])
  #expect(vault.records.isEmpty)
  model.saveStash([" first ", "\n", " second\n"])
  let firstID = try #require(model.lastStashID)
  #expect(vault.records.first?.stashedItems == ["first", "second"])
  model.searchQuery = "unrelated search"
  model.saveStash(["new item"])
  #expect(model.filteredRecords.first?.id == model.lastStashID)
  model.undoStash()
  #expect(vault.records.map(\.id) == [firstID])
  #expect(model.selectedRecordID == firstID)
  model.stop()
  await vault.flush()
  #expect(model.feedback == nil)
  #expect(model.lastStashID == nil)
}
