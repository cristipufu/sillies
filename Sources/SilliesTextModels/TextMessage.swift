import Foundation
import SilliesCore

package struct TextMessage: Codable, Equatable, Sendable {
  package enum Role: String, Codable, Sendable { case user, assistant, tool }
  package let role: Role
  package let content: String
  package var calls: [ConversationToolCall] = []
  package var callID: String?
  package var toolName: String?
  package var reasoningContent: String?

  package init(role: Role, content: String) {
    self.role = role
    self.content = content
  }
  package static func calling(
    _ calls: [ConversationToolCall], text: String, reasoningContent: String? = nil
  ) -> Self {
    var message = Self(role: .assistant, content: text)
    message.calls = calls
    message.reasoningContent = reasoningContent
    return message
  }
  package static func result(_ text: String, for call: ConversationToolCall) -> Self {
    var message = Self(role: .tool, content: text)
    message.callID = call.id
    message.toolName = call.name
    return message
  }

  package static func exchanging(_ exchanges: [ConversationToolExchange]) -> [Self] {
    exchanges.flatMap { [.calling([$0.call], text: ""), .result($0.result, for: $0.call)] }
  }
}
