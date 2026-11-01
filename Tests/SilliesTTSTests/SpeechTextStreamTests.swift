import Foundation
import SilliesTTS
import Testing

@Test func speechTextStreamDrainsInOrderAfterProducerFinishes() async throws {
  let stream = SpeechTextStream()
  try await stream.append("First phrase.")
  try await stream.append("Second phrase.")
  await stream.finish()
  #expect(try await stream.next() == "First phrase.")
  #expect(try await stream.next() == "Second phrase.")
  #expect(try await stream.next() == nil)
  await #expect(throws: TTSError.self) { try await stream.append("Late") }
}

@Test func cancellingSpeechConsumerReleasesSuspendedReadAndDiscardsQueuedWork() async throws {
  let stream = SpeechTextStream()
  let reader = Task { try await stream.next() }
  reader.cancel()
  await #expect(throws: CancellationError.self) { try await reader.value }
  await stream.cancel()
  await #expect(throws: CancellationError.self) { try await stream.append("Late") }
  await #expect(throws: CancellationError.self) { try await stream.next() }
}

@Test func speechQueueBoundsTotalReplyEvenIfConsumerKeepsUp() async throws {
  let stream = SpeechTextStream()
  for _ in 0..<8 {
    try await stream.append(String(repeating: "x", count: 500))
    #expect(try await stream.next()?.count == 500)
  }
  await #expect(throws: TTSError.self) { try await stream.append("Overflow") }
  await stream.finish()
  #expect(try await stream.next() == nil)
}

@Test func finishingSpeechStreamUnblocksAWaitingConsumer() async throws {
  let stream = SpeechTextStream()
  let reader = Task { try await stream.next() }
  await stream.finish()
  #expect(try await reader.value == nil)
}
