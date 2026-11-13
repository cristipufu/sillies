import Foundation
import SilliesCore
import SilliesReasoning
import SilliesVault
import Testing

@testable import SilliesApp
@testable import SilliesPersistence

@Test @MainActor func vaultTopicNotesRetryFreshContextAndLeaveMyNotesAndTranscriptUntouched()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let producer = PendingTopicNotes()
  let vault = SessionVaultStore(
    directory: directory, notesGenerator: { await producer.generate($0) })
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  defer {
    vault.suspendBackgroundProcessing()
    producer.finishAll()
    removeTestFile(at: directory)
  }
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(
      text: .init(transcript: "We agreed to ship on Thursday."),
      notes: .init(summary: "Existing summary"), processing: .init(summaryPending: true)))
  _ = try await vault.library.createDocument(
    record: record,
    metadata: .init(kind: .capture, title: "Planning", modifiedAt: Date()), notes: "Original agenda"
  )
  vault.resumeBackgroundProcessing()
  try await producer.waitForRequest(1)
  let initial = try #require(producer.inputs.first)
  #expect(initial.personalNotes == "Original agenda")
  #expect(initial.record.transcript == record.transcript)
  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  var notesRevision: UUID?
  var pendingDraft = true
  let flusher = vault.registerDraftFlusher { completion in
    guard pendingDraft else {
      completion()
      return
    }
    pendingDraft = false
    Task { @MainActor in
      do {
        notesRevision = try await vault.library.editText(
          .init(
            location: location, expectedRevision: initial.revision.personalNotes,
            text: "Focus on the deadline."), at: Date())
        vault.workspaceChanged([record.id])
      } catch { Issue.record(error) }
      completion()
    }
  }
  defer { vault.unregisterDraftFlusher(flusher) }
  producer.finish(0, summary: "Stale generated notes")
  try await producer.waitForRequest(2)
  #expect(producer.inputs[1].personalNotes == "Focus on the deadline.")
  #expect(producer.inputs[1].revision.personalNotes == (try #require(notesRevision)))
  #expect(try await vault.library.record(id: record.id)?.summary == "Existing summary")
  try await vault.edit(id: record.id, .protection(.protected))
  producer.finish(1, summary: "Launch\n• Agreed deadline: Thursday.")
  await vault.flushPendingSummaries()
  let saved = try #require(try await vault.record(id: record.id))
  #expect(saved.summary == "Launch\n• Agreed deadline: Thursday.")
  #expect(saved.transcript == record.transcript)
  #expect(saved.isProtected)
  #expect(!saved.summaryPending)
  let personalNotes = try await vault.library.sectionPage(location).blocks.map(\.text).joined()
  #expect(personalNotes == "Focus on the deadline.")
  #expect(producer.inputs.count == 2)
}

@MainActor private final class PendingTopicNotes {
  private(set) var inputs: [VaultNotesInput] = []
  private var continuations: [Int: CheckedContinuation<LocalNotes, Never>] = [:]
  func generate(_ input: VaultNotesInput) async -> LocalNotes {
    let index = inputs.count
    inputs.append(input)
    return await withCheckedContinuation { continuations[index] = $0 }
  }
  func waitForRequest(_ count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while inputs.count < count, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    try #require(inputs.count == count)
  }
  func finish(_ index: Int, summary: String) {
    continuations.removeValue(forKey: index)?.resume(
      returning: .init(summary: summary, actions: []))
  }
  func finishAll() {
    for index in Array(continuations.keys) { finish(index, summary: "Cancelled fixture") }
  }
}

@Test @MainActor func vaultTopicNotesFailureQueuesLaterRequestsAndRetryResumesThem() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var generations: [UUID: Int] = [:]
  let vault = SessionVaultStore(
    directory: directory,
    notesGenerator: { input in
      await MainActor.run { generations[input.record.id, default: 0] += 1 }
      return .init(summary: "Generated notes", actions: [])
    })
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  defer {
    vault.suspendBackgroundProcessing()
    removeTestFile(at: directory)
  }
  let origin = SessionOrigin(
    characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting"))
  let first = SessionRecord(
    kind: .listen, origin: origin,
    content: .init(notes: .init(summary: "First notes"), processing: .init(summaryPending: true)))
  let second = SessionRecord(
    kind: .listen, origin: origin, content: .init(notes: .init(summary: "Second notes")))
  vault.add(first)
  vault.add(second)
  await vault.flush()
  try await executeNotesFixtureSQL(
    """
    CREATE TRIGGER reject_topic_notes BEFORE UPDATE ON content_sections
    WHEN NEW.section='summary' BEGIN SELECT RAISE(ABORT,'injected topic notes write failure'); END
    """, directory: directory)
  vault.resumeBackgroundProcessing()
  await vault.flushPendingSummaries()
  #expect(vault.persistenceError != nil)
  #expect(generations[first.id] == 1 && generations[second.id] == nil)
  try await vault.edit(id: second.id, .requestNotes)
  await vault.flush()
  try await executeNotesFixtureSQL("DROP TRIGGER reject_topic_notes", directory: directory)
  vault.retrySaving()
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while try await vault.library.record(id: second.id)?.summaryPending == true,
    ContinuousClock.now < deadline
  {
    try await Task.sleep(for: .milliseconds(1))
  }
  let saved = try #require(try await vault.library.record(id: second.id))
  #expect(!saved.summaryPending && saved.summary == "Generated notes")
  #expect(try await vault.library.record(id: first.id)?.summary == "Generated notes")
  #expect(generations[first.id] == 1 && generations[second.id] == 1)
  #expect(vault.persistenceError == nil)
}

private func executeNotesFixtureSQL(_ statement: String, directory: URL) async throws {
  try await Task.detached {
    let database = try VaultDatabase(directory: directory)
    try database.sql.execute(statement)
  }.value
}
