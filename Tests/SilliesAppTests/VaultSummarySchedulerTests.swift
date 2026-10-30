import Foundation
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func cancelledVaultNotesCannotReplaceANewerRequestForTheSameRecord() async throws {
  let generator = SuspendedVaultNotes()
  defer { generator.finishAll() }
  let scheduler = VaultSummaryScheduler { await generator.generate($0.summary) }
  defer { scheduler.stop() }
  var record = SessionRecord(
    kind: .focus, characterID: "mochi", characterName: "Mochi", appName: "Test",
    summary: "Original", summaryPending: true)
  var delivered: [String] = []
  scheduler.schedule(record) { delivered.append($0.summary) }
  try await generator.waitForRequest("Original")
  scheduler.cancel(id: record.id)
  record.summary = "Replacement"
  scheduler.schedule(record) { delivered.append($0.summary) }
  try await generator.waitForRequest("Replacement")
  generator.finish("Original")
  generator.finish("Replacement")
  await scheduler.flush()
  #expect(delivered == ["Replacement"])
  #expect(scheduler.count == 0)
  scheduler.stop()
  scheduler.schedule(record) { delivered.append($0.summary) }
  #expect(scheduler.count == 0)
}

@MainActor private final class SuspendedVaultNotes {
  private var requests: [String: CheckedContinuation<LocalNotes, Never>] = [:]

  func generate(_ name: String) async -> LocalNotes {
    await withCheckedContinuation { requests[name] = $0 }
  }

  func waitForRequest(_ name: String) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while requests[name] == nil && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(requests[name] != nil)
  }

  func finish(_ name: String) {
    requests.removeValue(forKey: name)?.resume(returning: LocalNotes(summary: name, actions: []))
  }

  func finishAll() {
    for name in Array(requests.keys) { finish(name) }
  }
}
