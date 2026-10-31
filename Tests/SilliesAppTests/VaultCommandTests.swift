import Foundation
import SilliesCore
import SilliesReasoning
import SilliesVault
import Testing

@testable import SilliesApp

@Test @MainActor func vaultProtectionFromStaleDetailPreservesNewNotes() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  let original = commandRecord()
  vault.add(original)
  await vault.flush()
  let model = SessionVaultModel(vault: vault, initialRecordID: original.id)
  await model.loadSelection()
  let displayed = try #require(model.visibleDetail)
  try await vault.edit(
    id: original.id,
    .completeNotes(
      .init(summary: "New notes", actions: ["A commitment"]),
      revision: original.processingRevision.notes))
  await vault.flush()
  model.toggleProtection(displayed)
  await vault.flush()
  let saved = try #require(try await vault.record(id: original.id))
  #expect(saved.isProtected)
  #expect(saved.summary == "New notes")
  #expect(saved.actionItems == ["A commitment"])
  #expect(!saved.summaryPending)
  model.stop()
}

@Test @MainActor func vaultRegenerationPreservesSpeakerEditsAndRejectsSupersededResults()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  let original = commandRecord()
  vault.add(original)
  await vault.flush()
  var renamed = original
  renamed.transcript = "Alex: The updated transcript."
  renamed.speakerNames = ["meeting:1": "Alex"]
  try await vault.edit(id: original.id, .renameSpeaker(.init(original: original, renamed: renamed)))
  let model = SessionVaultModel(vault: vault)
  model.regenerateNotes(original)
  await vault.flush()
  #expect(
    try await vault.edit(
      id: original.id,
      .completeNotes(
        .init(summary: "Stale notes", actions: []), revision: original.processingRevision.notes))
      == false)
  let saved = try #require(try await vault.record(id: original.id))
  #expect(saved.transcript == renamed.transcript)
  #expect(saved.speakerNames == renamed.speakerNames)
  #expect(saved.summary == original.summary)
  #expect(saved.summaryPending)
  #expect(saved.processingRevision.notes != original.processingRevision.notes)
  vault.remove(id: original.id)
  #expect(try await vault.edit(id: original.id, .protection(.protected)) == false)
  await vault.flush()
  #expect(try await vault.record(id: original.id) == nil)
  model.stop()
}

@Test @MainActor func vaultScreenshotRetryRejectsThePreviousGeneration() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  let original = commandRecord()
  vault.add(original)
  try await vault.edit(id: original.id, .retryScreenshot)
  let pending = try #require(try await vault.record(id: original.id))
  #expect(
    try await vault.edit(
      id: original.id,
      .completeScreenshot(text: "stale", revision: original.processingRevision.screenshot)) == false
  )
  try await vault.edit(id: original.id, .protection(.protected))
  try await vault.edit(
    id: original.id,
    .completeScreenshot(text: "Ștefan", revision: pending.processingRevision.screenshot))
  await vault.flush()
  let saved = try #require(try await vault.record(id: original.id))
  #expect(saved.extractedText == "Ștefan")
  #expect(saved.isProtected)
}

private func commandRecord() -> SessionRecord {
  .init(
    kind: .record,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Fixture")),
    content: .init(
      text: .init(transcript: "The source transcript."), notes: .init(summary: "Earlier notes"),
      processing: .init(summaryPending: true)))
}
