import SilliesCore
import Testing

@testable import SilliesSearchModels

@Test func sharedIndexAdmissionRejectsInteractiveQueueingAndReleasesCancelledWaiters() async throws
{
  let admission = EmbeddingAdmission()
  try await admission.acquire(.passage)
  await #expect(throws: SearchEmbeddingError.self) { try await admission.acquire(.query) }
  let waiting = Task { try await admission.acquire(.passage) }
  try await waitForQueuedPassage(admission)
  waiting.cancel()
  await #expect(throws: CancellationError.self) { try await waiting.value }
  #expect(await admission.pendingPassages == 0)
  await admission.release()
  try await admission.acquire(.query)
  await admission.release()
}

@Test func sharedEmbeddingShutdownRejectsAllNewWork() async throws {
  let admission = EmbeddingAdmission()
  try await admission.acquire(.passage)
  let waiting = Task { try await admission.acquire(.passage) }
  try await waitForQueuedPassage(admission)
  await admission.stop()
  await #expect(throws: CancellationError.self) { try await waiting.value }
  await admission.release()
  await #expect(throws: CancellationError.self) { try await admission.acquire(.query) }
  await #expect(throws: CancellationError.self) { try await admission.acquire(.passage) }
}

@Test func sharedIndexAdmissionTransfersOwnershipBeforeAcceptingAnotherQuery() async throws {
  let admission = EmbeddingAdmission()
  try await admission.acquire(.passage)
  let waiting = Task { try await admission.acquire(.passage) }
  try await waitForQueuedPassage(admission)
  await admission.release()
  try await waiting.value
  #expect(await admission.pendingPassages == 0)
  await #expect(throws: SearchEmbeddingError.self) { try await admission.acquire(.query) }
  await admission.release()
  try await admission.acquire(.query)
  await admission.release()
}

private func waitForQueuedPassage(_ admission: EmbeddingAdmission) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while await admission.pendingPassages == 0, ContinuousClock.now < deadline {
    await Task.yield()
  }
  try #require(await admission.pendingPassages == 1)
}
