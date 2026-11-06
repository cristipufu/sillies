import Foundation
import FoundationModels
import SilliesCore
import SilliesTextModels

@testable import SilliesReasoning

/// Diagnostic alternatives only. Production selection never reads these variants.
enum NativeRepresentationVariant: String, CaseIterable, Sendable {
  case baseline, structuredTools, entityBackground, combined
  static let outputTokens = 240

  func backend() -> AppleReasoningBackend {
    switch self {
    case .baseline, .entityBackground: return AppleReasoningBackend()
    case .structuredTools, .combined:
      return AppleReasoningBackend(
        conversations: AppleConversationSessions { request, invocation in
          let tools = try request.tools.map {
            StructuredRepresentationTool(
              base: try AppleConversationTool($0, invoke: invocation.invoke))
          }
          return NativeAppleChatSession(
            session: LanguageModelSession(
              model: .default, tools: tools,
              transcript: try AppleConversationTranscript.make(
                request, tools: tools.map { .init(tool: $0) })))
        })
    }
  }

  func request(for context: ChatContext, tools: [ConversationToolDefinition]) throws
    -> TextGenerationRequest
  {
    let original = ChatReplyGenerator.request(
      for: context, tools: tools, maximumTokens: Self.outputTokens)
    switch self {
    case .baseline, .structuredTools: return original
    case .entityBackground, .combined:
      let withoutBackground = ChatReplyGenerator.request(
        for: context.prepared(with: .init()), tools: tools, maximumTokens: Self.outputTokens)
      let messages = try EntityBackgroundRepresentation.applying(
        context.background, to: withoutBackground.messages)
      return TextGenerationRequest(
        conversation: .init(
          instructions: original.instructions, messages: messages, tools: original.tools),
        maximumTokens: original.maximumTokens, style: original.style
      ).inConversation(original.conversationID).inSession(original.sessionID)
        .inContext(original.contextIdentity)
    }
  }
}

private struct StructuredRepresentationTool: Tool {
  let base: AppleConversationTool
  var name: String { base.name }
  var description: String { base.description }
  var parameters: GenerationSchema { base.parameters }
  func call(arguments: GeneratedContent) async throws -> GeneratedContent {
    let text = try await base.call(arguments: arguments)
    do { return try GeneratedContent(json: text) } catch {
      // Some tool outcomes are plain text. Preserve them verbatim instead of requiring JSON.
      return GeneratedContent(text)
    }
  }
}
