import SilliesCore

/// Constant archive work: one checkpoint and one bounded page ending at the submitted message.
struct ConversationHistoryPreparation {
  let repository: any ConversationRepository
  let limit: ConversationPolicy.History.Window

  func prepare(_ context: ChatContext) async throws -> ChatContext {
    guard let handle = context.historyHandle, let current = context.messages.last else {
      return context
    }
    let checkpoint = try await repository.checkpoint(handle)
    let page = try await repository.page(
      .init(
        handle: handle, position: .throughMessage(current.id), limit: limit.messageLimit,
        maximumBytes: limit.byteLimit))
    try Task.checkCancellation()
    guard page.entries.last?.id == current.id else { throw ConversationStorageError.changed }
    let result = context.replacingHistory(
      messages: page.entries.map(\.message), memory: checkpoint.memory)
    return page.hasOlder ? result.coveringRecentWindow() : result.followingCheckpoint()
  }
}
