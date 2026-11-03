import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

/// Three real checkpoint boundaries, a sliding recent window and reopening the store.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_ROLLOVER_CHECK"] == "1"))
func nativeRepeatedCheckpointRollover() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let model = try await NativeConversationModel.prepare()
  let lifetime = TextModelLifetime()
  do {
    await model.backend.retain(for: lifetime)
    let store = fixture.library
    let handle = try await fixture.seed(96, in: store)
    var previous = try await store.checkpoint(handle)
    for round in 0..<3 {
      try await appendRolloverHistory(round, handle: handle, store: store)
      let context = try await fixture.question(
        "Hello! What can we do together? Answer briefly.", handle: handle, store: store,
        session: lifetime.id)
      let service = LocalConversationService(
        resolveBackend: { model.backend }, tools: [], turns: .init(),
        history: .init(repository: store))
      let start = ContinuousClock.now
      let reply = try await service.reply(to: context)
      #expect(!reply.text.isEmpty)
      #expect(try await store.checkpoint(handle).memory == previous.memory)
      try await store.save(
        .init(
          handle: handle, messages: [.init(role: .companion, text: reply.text)],
          checkpoint: .init(), savedAt: .now))
      let replyDuration = start.duration(to: .now)
      let worker = ConversationCheckpointWorker(repository: store, backend: model.backend)
      #expect(try await worker.advance(try #require(ConversationCheckpointJob(context))))
      let current = try await store.checkpoint(handle)
      #expect(current.memory.throughMessageID != previous.memory.throughMessageID)
      let restarted = try await fixture.library.checkpoint(handle)
      #expect(restarted == current)
      previous = current
      print(
        "NATIVE ROLLOVER \(model.id): round=\(round); reply=\(replyDuration); checkpoint and reopen verified; answer=\(reply.text)"
      )
    }
    await lifetime.end()
    await model.stop()
  } catch {
    await lifetime.end()
    await model.stop()
    throw error
  }
}

private func appendRolloverHistory(
  _ round: Int, handle: ConversationHandle, store: ConversationLibrary
) async throws {
  let messages = (0..<32).flatMap { index in
    [
      ChatMessage(
        role: .user, text: "Planning note \(round)-\(index): we reviewed a project task."),
      ChatMessage(role: .companion, text: "Noted."),
    ]
  }
  try await store.save(
    .init(handle: handle, messages: messages, checkpoint: .init(), savedAt: .now))
}
