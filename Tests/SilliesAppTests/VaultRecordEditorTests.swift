import Foundation
import SilliesCore
import SilliesVault
import Testing

@testable import SilliesApp

private actor DelayedVaultRead {
  var completion: CheckedContinuation<SessionRecord?, Never>?
  func load() async -> SessionRecord? { await withCheckedContinuation { completion = $0 } }
  func complete(_ record: SessionRecord) {
    completion?.resume(returning: record)
    completion = nil
  }
}

@Test @MainActor func fieldEditRevalidatesWhenAnotherWriteArrivesDuringItsRead() async throws {
  let worker = DelayedVaultRead()
  let original = SessionRecord(
    kind: .record,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")))
  var pending: SessionRecord?
  var revision = 0
  var saved: SessionRecord?
  let editor = VaultRecordEditor(
    load: { _ in await worker.load() },
    context: .init(
      revision: { _ in revision }, pending: { _ in pending }, isRemoved: { _ in false },
      save: { saved = $0 }))
  var completed = false
  editor.submit(id: original.id, edit: .protection(.protected)) { result in
    if case .success(true) = result {
      completed = true
    } else {
      Issue.record("Edit was not accepted")
    }
  }
  for _ in 0..<200 {
    if await worker.completion != nil { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(await worker.completion != nil)
  var newer = original
  newer.summary = "Notes saved while the read was in flight"
  pending = newer
  revision += 1
  await worker.complete(original)
  await withCheckedContinuation { continuation in editor.flush { continuation.resume() } }
  #expect(completed)
  #expect(saved?.isProtected == true)
  #expect(saved?.summary == newer.summary)
}
