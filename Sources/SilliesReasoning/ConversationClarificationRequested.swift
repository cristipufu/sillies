import SilliesCore

/// Native tool execution exits through the framework's documented ToolCallError boundary.
/// This is a completed question, not a generation failure or a suspended inference session.
struct ConversationClarificationRequested: Error {
  let question: ChatClarification
}
