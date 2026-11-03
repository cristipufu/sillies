import Foundation
import SilliesCore

package struct TextGenerationRequest: Codable, Sendable {
  package enum Operation: String, Codable, Sendable { case generate, measure }
  package private(set) var operation = Operation.generate
  package private(set) var conversationID: UUID?
  package private(set) var sessionID: UUID?
  package func inSession(_ id: UUID?) -> Self {
    var copy = self
    copy.sessionID = id
    return copy
  }
  package func inConversation(_ id: UUID?) -> Self {
    var copy = self
    copy.conversationID = id
    return copy
  }
  package func measuringTokens() -> Self {
    var result = self
    result.operation = .measure
    return result
  }
  package let instructions: String
  package let messages: [TextMessage]
  package let tools: [ConversationToolDefinition]
  package var prompt: String { messages.last?.content ?? "" }
  package let maximumTokens: Int
  package let style: TextGenerationStyle
  package init(
    instructions: String, prompt: String, maximumTokens: Int,
    style: TextGenerationStyle = .precise
  ) {
    self.init(
      conversation: .init(
        instructions: instructions, messages: [.init(role: .user, content: prompt)], tools: []),
      maximumTokens: maximumTokens, style: style)
  }
  package init(
    conversation: TextConversationInput, maximumTokens: Int, style: TextGenerationStyle
  ) {
    instructions = conversation.instructions
    messages = conversation.messages
    tools = conversation.tools
    self.maximumTokens = maximumTokens
    self.style = style
  }
}

/// Backends own inference. Prompts, evidence validation and session presentation stay in the app.
package protocol PreparedTextModel: Sendable {
  func generate(_ request: TextGenerationRequest) async throws -> String
  func complete(_ request: TextGenerationRequest) async throws -> TextGenerationOutput
  func stream(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  func stop() async
}

extension PreparedTextModel {
  package func stream(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink)
    async throws -> TextGenerationOutput
  {
    let output = try await complete(request)
    if !output.text.isEmpty { try await receive(output.text) }
    return output
  }
  package func complete(_ request: TextGenerationRequest) async throws -> TextGenerationOutput {
    guard request.tools.isEmpty, request.operation == .generate else {
      throw TextModelError.toolsUnavailable
    }
    return try await .init(text: generate(request))
  }
}

package protocol TextModelProvider: Sendable {
  var id: String { get }
  func prepare(_ configuration: TextModelPreparation) async throws -> any PreparedTextModel
}

package struct TextModelPreparation: Codable, Sendable {
  package typealias Reasoning = TextModelReasoning
  package let directory: URL
  package let profile: TextModelProfile
  package var contextTokens: Int { profile.context.workingTokens }
  package let memoryLimitBytes: Int
  package let reasoning: TextModelReasoning?
  package init(
    directory: URL, profile: TextModelProfile, memoryLimitBytes: Int,
    reasoning: TextModelReasoning? = nil
  ) {
    self.directory = directory
    self.profile = profile
    self.memoryLimitBytes = memoryLimitBytes
    self.reasoning = reasoning
  }
}

package enum TextModelError: LocalizedError {
  case unavailable(String)
  case busy, invalidResponse, interrupted, repetitiveResponse, toolsUnavailable, contextLimit
  package var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .busy: String(localized: "The text model is busy. Please try again.")
    case .contextLimit:
      String(localized: "This passage exceeds the local model’s context. Try a shorter passage.")
    case .toolsUnavailable:
      String(
        localized:
          "This text model does not support Vault tools. Choose another in Settings → Local AI.")
    case .invalidResponse:
      String(
        localized: "The local text model returned an incomplete response. Your source is unchanged."
      )
    case .interrupted:
      String(localized: "Local text generation was interrupted. Your source is unchanged.")
    case .repetitiveResponse:
      String(localized: "The reply got stuck repeating itself. Please try again.")
    }
  }
}
