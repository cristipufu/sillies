import Foundation

public struct ChatReply: Sendable {
  public let text: String
  public let sources: [ChatSource]
  public let memory: ConversationMemory
  public let exchanges: [ConversationToolExchange]
  public private(set) var contextInspection: ReplyContextInspection?
  public private(set) var clarification: ChatClarification?
  public func asking(_ question: ChatClarification?) -> Self {
    var copy = self
    copy.clarification = question
    return copy
  }
  public func inspecting(_ context: ReplyContextInspection) -> Self {
    var copy = self
    copy.contextInspection = context
    return copy
  }
  public init(
    text: String, sources: [ChatSource] = [], exchanges: [ConversationToolExchange] = [],
    memory: ConversationMemory = .init()
  ) {
    self.memory = memory
    self.text = text
    self.sources = sources
    self.exchanges = exchanges
  }
}
