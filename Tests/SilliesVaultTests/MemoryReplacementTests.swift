import Foundation
import SilliesCore
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

@Test func memoryReplacementPreservesIdentityAndRejectsStaleOrDeletedTargets() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let update = fixture.update.replacing(fixture.original.saved.reference)
  let changed = try await fixture.store.remember(update)
  let memories = try await fixture.store.memories(
    .init(handle: fixture.handle, text: "", limit: CompanionMemoryQuery.maximumResults))
  #expect(memories.count == 1)
  #expect(changed.saved.id == fixture.original.saved.id)
  #expect(changed.saved.key == "name")
  #expect(changed.saved.value == "Sam")
  #expect(changed.saved.sourceMessageID == fixture.correction.id)
  #expect(changed.saved.revision != fixture.original.saved.revision)
  await #expect(throws: MemoryMutationError.self) { try await fixture.store.remember(update) }
  #expect(try await fixture.store.recentMemoryChanges(fixture.handle).count == 2)

  let undone = try await fixture.store.undoMemory(fixture.handle, receiptID: changed.id)
  let restored = try #require(
    try await fixture.store.memories(
      .init(handle: undone.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).first)
  #expect(restored == fixture.original.saved)
  let forgotten = try await fixture.store.forget(undone.handle, id: restored.id)
  let late = MemoryWrite(
    handle: forgotten.handle, fact: fixture.update.fact, source: fixture.update.source,
    savedAt: fixture.update.savedAt
  ).replacing(restored.reference)
  await #expect(throws: MemoryMutationError.self) { try await fixture.store.remember(late) }
  #expect(
    try await fixture.store.memories(
      .init(handle: forgotten.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).isEmpty)
  #expect(try await fixture.store.recentMemoryChanges(forgotten.handle).isEmpty)
}

@Test func memoryReplacementToolRequiresValidPairedReferencesAndCompanionOwnership() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let tool = MemorySaveTool(
    repository: fixture.store, handle: fixture.handle, statement: fixture.correction)
  for reference in [
    ["memoryID": "invalid", "revision": "invalid"],
    ["memoryID": fixture.original.saved.id.uuidString],
    ["revision": fixture.original.saved.revision.uuidString],
  ] {
    var args = reference
    args["key"] = "user_name"
    args["value"] = "Sam"
    let result = try await tool.call(arguments: JSONEncoder().encode(args))
    #expect(result.memoryReceipt == nil)
    #expect(
      try await fixture.store.memories(
        .init(handle: fixture.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
      ).first?.value == "Alex")
  }
  let arguments = try JSONEncoder().encode([
    "key": "user_name", "value": "Sam", "memoryID": fixture.original.saved.id.uuidString,
    "revision": fixture.original.saved.revision.uuidString,
  ])
  let other = try await fixture.store.open(.init(id: "bolt", name: "Bolt"))
  let otherStatement = ChatMessage(role: .user, text: fixture.correction.text)
  try await fixture.store.save(
    .init(handle: other.handle, messages: [otherStatement], checkpoint: .init(), savedAt: Date()))
  let foreign = MemorySaveTool(
    repository: fixture.store, handle: other.handle, statement: otherStatement)
  #expect(try await foreign.call(arguments: arguments).memoryReceipt == nil)
  #expect(
    try await fixture.store.memories(
      .init(handle: other.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).isEmpty)
  let result = try await tool.call(arguments: arguments)
  #expect(result.memoryReceipt?.saved.key == "name")
  #expect(result.memoryReceipt?.saved.value == "Sam")
  #expect(
    try await fixture.store.memories(
      .init(handle: fixture.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).count == 1)
}

@Test func memoryWriteAcknowledgementsDescribeTheCommittedIdentityAndCanonicalFact() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let tool = MemorySaveTool(
    repository: fixture.store, handle: fixture.handle, statement: fixture.correction)
  let output = try await tool.call(
    arguments: JSONEncoder().encode([
      "key": "different_topic", "value": "Sam", "memoryID": fixture.original.saved.id.uuidString,
      "revision": fixture.original.saved.revision.uuidString,
    ]))
  let committed = try #require(
    try await fixture.store.memories(
      .init(handle: fixture.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).first)
  let response = try JSONDecoder().decode(
    MemoryWriteAcknowledgement.self, from: Data(output.text.utf8))
  #expect(response.status == "saved")
  #expect(response.reason == nil)
  #expect(response.memory?.memoryID == committed.id)
  #expect(response.memory?.revision == committed.revision)
  #expect(response.memory?.key == committed.key)
  #expect(response.memory?.value == committed.value)
  #expect(committed.key == fixture.original.saved.key)
  #expect(output.memoryReceipt?.saved == committed)
  let brief = try JSONDecoder().decode(
    MemoryWriteAcknowledgement.self, from: Data(output.briefText.utf8))
  #expect(brief.status == "saved")
  #expect(brief.reason == nil)
  #expect(brief.memory == nil)
}

