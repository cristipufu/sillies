import SilliesCore

/// Native conversation content, separate from generation settings.
package struct TextConversationInput: Sendable {
  package let instructions: String
  package let messages: [TextMessage]
  package let tools: [ConversationToolDefinition]
  package init(instructions: String, messages: [TextMessage], tools: [ConversationToolDefinition]) {
    self.instructions = instructions
    self.messages = messages
    self.tools = tools
  }
}
