import Darwin
import Foundation
import SilliesCore
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

@Test func largeArchiveKeepsReplyReadsMemoryAndMainActorWorkBounded() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(10_000, in: store)
  let context = try await fixture.question("Continue", handle: handle, store: store)
  let reads = ConversationReadProbe(store)
  let backend = ContinuityBackend()
  let service = LocalConversationService(
    resolveBackend: { backend }, tools: [], turns: .init(),
    history: .init(repository: reads))
  let residentBefore = try residentBytes()
  var latencies: [Duration] = []
  var mainActorLatencies: [Duration] = []
  for _ in 0..<50 {
    let start = ContinuousClock.now
    async let reply = service.reply(to: context)
    let pulse = ContinuousClock.now
    await MainActor.run {}
    mainActorLatencies.append(pulse.duration(to: .now))
    #expect(try await reply.text == "Ready to continue.")
    latencies.append(start.duration(to: .now))
  }
  let residentAfter = try residentBytes()
  #expect(await reads.pageReads == 50)
  #expect(await reads.checkpointReads == 50)
  #expect(await reads.maximumPageMessages <= backend.conversationPolicy.history.recent.messageLimit)
  #expect(
    await reads.maximumPageBytes <= backend.conversationPolicy.history.recent.byteLimit
      + backend.conversationPolicy.history.recent.messageLimit + 1)
  #expect(await backend.summaryCalls == 0)
  #expect(await backend.measurements <= 50 * 10)
  #expect(try await store.conversations().first?.messageCount == 10_001)
  let historical = try await store.search(.init(companionID: "pogo", query: "0"))
  #expect(historical.first?.entry.message.text == "Archived discussion 0.")
  let megabyte: UInt64 = 1_024 * 1_024
  let growth = residentAfter > residentBefore ? residentAfter - residentBefore : 0
  #expect(growth < 32 * megabyte)
  let maximumMainActorDelay = try #require(mainActorLatencies.max())
  #expect(maximumMainActorDelay < .milliseconds(100))
  print(
    "CONTINUITY SCALE: 10001 records, 50 replies; reply p50=\(percentile(latencies, fraction: 0.5)), p95=\(percentile(latencies, fraction: 0.95)); main actor max=\(maximumMainActorDelay); resident delta=\(growth) bytes; max page=\(await reads.maximumPageBytes) bytes"
  )
}

@Test func byteBoundedPagesPreserveCursorProgressWithOversizedRecords() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(20, in: store)
  let large = ChatMessage(role: .user, text: String(repeating: "source ", count: 20_000))
  try await store.save(.init(handle: handle, messages: [large], checkpoint: .init(), savedAt: .now))
  let latest = try await store.page(.init(handle: handle, maximumBytes: 1_024))
  #expect(latest.entries.map(\.id) == [large.id])
  #expect(latest.hasOlder)
  let older = try await store.page(
    .init(handle: handle, position: .beforeMessage(large.id), maximumBytes: 1_024))
  #expect(!older.entries.isEmpty)
  #expect(try JSONEncoder().encode(older.entries.map(\.message)).count < 1_100)
  #expect(!older.entries.contains { $0.id == large.id })
}

private func residentBytes() throws -> UInt64 {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(
    MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
  let status = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  guard status == KERN_SUCCESS else { throw ConversationStorageError.invalidData }
  return info.resident_size
}

private func percentile(_ samples: [Duration], fraction: Double) -> Duration {
  let sorted = samples.sorted()
  let index = max(0, Int((Double(sorted.count) * fraction).rounded(.up)) - 1)
  return sorted[index]
}
