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
    load: { await records.record($0) }, generate: { await generator.generate($0.record.summary) })
  defer { scheduler.stop() }
  var record = SessionRecord(
    kind: .focus,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")),
    content: .init(notes: .init(summary: "Original"), processing: .init(summaryPending: true)))
  var delivered: [String] = []
  records.store(record)
  scheduler.schedule(record.id) { notes, _ in
    delivered.append(notes.summary)
    return true
  }
  try await generator.waitForRequest("Original")
  scheduler.cancel(id: record.id)
  record.summary = "Replacement"
  records.store(record)
  scheduler.schedule(record.id) { notes, _ in
    delivered.append(notes.summary)
    return true
  }
  generator.finish("Original")
  try await generator.waitForRequest("Replacement")
  generator.finish("Replacement")
  await scheduler.flush()
  #expect(delivered == ["Replacement"])
  #expect(scheduler.count == 0)
  scheduler.stop()
  records.store(record)
  scheduler.schedule(record.id) { notes, _ in
    delivered.append(notes.summary)
    return true
  }
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
    load: { await records.record($0) }, generate: { await generator.generate($0.record.summary) })
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
    scheduler.schedule(record.id) { notes, _ in
      delivered.append(notes.summary)
      return true
    }
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
  func record(_ id: UUID) -> VaultNotesInput? {
    values[id].map { record in
      .init(
        record: record, personalNotes: "",
        revision: .init(
          generation: record.processingRevision.notes, transcript: nil, screenshotText: nil,
          personalNotes: nil))
    }
  }
}

@Test @MainActor func vaultNotesSaveFailureRetainsItsResultAndRetriesWithoutGeneratingAgain()
  async throws
{
  let records = NotesRecords()
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(
      text: .init(transcript: "A recorded decision."), processing: .init(summaryPending: true)))
  records.store(record)
  var generations = 0
  var deliveries = 0
  var saved: String?
  var failure: String?
  let scheduler = VaultSummaryScheduler(
    load: { await records.record($0) },
    generate: { _ in
      await MainActor.run { generations += 1 }
      return .init(summary: "Launch\n• A recorded decision.", actions: [])
    })
  defer { scheduler.stop() }
  scheduler.reportFailure = { failure = $0 }
  scheduler.schedule(record.id) { notes, _ in
    deliveries += 1
    if deliveries == 1 { throw CocoaError(.fileWriteNoPermission) }
    saved = notes.summary
    return true
  }
  await scheduler.flush()
  #expect(generations == 1 && deliveries == 1)
  #expect(scheduler.count == 1 && failure != nil)
  scheduler.stop()
  scheduler.resume()
  await scheduler.flush()
  #expect(generations == 1 && deliveries == 1)
  scheduler.retry()
  await scheduler.flush()
  #expect(generations == 1 && deliveries == 2)
  #expect(saved == "Launch\n• A recorded decision.")
  #expect(scheduler.count == 0 && failure == nil)
}

@Test @MainActor func vaultNotesReadFailureRemainsRetryableWithoutLosingTheRequest() async throws {
  let records = NotesRecords()
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(processing: .init(summaryPending: true)))
  records.store(record)
  var reads = 0
  var deliveries = 0
  var failure: String?
  let scheduler = VaultSummaryScheduler(
    load: { id in
      try await MainActor.run {
        reads += 1
        if reads == 1 { throw CocoaError(.fileReadNoPermission) }
        return records.record(id)
      }
    }, generate: { _ in .init(summary: "Recovered notes", actions: []) })
  defer { scheduler.stop() }
  scheduler.reportFailure = { failure = $0 }
  scheduler.schedule(record.id) { _, _ in
    deliveries += 1
    return true
  }
  await scheduler.flush()
  #expect(reads == 1 && deliveries == 0 && failure != nil && scheduler.count == 1)
  scheduler.retry()
  await scheduler.flush()
  #expect(reads == 2 && deliveries == 1 && failure == nil && scheduler.count == 0)
}

@Test @MainActor func vaultNotesPausedRetryKeepsTheGeneratedPayloadUntilDeliveryCompletes()
  async throws
{
  let records = NotesRecords()
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(processing: .init(summaryPending: true)))
  records.store(record)
  var generations = 0
  var deliveries = 0
  var suspended: CheckedContinuation<Bool, any Error>?
  let scheduler = VaultSummaryScheduler(
    load: { await records.record($0) },
    generate: { _ in
      await MainActor.run { generations += 1 }
      return .init(summary: "Retained notes", actions: [])
    })
  defer { scheduler.stop() }
  scheduler.schedule(record.id) { _, _ in
    deliveries += 1
    if deliveries == 1 { throw CocoaError(.fileWriteNoPermission) }
    if deliveries == 2 {
      return try await withCheckedThrowingContinuation { suspended = $0 }
    }
    return true
  }
  await scheduler.flush()
  scheduler.retry()
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while suspended == nil, ContinuousClock.now < deadline { await Task.yield() }
  let delivery = try #require(suspended)
  scheduler.stop()
  #expect(scheduler.count == 1)
  delivery.resume(throwing: CancellationError())
  await scheduler.flush()
  #expect(generations == 1 && deliveries == 2 && scheduler.count == 1)
  scheduler.stop()
  scheduler.resume()
  await scheduler.flush()
  #expect(generations == 1 && deliveries == 3 && scheduler.count == 0)
}
