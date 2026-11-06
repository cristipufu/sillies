import Foundation
import SilliesCore
import Testing

@testable import SilliesChat

@Test @MainActor func selectedVaultRecordsRejectLateReadsAndKeepBoundedReferences() async throws {
  let provider = SelectedMaterialProbe()
  let selection = ChatSelectedRecords(provider: provider)
  let first = UUID()
  #expect(selection.add(first))
  await provider.waitForRead()
  selection.remove(first)
  await provider.release()
  for _ in 0..<20 { await Task.yield() }
  #expect(selection.records.isEmpty && selection.selection.ids.isEmpty)
  #expect(!selection.isLoading)
  for _ in 0..<ConversationRecordSelection.maximumRecords { #expect(selection.add(UUID())) }
  #expect(!selection.add(UUID()))
  #expect(selection.failure != nil)
  let checkpoint = ConversationCheckpoint(draft: "Unsent", selectedRecords: selection.selection)
  let decoded = try JSONDecoder().decode(
    ConversationCheckpoint.self, from: JSONEncoder().encode(checkpoint))
  #expect(decoded.selectedRecords == selection.selection)
  #expect(decoded.draft == "Unsent")
  selection.canChange = { false }
  let before = selection.selection
  selection.remove(try #require(before.ids.first))
  #expect(selection.selection == before)
  selection.restore(.init())
  #expect(selection.failure == nil, "Restoring an empty selection must retire its old warning.")
  selection.stop()
  #expect(!selection.isLoading)
}

@Test @MainActor func acceptedProfileChangesDrainAfterViewCancellation() async throws {
  let repository = PersonalFactsProbe()
  let history = ChatHistory(configuration: .transient)
  history.restore(
    .init(
      handle: .init(companionID: "pogo", generation: UUID()), checkpoint: .init(),
      page: .init(entries: [], hasOlder: false, hasNewer: false)))
  let profile = ChatPersonalFacts(history: history, repository: repository)
  profile.begin()
  profile.topic = "name"
  profile.value = "Alex"
  let save = Task { await profile.save() }
  await repository.waitForWrite()
  #expect(profile.isSaving)
  save.cancel()
  profile.stop()
  let drained = Task { @MainActor in
    await withCheckedContinuation { continuation in
      profile.finish(deliver: { operation in Task { @MainActor in operation() } }) {
        continuation.resume()
      }
    }
  }
  await repository.release()
  await drained.value
  await save.value
  #expect(await repository.saved?.value == "Alex")
  #expect(!profile.isSaving)
  #expect(!profile.isEditing)
  #expect(profile.failure == nil)
  await profile.load()
  #expect(profile.facts.first?.fact.value == "Alex")
}

@Test @MainActor func persistenceShutdownAcceptsCommittedStateExactlyOnce() async throws {
  let operation = ChatPersistenceOperation<Int>()
  let gate = PersistenceGate()
  var accepted: [Int] = []
  let run = Task {
    try await operation.run(
      {
        await gate.wait()
        return 7
      }, accept: { accepted.append($0) })
  }
  await gate.waitForStart()
  let finish = Task { @MainActor in
    await withCheckedContinuation { continuation in
      operation.finish(deliver: { callback in Task { @MainActor in callback() } }) {
        continuation.resume()
      }
    }
  }
  await gate.release()
  await finish.value
  #expect(try await run.value == 7)
  #expect(accepted == [7])
  #expect(!operation.isRunning)
}

private actor SelectedMaterialProbe: ConversationMaterialProviding {
  private let gate = PersistenceGate()
  private var first = true
  func waitForRead() async { await gate.waitForStart() }
  func release() async { await gate.release() }
  func selectedRecords(_ selection: ConversationRecordSelection, query: String) async
    -> [ConversationRecordContext]
  {
    if first {
      first = false
      await gate.wait()
    }
    return selection.ids.map {
      .init(id: $0, title: "Synthetic item", source: nil, isComplete: false)
    }
  }
}

private actor PersonalFactsProbe: PersonalFactsRepository {
  private let gate = PersistenceGate()
  private(set) var saved: MemoryFact?
  func waitForWrite() async { await gate.waitForStart() }
  func release() async { await gate.release() }
  func personalFacts(_ handle: ConversationHandle) -> PersonalFactsSnapshot {
    .init(revision: UUID(), facts: saved.map { [.init(scope: .companion, fact: $0)] } ?? [])
  }
  func savePersonalFact(_ request: PersonalFactWrite) async -> PersonalFactsSnapshot {
    await gate.wait()
    saved = request.fact
    return personalFacts(request.handle)
  }
  func removePersonalFact(_ fact: PersonalFact, handle: ConversationHandle) -> PersonalFactsSnapshot
  {
    saved = nil
    return personalFacts(handle)
  }
}

private actor PersistenceGate {
  private var waiting: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  func wait() async {
    await withCheckedContinuation {
      waiting = $0
      observer?.resume()
      observer = nil
    }
  }
  func waitForStart() async {
    if waiting != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func release() {
    waiting?.resume()
    waiting = nil
  }
}
