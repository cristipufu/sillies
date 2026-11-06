import Foundation
import SilliesCore
import SilliesVault
import Testing

@testable import SilliesApp

@Test @MainActor func vaultDismissalInvalidatesActionsWaitingForPersistence() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  var exports = 0
  var discussions = 0
  let owner = ConversationOwner(id: "pogo", name: "Pogo")
  let model = SessionVaultModel(
    vault: vault,
    presentation: .init(
      windowActions: .init(
        export: { _, done in
          exports += 1
          done(nil)
        }, popOutTranscript: { _ in }),
      discussion: .init(
        companions: [owner],
        open: { _, _ in
          discussions += 1
          return nil
        })))
  model.exportAll()
  model.discuss(UUID(), with: owner)
  model.stop()
  #expect(!model.isExporting)
  model.resume()
  await vault.flush()
  #expect(exports == 0)
  #expect(discussions == 0)
  #expect(model.feedback == nil && model.discussionFailure == nil)
  model.exportAll()
  model.exportAll()
  model.discuss(UUID(), with: owner)
  model.discuss(UUID(), with: owner)
  await vault.flush()
  #expect(exports == 1 && discussions == 1)
  model.stop()
}

@Test @MainActor func staleExportCompletionCannotFinishANewerExport() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  var completions: [(String?) -> Void] = []
  let model = SessionVaultModel(
    vault: vault,
    presentation: .init(
      windowActions: .init(
        export: { _, done in completions.append(done) }, popOutTranscript: { _ in })))
  model.exportAll()
  await vault.flush()
  #expect(completions.count == 1)
  model.stop()
  model.resume()
  model.exportAll()
  await vault.flush()
  guard completions.count == 2 else {
    Issue.record("Reopening must allow a new export after cancelling the old presentation.")
    completions.first?(nil)
    model.stop()
    return
  }
  completions[0]("Old completion")
  #expect(model.isExporting && model.feedback == nil)
  completions[1]("Current completion")
  #expect(!model.isExporting && model.feedback == "Current completion")
  model.stop()
}

@Test @MainActor func deletingVaultRecordOutsideCurrentListingSelectsARemainingRecord()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  await vault.waitUntilLoaded()
  let remaining = actionRecord("Visible")
  vault.add(remaining)
  await vault.flush()
  let linked = actionRecord("Linked later")
  let model = SessionVaultModel(vault: vault, presentation: .init())
  await model.refreshSearch()
  vault.add(linked)
  await vault.flush()
  model.navigate(to: linked.id)
  await model.loadSelection()
  #expect(model.visibleDetail?.id == linked.id)
  #expect(!model.filteredRecords.contains { $0.id == linked.id })
  model.delete(linked)
  #expect(model.selectedRecordID == remaining.id)
  await model.loadSelection()
  #expect(model.visibleDetail?.id == remaining.id && model.detailError == nil)
  await vault.flush()
  model.stop()
}

private func actionRecord(_ title: String) -> SessionRecord {
  .init(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: title)))
}

@Test @MainActor func cancelledVaultConversationActionNeverStartsOpening() async {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  var opens = 0
  let model = VaultConversationsModel(
    presentation: .init(
      repository: ConversationLibrary(directory: directory),
      open: { _, _ in
        opens += 1
        return nil
      }))
  model.open(.init(id: "pogo", name: "Pogo"))
  model.stop()
  for _ in 0..<20 { await Task.yield() }
  #expect(opens == 0 && !model.isOpening)
}
