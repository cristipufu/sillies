import Foundation
import SilliesCore
import SilliesTextModels

enum ChatReplyGenerator {
  private static let maximumOutputTokens = 240

  static func reply(to context: ChatContext, backend: any ReasoningBackend) async throws -> String {
    let messages = context.messages.map {
      ["role": $0.role == .user ? "user" : "assistant", "text": $0.text]
    }
    let encoded = try JSONEncoder().encode(messages)
    let request = TextGenerationRequest(
      instructions: """
        You are \(context.companionName), a fictional little window companion in Sillies.
        Personality: \(context.profile.personality)
        Be helpful and conversational. Keep replies brief, usually one to three sentences.
        Your personality shapes your wording, never the accuracy of your answer.
        You only know the conversation below. Do not claim to see the screen, access files,
        remember older conversations, or perform actions. State uncertainty when appropriate.
        Use plain, speakable text without Markdown, stage directions, or speaker labels.
        \(LocalReasoningService.languageInstructions(context.profile.languageIdentifier))
        Reply to the last user message in the supplied conversation.
        """,
      prompt: String(decoding: encoded, as: UTF8.self), maximumTokens: maximumOutputTokens,
      style: .conversation)
    let text = try await backend.generate(request, format: .text)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw TextModelError.invalidResponse }
    guard !TextRepetitionGuard.containsLoop(text) else { throw TextModelError.repetitiveResponse }
    return String(text.prefix(ChatContext.maximumMessageCharacters))
  }
}
