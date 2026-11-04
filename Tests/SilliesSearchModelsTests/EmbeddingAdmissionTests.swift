import Foundation
import SilliesCore
import SilliesInference
import Testing

@testable import SilliesSearchModels

@Test func interactiveWorkBlocksIndexingButAllowsMemoryToolQueries() async throws {
  let activity = InferenceActivity()
  await activity.beginInteractiveWork()
  #expect(await !activity.claimEmbedding(UUID(), cancel: {}))
  let query = UUID()
  #expect(await activity.claimEmbedding(query, priority: .query, cancel: {}))
  await activity.releaseEmbedding(query)
  await activity.endInteractiveWork()
  let indexing = UUID()
  #expect(await activity.claimEmbedding(indexing, cancel: {}))
  await activity.releaseEmbedding(indexing)
}

@Test func speechPreemptsEmbeddingsAndWaitsForDrain() async throws {
  let activity = InferenceActivity()
  let id = UUID()
  let cancelled = AsyncStream<Void>.makeStream()
  #expect(await activity.claimEmbedding(id, cancel: { cancelled.continuation.yield(()) }))
  let speech = Task { await activity.beginSpeech() }
  for await _ in cancelled.stream { break }
  #expect(await !activity.claimEmbedding(UUID(), cancel: {}))
  await activity.releaseEmbedding(id)
  await speech.value
  #expect(await !activity.claimEmbedding(UUID(), cancel: {}))
  await activity.endSpeech()
  let resumed = UUID()
  #expect(await activity.claimEmbedding(resumed, cancel: {}))
  await activity.releaseEmbedding(resumed)
}

@Test func interactiveTextPreemptsEmbeddingBeforeClaimingGPU() async throws {
  let activity = InferenceActivity()
  let embedding = UUID()
  let text = UUID()
  let cancelled = AsyncStream<Void>.makeStream()
  #expect(await activity.claimEmbedding(embedding, cancel: { cancelled.continuation.yield(()) }))
  #expect(await !activity.claimText(text, cancel: {}))
  for await _ in cancelled.stream { break }
  await activity.releaseEmbedding(embedding)
  #expect(await activity.claimText(text, cancel: {}))
  #expect(await !activity.claimEmbedding(UUID(), cancel: {}))
  await activity.releaseText(text)
}

@Test func persistedVectorsRejectInvalidInputsAndDifferentSpaces() throws {
  let vector = try MemoryEmbedding(space: "model/revision/script", values: [3, 4])
  #expect(abs((vector.similarity(to: vector) ?? 0) - 1) < 0.0001)
  #expect(vector.similarity(to: try .init(space: "different", values: [3, 4])) == nil)
  for values: [Float] in [[], [0, 0], [.infinity], [.nan]] {
    #expect(throws: MemoryEmbeddingError.self) {
      try MemoryEmbedding(space: "model", values: values)
    }
  }
  #expect(throws: MemoryEmbeddingError.self) {
    try JSONDecoder().decode(
      MemoryEmbedding.self, from: Data(#"{"space":"model","values":[0,0]}"#.utf8))
  }
}

@Test func stoppingSearchOwnsAndDrainsPreparationWaitingForInteractiveInference() async throws {
  let activity = InferenceActivity()
  await activity.beginInteractiveWork()
  let session = EmbeddingWorkerSession(
    configuration: .init(provider: "apple", identity: "apple"),
    executable: URL(fileURLWithPath: "/unused-search-helper"),
    modelBytes: 512, activity: activity)
  let preparation = Task { try await session.access() }
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while await !session.isBusy, ContinuousClock.now < deadline { await Task.yield() }
  #expect(await session.isBusy)
  await session.stop()
  await #expect(throws: CancellationError.self) { try await preparation.value }
  // Search shutdown must not end another feature's interactive lease.
  #expect(await !activity.claimEmbedding(UUID(), cancel: {}))
  await activity.endInteractiveWork()
  let next = UUID()
  #expect(await activity.claimEmbedding(next, cancel: {}))
  await activity.releaseEmbedding(next)
}
