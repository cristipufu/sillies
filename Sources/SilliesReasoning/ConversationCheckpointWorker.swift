import Foundation
import SilliesCore

/// One page, one summary, one conditional write. All durable cursors refer to original messages.
struct ConversationCheckpointWorker {
  let repository: any ConversationRepository
  let backend: any ConversationBackend

  func advance(_ job: ConversationCheckpointJob) async throws -> Bool {
    let snapshot = try await repository.checkpoint(job.handle)
    let policy = backend.conversationPolicy.history.checkpoint
    let page = try await repository.page(
      .init(
        handle: job.handle,
        position: .between(after: snapshot.memory.throughMessageID, before: job.beforeMessageID),
        limit: policy.window.messageLimit,
        maximumBytes: policy.window.byteLimit))
    var messages = page.entries.map(\.message)
    if messages.last?.role == .user {
      // The page may split a turn. Leave its final user and reply for the next slice.
      guard let lastUser = messages.lastIndex(where: { $0.role == .user }) else { return false }
      messages = Array(messages.prefix(lastUser))
    }
    guard !messages.isEmpty,
      messages.count >= policy.minimumMessages || page.isByteLimited
    else { return false }
    var memory = snapshot.memory
    if memory.throughMessageID == nil, let opening = messages.first(where: { $0.role == .user }) {
      memory = .init(openingStatement: opening.text)
    }
    guard
      let replacement = try await ConversationCompactor(backend: backend).compact(
        messages, into: memory)
    else { return false }
    try Task.checkCancellation()
    return try await repository.advanceCheckpoint(
      .init(handle: job.handle, expected: snapshot, replacement: replacement))
  }
}
