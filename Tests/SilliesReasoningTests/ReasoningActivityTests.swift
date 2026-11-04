import Foundation
import Testing

@testable import SilliesReasoning

@Test func cancellingInteractiveAdmissionBalancesActivityAndReleasesTheGate() async throws {
  let began = AsyncStream<Void>.makeStream()
  let blocked = AsyncStream<Void>.makeStream()
  let ended = AsyncStream<Void>.makeStream()
  let gate = ReasoningTurnGate { event in
    switch event {
    case .began:
      began.continuation.yield(())
      for await _ in blocked.stream { break }
    case .ended: ended.continuation.yield(())
    }
  }
  let task = Task { try await gate.acquire(.interactive) }
  for await _ in began.stream { break }
  task.cancel()
  await #expect(throws: CancellationError.self) { try await task.value }
  for await _ in ended.stream { break }
  #expect(await gate.tryAcquire())
  await gate.release()
}