@Test func refusedMemoryCorrectionsAcknowledgeNoWriteAndKeepTheOriginal() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let tool = MemorySaveTool(
    repository: fixture.store, handle: fixture.handle, statement: fixture.correction)
  for (reference, reason) in [
    (["memoryID": fixture.original.saved.id.uuidString], "invalidReplacementReference"),
    (["memoryID": UUID().uuidString, "revision": UUID().uuidString], "replacementChanged"),
  ] {
    var arguments = reference
    arguments["key"] = "name"
    arguments["value"] = "Sam"
    let output = try await tool.call(arguments: JSONEncoder().encode(arguments))
    let response = try JSONDecoder().decode(
      MemoryWriteAcknowledgement.self, from: Data(output.text.utf8))
    #expect(response.status == "notSaved")
    #expect(response.reason == reason)
    #expect(response.memory == nil)
    #expect(output.memoryReceipt == nil)
  }
  let memories = try await fixture.store.memories(
    .init(handle: fixture.handle, text: "", limit: CompanionMemoryQuery.maximumResults))
  #expect(memories == [fixture.original.saved])
  #expect(try await fixture.store.recentMemoryChanges(fixture.handle).count == 1)
}

private struct MemoryWriteAcknowledgement: Decodable {
  struct Memory: Decodable, Equatable {
    let memoryID: UUID
    let revision: UUID
    let key: String
    let value: String
  }
  let status: String
  let memory: Memory?
  let reason: String?
}

@Test func aSmallEvidenceBudgetKeepsTheSaveAcknowledgementWithoutRepeatingTheWrite() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let tool = MemorySaveTool(
    repository: fixture.store, handle: fixture.handle, statement: fixture.correction)
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  try await toolbox.configure(
    evidence: .init(totalTokens: 80, resultTokens: 80, measure: { $0.utf8.count }), maximumCalls: 4)
  let call = ConversationToolCall(
    id: "correct-name", name: "save_memory",
    arguments: try JSONEncoder().encode([
      "key": "name", "value": "Sam", "memoryID": fixture.original.saved.id.uuidString,
      "revision": fixture.original.saved.revision.uuidString,
    ]))
  let answer = try await toolbox.invoke(call)
  let response = try JSONDecoder().decode(MemoryWriteAcknowledgement.self, from: Data(answer.utf8))
  #expect(response.status == "saved")
  #expect(response.memory == nil)
  #expect(
    try await fixture.store.memories(
      .init(handle: fixture.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).first?.value == "Sam")
  try await toolbox.beginRecovery()
  #expect(try await toolbox.invoke(call) == answer)
  #expect(try await fixture.store.recentMemoryChanges(fixture.handle).count == 2)
}

private struct MemoryReplacementFixture {
  let directory: URL
  let store: ConversationLibrary
  let handle: ConversationHandle
  let correction: ChatMessage
  let original: MemoryReceipt
  let update: MemoryWrite

  init() async throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    store = ConversationLibrary(directory: directory)
    handle = try await store.open(.init(id: "pogo", name: "Pogo")).handle
    let first = ChatMessage(role: .user, text: "My name is Alex.")
    correction = ChatMessage(role: .user, text: "Please call me Sam instead.")
    try await store.save(
      .init(handle: handle, messages: [first, correction], checkpoint: .init(), savedAt: Date()))
    original = try await store.remember(
      .init(
        handle: handle, fact: .init(key: "name", value: "Alex"),
        source: .init(messageID: first.id, quote: first.text), savedAt: Date()))
    update = .init(
      handle: handle, fact: .init(key: "user_name", value: "Sam"),
      source: .init(messageID: correction.id, quote: correction.text), savedAt: Date())
  }

  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}

