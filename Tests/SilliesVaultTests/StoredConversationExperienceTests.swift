import Foundation
import SilliesConversationTestSupport
import SilliesCore
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_STORED_HISTORY_DIRECTORY"] != nil))
func growingStoredHistoryKeepsRepliesPagingAndSearchBounded() async throws {
  let directory = URL(
    fileURLWithPath: try #require(
      ProcessInfo.processInfo.environment["SILLIES_STORED_HISTORY_DIRECTORY"]))
  let fixture = try StoredConversationFixture.load(at: directory)
  let store = ConversationLibrary(directory: directory)
  let restoreStarted = ContinuousClock.now
  let opened = try await store.open(StoredConversationFixture.owner)
  let restoreSeconds = ConversationScaleMetrics.seconds(restoreStarted.duration(to: .now))
  let initialCount = try #require(
    try await store.conversations().first { $0.id == opened.handle.companionID }?.messageCount)
  #expect(initialCount >= fixture.messageCount)
  let reads = ConversationReadProbe(store)
  let backend = ContinuityBackend()
  let service = LocalConversationService(
    resolveBackend: { backend }, tools: [], turns: .init(), history: .init(repository: reads))
  let memoryBefore = try ConversationScaleMetrics.residentBytes()
  let pulse = Task { await ConversationScaleMetrics.pulseMainActor() }
  defer { pulse.cancel() }
  var replies: [Double] = []
  let turns = 100
  for index in 0..<turns {
    let started = ContinuousClock.now
    let user = ChatMessage(
      role: .user, text: "New conversation turn \(index): growingneedle\(index)")
    try await store.save(
      .init(
        handle: opened.handle, messages: [user], checkpoint: .init(draft: "Continuing"),
        savedAt: .now))
    let context = ChatContext(
      companionName: "Pogo", profile: .init(personality: "Curious"), messages: [user]
    ).inHistory(opened.handle)
    let answer = try await service.reply(to: context)
    #expect(answer.text == "Ready to continue.")
    try await store.save(
      .init(
        handle: opened.handle, messages: [.init(role: .companion, text: answer.text)],
        checkpoint: .init(), savedAt: .now))
    replies.append(ConversationScaleMetrics.seconds(started.duration(to: .now)))
  }
  #expect(await reads.pageReads == turns)
  #expect(await reads.checkpointReads == turns)
  #expect(await backend.summaryCalls == 0)
  #expect(await backend.measurements <= turns * 10)
  #expect(await reads.maximumPageMessages <= backend.conversationPolicy.history.recent.messageLimit)
  let pages = try await pageOlderHistory(store, handle: opened.handle)
  let searches = try await searchStoredHistory(store, fixture: fixture)
  let count = try await store.conversations().first { $0.id == opened.handle.companionID }?
    .messageCount
  #expect(count == initialCount + turns * 2)
  #expect(try await store.checkpoint(opened.handle).memory == fixture.memory)
  pulse.cancel()
  let mainDelay = await pulse.value
  let after = try ConversationScaleMetrics.residentBytes()
  let growth = after > memoryBefore ? after - memoryBefore : 0
  #expect(growth < 64 * 1_024 * 1_024)
  #expect(mainDelay < 0.1)
  #expect(ConversationScaleMetrics.percentile(replies, fraction: 0.95) < 0.1)
  print(
    "STORED HISTORY \(fixture.messageCount): 100 growing turns from \(initialCount) messages; restore=\(restoreSeconds)s; reply p50=\(ConversationScaleMetrics.percentile(replies, fraction: 0.5))s p95=\(ConversationScaleMetrics.percentile(replies, fraction: 0.95))s; older page max=\(pages)s; main actor max=\(mainDelay)s; RSS delta=\(growth); search seconds=\(searches)"
  )
}

