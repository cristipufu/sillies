import Foundation

public struct ChatReply: Sendable {
  public let text: String
  public let sources: [ChatSource]
  public let memory: ConversationMemory
  public let exchanges: [ConversationToolExchange]
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
