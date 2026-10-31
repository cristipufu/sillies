import Foundation
import SilliesCore
import SilliesReasoning
import Testing

@testable import SilliesVault

@Test @MainActor func cancelledVaultNotesCannotReplaceANewerRequestForTheSameRecord() async throws {
  let generator = SuspendedVaultNotes()
  defer { generator.finishAll() }
  let records = NotesRecords()
  let scheduler = VaultSummaryScheduler(
    load: { await records.record($0) }, generate: { await generator.generate($0.summary) })
  defer { scheduler.stop() }
  var record = SessionRecord(
    kind: .focus,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")),
    content: .init(notes: .init(summary: "Original"), processing: .init(summaryPending: true)))
  var delivered: [String] = []
  records.store(record)
  scheduler.schedule(record.id) { notes, _ in delivered.append(notes.summary) }
  try await generator.waitForRequest("Original")
  scheduler.cancel(id: record.id)
  record.summary = "Replacement"
  records.store(record)
  scheduler.schedule(record.id) { notes, _ in delivered.append(notes.summary) }
  generator.finish("Original")
  try await generator.waitForRequest("Replacement")
  generator.finish("Replacement")
  await scheduler.flush()
  #expect(delivered == ["Replacement"])
  #expect(scheduler.count == 0)
  scheduler.stop()
  records.store(record)
  scheduler.schedule(record.id) { notes, _ in delivered.append(notes.summary) }
  #expect(scheduler.count == 0)
}

@MainActor private final class SuspendedVaultNotes {
  private var requests: [String: CheckedContinuation<LocalNotes, Never>] = [:]
  var requestedNames: Set<String> { Set(requests.keys) }

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

@Test @MainActor func thousandsOfPendingNotesAdmitOnlyOneProducerAndStopWithoutStartingTheRest()
  async throws
{
  let generator = SuspendedVaultNotes()
  defer { generator.finishAll() }
  let records = NotesRecords()
  let scheduler = VaultSummaryScheduler(
    load: { await records.record($0) }, generate: { await generator.generate($0.summary) })
  defer { scheduler.stop() }
  var delivered: [String] = []
  for index in 0..<2_000 {
    let record = SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "mochi", characterName: "Mochi", source: .init(appName: "Fixture")),
      content: .init(notes: .init(summary: "Job \(index)"), processing: .init(summaryPending: true))
    )
    records.store(record)
    scheduler.schedule(record.id) { notes, _ in delivered.append(notes.summary) }
  }
  try await generator.waitForRequest("Job 0")
  #expect(generator.requestedNames == ["Job 0"])
  generator.finish("Job 0")
  try await generator.waitForRequest("Job 1")
  #expect(generator.requestedNames == ["Job 1"])
  scheduler.stop()
  generator.finish("Job 1")
  await scheduler.flush()
  #expect(generator.requestedNames.isEmpty)
  #expect(delivered == ["Job 0"])
  #expect(scheduler.count == 0)
}

@MainActor private final class NotesRecords {
  private var values: [UUID: SessionRecord] = [:]
  func store(_ record: SessionRecord) { values[record.id] = record }
  func record(_ id: UUID) -> SessionRecord? { values[id] }
}