private func pageOlderHistory(_ store: ConversationLibrary, handle: ConversationHandle) async throws
  -> Double
{
  var position = ConversationPageRequest.Position.latest
  var boundary = Int64.max
  var seen: Set<UUID> = []
  var maximum = 0.0
  for _ in 0..<100 {
    let began = ContinuousClock.now
    let page = try await store.page(.init(handle: handle, position: position))
    maximum = max(maximum, ConversationScaleMetrics.seconds(began.duration(to: .now)))
    #expect(page.entries.count <= ConversationPageRequest.defaultLimit)
    let first = try #require(page.entries.first)
    #expect(page.entries.allSatisfy { $0.sequence < boundary && seen.insert($0.id).inserted })
    boundary = first.sequence
    position = .before(boundary)
  }
  #expect(maximum < 0.1)
  return maximum
}

private func searchStoredHistory(_ store: ConversationLibrary, fixture: StoredConversationFixture)
  async throws -> [String: Double]
{
  var timings: [String: Double] = [:]
  for index in [0, fixture.messageCount / 2, fixture.messageCount - 1] {
    let query = "historyneedle\(index)"
    let began = ContinuousClock.now
    let found = try await store.search(.init(companionID: fixture.handle.companionID, query: query))
    timings[query] = ConversationScaleMetrics.seconds(began.duration(to: .now))
    #expect(found.count == 1)
    #expect(found.first?.entry.message.text.contains(query) == true)
  }
  for query in ["project", "résumé", "absentuniquehistoryterm"] {
    let began = ContinuousClock.now
    let found = try await store.search(.init(companionID: fixture.handle.companionID, query: query))
    timings[query] = ConversationScaleMetrics.seconds(began.duration(to: .now))
    #expect(found.count <= 20)
    if query == "absentuniquehistoryterm" {
      #expect(found.isEmpty)
    } else {
      #expect(!found.isEmpty)
    }
  }
  #expect(timings.values.allSatisfy { $0 < 2 })
  return timings
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_RECOVERY_DIRECTORY"] != nil))
func killedWriterRestoresCommittedChatAndRollsBackPartialBodyAndIndexChanges() async throws {
  let directory = URL(
    fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SILLIES_RECOVERY_DIRECTORY"])
  )
  let fixture = try StoredConversationFixture.load(at: directory)
  let committed = try ConversationRecoveryFixture.load(at: directory)
  let store = ConversationLibrary(directory: directory)
  let opened = try await store.open(StoredConversationFixture.owner)
  #expect(opened.handle == fixture.handle)
  #expect(opened.checkpoint.memory == fixture.memory)
  #expect(opened.checkpoint.draft == committed.draft)
  #expect(opened.checkpoint.language == "fr")
  #expect(opened.checkpoint.readingMessageID == committed.readingMessageID)
  #expect(opened.page.entries.contains { $0.message == committed.user })
  let reply = try #require(opened.page.entries.first { $0.id == committed.reply.id }?.message)
  #expect(reply.text == committed.reply.text)
  #expect(reply.completion == .interrupted)
  #expect(reply.spokenText == committed.reply.spokenText)
  let earliest = try await store.page(
    .init(handle: opened.handle, position: .around(fixture.landmarks[0].id), limit: 1))
  #expect(earliest.entries.first?.message == fixture.landmarks[0])
  let found = try await store.search(
    .init(companionID: opened.handle.companionID, query: "historyneedle0"))
  #expect(found.first?.entry.id == fixture.landmarks[0].id)
  #expect(
    try await store.search(
      .init(companionID: opened.handle.companionID, query: "uncommittedneedle")
    ).isEmpty)
  let next = ChatMessage(role: .user, text: "Successfully resumed: recoveryresumedneedle")
  try await store.save(
    .init(handle: opened.handle, messages: [next], checkpoint: opened.checkpoint, savedAt: .now))
  #expect(
    try await store.search(
      .init(companionID: opened.handle.companionID, query: "recoveryresumedneedle")
    ).first?.entry.id == next.id)
  print(
    "RECOVERY VERIFIED: committed messages, interrupted reply, spoken prefix, draft, reading position, checkpoint, original body/search index and a fresh write."
  )
}
