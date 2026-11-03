import Foundation
import SilliesConversationTestSupport
import SilliesCore
import Synchronization
import Testing

@testable import SilliesVault

@Test func conversationSearchReaderObservesCommitsAndClearWithoutReopening() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(2, in: store)
  #expect(try await store.search(.init(query: "discussion")).count == 2)
  let message = ChatMessage(role: .user, text: "A newly committed searchable statement")
  try await store.save(
    .init(handle: handle, messages: [message], checkpoint: .init(), savedAt: .now))
  #expect(try await store.search(.init(query: "searchable")).first?.id == message.id)
  _ = try await store.clear(handle)
  #expect(try await store.search(.init(query: "searchable")).isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_STORED_HISTORY_DIRECTORY"] != nil))
func broadConversationSearchYieldsToWritesAndCancellation() async throws {
  let directory = URL(
    fileURLWithPath: try #require(
      ProcessInfo.processInfo.environment["SILLIES_STORED_HISTORY_DIRECTORY"]))
  let fixture = try StoredConversationFixture.load(at: directory)
  let store = ConversationLibrary(directory: directory)
  let snapshot = try await store.open(StoredConversationFixture.owner)
  let finished = Mutex(false)
  let search = Task {
    defer { finished.withLock { $0 = true } }
    return try await store.search(.init(companionID: fixture.handle.companionID, query: "project"))
  }
  defer { search.cancel() }
  // The opt-in million-message query runs for seconds. Allow it to enter SQLite before the write.
  try await Task.sleep(for: .milliseconds(50))
  #expect(!finished.withLock { $0 })
  let message = ChatMessage(role: .user, text: "Concurrent search isolation check")
  let writeStarted = ContinuousClock.now
  try await store.save(
    .init(
      handle: snapshot.handle, messages: [message], checkpoint: snapshot.checkpoint, savedAt: .now))
  let page = try await store.page(.init(handle: snapshot.handle))
  #expect(page.entries.last?.id == message.id)
  let foregroundDuration = writeStarted.duration(to: .now)
  #expect(!finished.withLock { $0 })
  #expect(foregroundDuration < .milliseconds(100))
  let cancelled = ContinuousClock.now
  search.cancel()
  await #expect(throws: CancellationError.self) { try await search.value }
  let cancellationDuration = cancelled.duration(to: .now)
  #expect(cancellationDuration < .milliseconds(250))
  let subsequent = try await store.search(.init(query: "historyneedle0"))
  #expect(subsequent.first?.id == fixture.landmarks.first?.id)
  print(
    "SEARCH ISOLATION \(fixture.messageCount): write+page=\(foregroundDuration); cancellation=\(cancellationDuration); subsequent search verified"
  )
}
