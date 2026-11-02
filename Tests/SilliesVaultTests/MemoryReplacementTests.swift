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
  let memories = try await fixture.store.memories(fixture.handle, query: "")
  #expect(memories.count == 1)
  #expect(changed.saved.id == fixture.original.saved.id)
  #expect(changed.saved.key == "name")
  #expect(changed.saved.value == "Sam")
  #expect(changed.saved.sourceMessageID == fixture.correction.id)
  #expect(changed.saved.revision != fixture.original.saved.revision)
  await #expect(throws: MemoryMutationError.self) { try await fixture.store.remember(update) }
  #expect(try await fixture.store.recentMemoryChanges(fixture.handle).count == 2)

  let undone = try await fixture.store.undoMemory(fixture.handle, receiptID: changed.id)
  let restored = try #require(try await fixture.store.memories(undone.handle, query: "").first)
  #expect(restored == fixture.original.saved)
  let forgotten = try await fixture.store.forget(undone.handle, id: restored.id)
  let late = MemoryWrite(
    handle: forgotten.handle, fact: fixture.update.fact, source: fixture.update.source,
    savedAt: fixture.update.savedAt
  ).replacing(restored.reference)
  await #expect(throws: MemoryMutationError.self) { try await fixture.store.remember(late) }
  #expect(try await fixture.store.memories(forgotten.handle, query: "").isEmpty)
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
    #expect(try await fixture.store.memories(fixture.handle, query: "").first?.value == "Alex")
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
  #expect(try await fixture.store.memories(other.handle, query: "").isEmpty)
  let result = try await tool.call(arguments: arguments)
  #expect(result.memoryReceipt?.saved.key == "name")
  #expect(result.memoryReceipt?.saved.value == "Sam")
  #expect(try await fixture.store.memories(fixture.handle, query: "").count == 1)
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
