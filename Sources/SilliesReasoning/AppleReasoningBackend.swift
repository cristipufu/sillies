import Foundation
import FoundationModels
import SilliesTextModels

package struct AppleReasoningBackend: ReasoningBackend {
  package var meetingNotesStyle: MeetingNotesStyle { .sourceExcerpts }
  let conversations: AppleConversationSessions
  package init() { conversations = AppleConversationSessions() }
  init(conversations: AppleConversationSessions) { self.conversations = conversations }
  package func stop() async { await conversations.stop() }
  package func setRetention(_ retention: TextModelRegistry.Retention) async {
    await conversations.setRetention(retention)
  }
  package func availabilityNotice(localeIdentifier: String?) async -> String? {
    if let localeIdentifier,
      !SystemLanguageModel.default.supportsLocale(Locale(identifier: localeIdentifier))
    {
      let name = Locale.current.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
      return
        String(
          localized:
            "Apple’s on-device AI does not support \(name). Choose a downloaded text model in Settings → Local AI."
        )
    }
    switch SystemLanguageModel.default.availability {
    case .available: return nil
    case .unavailable(.appleIntelligenceNotEnabled):
      return
        String(
          localized:
            "Enable Apple Intelligence in System Settings, or choose a downloaded text model in Settings → Local AI."
        )
    case .unavailable(.modelNotReady):
      return String(localized: "Apple Intelligence is still preparing its on-device model.")
    case .unavailable:
      return
        String(
          localized:
            "Apple’s on-device AI is unavailable on this Mac. Choose a downloaded text model in Settings → Local AI."
        )
    }
  }
  package func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws
    -> String
  {
    do { return try await generateResponse(request, format: format) } catch {
      throw AppleGenerationFailure.recoverable(error)
    }
  }

  private func generateResponse(_ request: TextGenerationRequest, format: ReasoningFormat)
    async throws
    -> String
  {
    let session = LanguageModelSession(model: .default, instructions: request.instructions)
    let options = AppleGenerationOptions.make(request)
    switch format {
    case .text:
      return try await session.respond(to: request.prompt, options: options).content
    case .meetingTopicMatch, .actionReview:
      let text = try await session.respond(
        to: request.prompt + "\nAnswer YES or NO only.", options: options
      ).content
      return try encode(
        AppleNotesText.decision(text))
    case .notes:
      return try encode(
        await session.respond(to: request.prompt, generating: GeneratedNotes.self, options: options)
          .content)
    case .meetingTopics:
      let text = try await session.respond(
        to: request.prompt + AppleNotesText.listInstruction, options: options
      ).content
      return try encode(
        GeneratedMeetingTopics(topics: AppleNotesText.items(text)))
    case .meetingTopicBody:
      throw TextModelError.invalidResponse
    case .actions:
      let text = try await session.respond(
        to: request.prompt + AppleNotesText.listInstruction, options: options
      ).content
      return try encode(
        GeneratedActionEvidence(passages: AppleNotesText.items(text)))
    case .suggestion:
      return try encode(
        await session.respond(
          to: request.prompt, generating: GeneratedSuggestion.self, options: options
        ).content)
    case .translations:
      let text = try await session.respond(to: request.prompt, options: options).content
      return try encode(GeneratedTranslations(translations: [text]))
    }
  }
  private func encode(_ value: some Encodable) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }
}
