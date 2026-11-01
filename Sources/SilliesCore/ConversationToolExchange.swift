import Foundation

/// Retains a completed call with its result so follow-up questions keep native tool context.
public struct ConversationToolExchange: Codable, Equatable, Sendable {
  public let call: ConversationToolCall
  public let result: String
  public init(call: ConversationToolCall, result: String) {
    self.call = call
    self.result = result
  }
}