@Test func explicitCorrectionPreservesProvenanceInvalidatesOldContextAndSurvivesReopen()
  async throws
{
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let edited = try await fixture.store.correctMemory(
    .init(
      handle: fixture.handle, target: fixture.original.saved.reference,
      value: "Riley", savedAt: Date()))
  #expect(edited.receipt.saved.id == fixture.original.saved.id)
  #expect(edited.receipt.saved.sourceQuote == fixture.original.saved.sourceQuote)
  #expect(edited.receipt.saved.source.attribution == .userCorrection)
  #expect(edited.snapshot.handle != fixture.handle)
  #expect(edited.snapshot.checkpoint.memory.summary.isEmpty)
  await #expect(throws: ConversationStorageError.self) {
    try await fixture.store.save(
      .init(handle: fixture.handle, messages: [], checkpoint: .init(), savedAt: Date()))
  }
  await #expect(throws: MemoryMutationError.self) {
    try await fixture.store.correctMemory(
      .init(
        handle: edited.snapshot.handle, target: fixture.original.saved.reference,
        value: "Stale editor", savedAt: Date()))
  }
  let reopened = ConversationLibrary(directory: fixture.directory)
  let handle = try await reopened.open(.init(id: "pogo", name: "Pogo")).handle
  #expect(
    try await reopened.memories(.init(handle: handle, text: "Riley")).first == edited.receipt.saved)
  #expect(try await reopened.memories(.init(handle: handle, text: "Alex")).isEmpty)
  let tool = MemorySearchTool(repository: reopened, handle: handle, companionName: "Pogo")
  let result = try await tool.call(arguments: Data(#"{"query":"name"}"#.utf8))
  #expect(result.text.contains("edited_by_user") && result.text.contains("Riley"))
  #expect(!result.text.contains("My name is Alex"))
  let undone = try await reopened.undoMemory(handle, receiptID: edited.receipt.id)
  #expect(
    try await reopened.memories(.init(handle: undone.handle, text: "Alex")).first
      == fixture.original.saved)
  #expect(try await reopened.memories(.init(handle: undone.handle, text: "Riley")).isEmpty)
}

@Test func automaticMemoryWritesCannotForgeAnExplicitUserCorrection() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  await #expect(throws: ConversationStorageError.self) {
    try await fixture.store.remember(
      .init(
        handle: fixture.handle, fact: .init(key: "name", value: "Forged"),
        source: fixture.original.saved.source.correctedByUser(), savedAt: Date()
      )
      .replacing(fixture.original.saved.reference))
  }
  await #expect(throws: ConversationStorageError.self) {
    try await fixture.store.correctMemory(
      .init(
        handle: fixture.handle, target: fixture.original.saved.reference, value: " ",
        savedAt: Date()))
  }
  #expect(
    try await fixture.store.memories(.init(handle: fixture.handle, text: "")).first
      == fixture.original.saved)
  #expect(try await fixture.store.recentMemoryChanges(fixture.handle) == [fixture.original])
}

@Test func memoryCreationCannotOverwriteAStoredTopicOrItsProvenance() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let tool = MemorySaveTool(
    repository: fixture.store, handle: fixture.handle, statement: fixture.correction)
  for value in ["Alex", "Sam"] {
    let output = try await tool.call(
      arguments: JSONEncoder().encode(["key": " Name ", "value": value]))
    let acknowledgement = try JSONDecoder().decode(
      MemoryWriteAcknowledgement.self, from: Data(output.text.utf8))
    #expect(acknowledgement.status == "notSaved")
    #expect(acknowledgement.reason == "keyAlreadyExists")
    #expect(output.memoryReceipt == nil)
    #expect(output.text.contains("search") || output.text.contains("Search"))
  }
  #expect(
    try await fixture.store.memories(.init(handle: fixture.handle, text: ""))
      == [fixture.original.saved])
  #expect(try await fixture.store.recentMemoryChanges(fixture.handle) == [fixture.original])
}

@Test func competingMemoryCorrectionsCommitOnlyOneRevision() async throws {
  let fixture = try await MemoryReplacementFixture()
  defer { fixture.remove() }
  let write = fixture.update.replacing(fixture.original.saved.reference)
  let successes = await withTaskGroup(of: Bool.self) { group in
    for _ in 0..<2 {
      group.addTask {
        do {
          _ = try await fixture.store.remember(write)
          return true
        } catch MemoryMutationError.replacementChanged {
          return false
        } catch {
          Issue.record(error)
          return false
        }
      }
    }
    var committed = 0
    for await succeeded in group { if succeeded { committed += 1 } }
    return committed
  }
  #expect(successes == 1)
  #expect(try await fixture.store.recentMemoryChanges(fixture.handle).count == 2)
}
