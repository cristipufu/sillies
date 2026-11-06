import Foundation

/// Observable application inputs, not a model's internal reasoning or an explanation of its answer.
public struct ReplyContextInspection: Codable, Equatable, Sendable {
  public let recentMessages: Int
  public let previousToolResults: Int
  public let availableTools: Int
  public let workingContextTokens: Int
  public let notes: ConversationMemory

  public init(context: ChatContext, availableTools: Int, workingContextTokens: Int) {
    recentMessages = context.messages.count
    previousToolResults = context.messages.reduce(0) { $0 + $1.exchanges.count }
    self.availableTools = max(0, availableTools)
    self.workingContextTokens = max(0, workingContextTokens)
    notes = context.memory
  }
}
