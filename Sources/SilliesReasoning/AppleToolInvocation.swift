import SilliesCore
import SilliesTextModels

/// A retained native tool receives only the current turn's budget and destinations.
actor AppleToolInvocation {
  private var toolbox: ConversationToolbox?
  func open(_ toolbox: ConversationToolbox) { self.toolbox = toolbox }
  func close() { toolbox = nil }
  func invoke(_ call: ConversationToolCall) async throws -> String {
    try Task.checkCancellation()
    guard let toolbox else { throw TextModelError.interrupted }
    let result = try await toolbox.invoke(call)
    if let question = await toolbox.clarification {
      throw ConversationClarificationRequested(question: question)
    }
    return result
  }
}
