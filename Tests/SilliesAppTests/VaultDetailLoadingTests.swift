import Foundation
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func vaultDetailSelectionRejectsLateResultsAndReleasesContentOnClose() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let first = detailRecord("First")
  let second = detailRecord("Second")
  vault.add(first)
  vault.add(second)
  await vault.flush()
  let loader = DelayedDetail()
  let model = SessionVaultModel(
    vault: vault, initialRecordID: first.id,
    loadDetail: { id in
      if id == first.id { return await loader.read(first) }
      return second
    })
  let old = Task { await model.loadSelection() }
  await loader.waitUntilStarted()
  model.selectedRecordID = second.id
  await model.loadSelection()
  #expect(model.visibleDetail?.id == second.id)
  await loader.release()
  await old.value
  #expect(model.visibleDetail?.id == second.id)
  model.stop()
  #expect(model.visibleDetail == nil)
}

@Test @MainActor func vaultDetailFailureKeepsSelectionAndCanRetry() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let record = detailRecord("Recoverable")
  vault.add(record)
  await vault.flush()
  let state = DetailFailureState()
  let model = SessionVaultModel(
    vault: vault, initialRecordID: record.id,
    loadDetail: { _ in
      if state.failed { throw CocoaError(.fileReadNoPermission) }
      return record
    })
  await model.loadSelection()
  #expect(model.detailError != nil)
  #expect(model.selectedRecordID == record.id)
  #expect(!model.isLoadingDetail)
  state.failed = false
  await model.loadSelection()
  #expect(model.visibleDetail?.transcript == record.transcript)
  #expect(model.detailError == nil)
  model.stop()
}

@MainActor private final class DetailFailureState {
  var failed = true
}

private func detailRecord(_ text: String) -> SessionRecord {
  .init(
    kind: .record,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: text)),
    content: .init(text: .init(transcript: text)))
}

private actor DelayedDetail {
  private var result: SessionRecord?
  private var continuation: CheckedContinuation<SessionRecord?, Never>?
  func read(_ record: SessionRecord) async -> SessionRecord? {
    result = record
    return await withCheckedContinuation { continuation = $0 }
  }
  func waitUntilStarted() async {
    for _ in 0..<1_000 {
      if continuation != nil { return }
      await Task.yield()
    }
    Issue.record("Detail request did not start")
  }
  func release() {
    continuation?.resume(returning: result)
    continuation = nil
  }
}
