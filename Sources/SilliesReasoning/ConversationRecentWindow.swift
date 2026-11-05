import Foundation
import SilliesCore
import SilliesTextModels

/// Count and byte boundaries precede tokenization. Whole older turns can be omitted, never the query.
enum ConversationRecentWindow {
  static func select(_ context: ChatContext, limit: ConversationPolicy.History.Window) throws
    -> ChatContext
  {
    var selected: [ChatMessage] = []
    var bytes = 0
    for message in context.messages.suffix(limit.messageLimit).reversed() {
      try Task.checkCancellation()
      let size = try JSONEncoder().encode(message).count
      guard size <= limit.byteLimit - bytes else {
        if selected.isEmpty { throw TextModelError.contextLimit }
        break
      }
      selected.append(message)
      bytes += size
    }
    selected.reverse()
    // A checkpoint records summary progress, not permission to discard verbatim recent turns.
    // Background maintenance can catch up while a user is reading or composing their next reply.
    guard let firstUser = selected.firstIndex(where: { $0.role == .user }) else {
      throw TextModelError.invalidResponse
    }
    selected = Array(selected[firstUser...])
    let result = ChatContext(
      companionName: context.companionName, profile: context.profile,
      messages: selected, memory: context.memory
    ).inTurn(context.turnID, session: context.sessionID).inHistory(context.historyHandle)
      .presented(as: context.mode)
    if selected.count != context.messages.count || context.historyCoverage == .recentWindow {
      return result.coveringRecentWindow()
    }
    return result.followingCheckpoint()
  }
}
