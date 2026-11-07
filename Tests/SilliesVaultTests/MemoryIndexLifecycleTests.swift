import Foundation
import SilliesCore
import Testing

@testable import SilliesVault

@Test func semanticDeadlineCancelsAndDrainsSlowWork() async throws {
  let stopped = AsyncStream<Void>.makeStream()
  let blocked = AsyncStream<Void>.makeStream()
  await #expect(throws: SemanticSearchDeadline.Failure.self) {
    try await SemanticSearchDeadline.perform {
      defer { stopped.continuation.yield(()) }
      for await _ in blocked.stream { break }
      try Task.checkCancellation()
      return [CompanionMemory]()
    }
  }
  for await _ in stopped.stream { break }
}

@Test func stoppingMemoryIndexCancelsItsProducerAndKeepsKeywordSearch() async throws {
  let fixture = MemoryIndexFixture()
  defer { fixture.remove() }
  let handle = try await fixture.seed()
  let started = AsyncStream<Void>.makeStream()
  let blocked = AsyncStream<Void>.makeStream()
  try await fixture.library.useSearchEmbeddings(
    .init(identity: "blocked") { _ in
      started.continuation.yield(())
      for await _ in blocked.stream { break }
      try Task.checkCancellation()
      return nil
    })
  for await _ in started.stream { break }
  try await fixture.library.useSearchEmbeddings(nil)
  let status = try await fixture.library.memoryIndexStatus()
  #expect(status.0 == nil)
  #expect(try await fixture.library.memories(.init(handle: handle, text: "bicycle")).count == 1)
}

@Test func replacingEmbeddingProviderCannotPublishThePreviousProvidersWork() async throws {
  let fixture = MemoryIndexFixture()
  defer { fixture.remove() }
  let handle = try await fixture.seed()
  let first = AsyncStream<Void>.makeStream()
  let blocked = AsyncStream<Void>.makeStream()
  try await fixture.library.useSearchEmbeddings(
    .init(identity: "old") { _ in
      first.continuation.yield(())
      for await _ in blocked.stream { break }
      try Task.checkCancellation()
      return try .init(space: "old", values: [1, 0])
    })
  for await _ in first.stream { break }
  try await fixture.library.useSearchEmbeddings(
    .init(identity: "new") { _ in
      try .init(space: "new", values: [0, 1])
    })
  try await fixture.waitUntilIndexed()
  let result = try await fixture.library.memories(.init(handle: handle, text: "transport"))
  #expect(result.map(\.key) == ["commute"])
  try await fixture.library.useSearchEmbeddings(nil)
}

@Test func failedEmbeddingPreparationKeepsTheArchiveAndKeywordResults() async throws {
  let fixture = MemoryIndexFixture()
  defer { fixture.remove() }
  let handle = try await fixture.seed()
  try await fixture.library.useSearchEmbeddings(
    .init(identity: "failed") { _ in
      throw SearchEmbeddingError.unavailable
    })
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while try await fixture.library.memoryIndexStatus().1 == nil, ContinuousClock.now < deadline {
    await Task.yield()
  }
  #expect(try await fixture.library.memoryIndexStatus().1 != nil)
  #expect(try await fixture.library.memories(.init(handle: handle, text: "bicycle")).count == 1)
  try await fixture.library.useSearchEmbeddings(nil)
}

private struct MemoryIndexFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var library: ConversationLibrary { owner }
  private let owner: ConversationLibrary
  init() { owner = ConversationLibrary(directory: directory) }
  func seed() async throws -> ConversationHandle {
    let handle = try await library.open(.init(id: "pogo", name: "Pogo")).handle
    let source = ChatMessage(role: .user, text: "I ride a bicycle to work.")
    try await library.save(
      .init(handle: handle, messages: [source], checkpoint: .init(), savedAt: Date()))
    _ = try await library.remember(
      .init(
        handle: handle,
        fact: .init(key: "commute", value: source.text),
        source: .init(messageID: source.id, quote: source.text), savedAt: Date()))
    return handle
  }
  func waitUntilIndexed() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
      if let progress = try await library.memoryIndexStatus().0,
        progress.processed == progress.total
      {
        return
      }
      await Task.yield()
    }
    throw SearchEmbeddingError.unavailable
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}

@Test func overlappingProviderChangesKeepOnlyTheLatestOwner() async throws {
  let fixture = MemoryIndexFixture()
  defer { fixture.remove() }
  _ = try await fixture.seed()
  let release = MemoryIndexSuspension()
  let started = AsyncStream<Void>.makeStream()
  let cancelled = AsyncStream<Void>.makeStream()
  try await fixture.library.useSearchEmbeddings(
    .init(identity: "old") { _ in
      await withTaskCancellationHandler {
        await release.wait(started: started.continuation)
      } onCancel: {
        cancelled.continuation.yield(())
      }
      try Task.checkCancellation()
      return nil
    })
  for await _ in started.stream { break }
  let first = Task {
    try await fixture.library.useSearchEmbeddings(
      .init(identity: "superseded") { _ in
        Issue.record("An obsolete selection started indexing")
        return nil
      })
  }
  for await _ in cancelled.stream { break }
  let previousOwner = await fixture.library.memoryIndexGeneration
  let second = Task {
    try await fixture.library.useSearchEmbeddings(
      .init(identity: "latest") { _ in try .init(space: "latest", values: [1, 0]) })
  }
  // Observe admission only to make the race deterministic; assert the resulting index below.
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while await fixture.library.memoryIndexGeneration == previousOwner,
    ContinuousClock.now < deadline
  {
    await Task.yield()
  }
  #expect(await fixture.library.memoryIndexGeneration != previousOwner)
  await release.resume()
  try await first.value
  try await second.value
  try await fixture.waitUntilIndexed()
  let status = try await fixture.library.memoryIndexStatus()
  #expect(status.0?.searchable == 1)
  try await fixture.library.useSearchEmbeddings(nil)
}

private actor MemoryIndexSuspension {
  private var continuation: CheckedContinuation<Void, Never>?
  func wait(started: AsyncStream<Void>.Continuation) async {
    await withCheckedContinuation {
      continuation = $0
      started.yield(())
    }
  }
  func resume() {
    continuation?.resume()
    continuation = nil
  }
}
