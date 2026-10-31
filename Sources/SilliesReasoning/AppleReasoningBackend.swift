import Foundation
import FoundationModels
import SilliesTextModels

package struct AppleReasoningBackend: ReasoningBackend {
  package init() {}
  package func availabilityNotice(localeIdentifier: String?) async -> String? {
    if let localeIdentifier,
      !SystemLanguageModel.default.supportsLocale(Locale(identifier: localeIdentifier))
    {
      let name = Locale.current.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
      return
        "Apple’s on-device AI does not support \(name). Your transcript is saved; generated notes and suggestions are unavailable in this language."
    }
    switch SystemLanguageModel.default.availability {
    case .available: return nil
    case .unavailable(.appleIntelligenceNotEnabled):
      return "Enable Apple Intelligence in System Settings for local summaries and suggestions."
    case .unavailable(.modelNotReady):
      return "Apple Intelligence is still preparing its on-device model."
    case .unavailable:
      return
        "On-device reasoning is unavailable on this Mac. Your captured material is still saved."
    }
  }
  package func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws
    -> String
  {
    let session = LanguageModelSession(model: .default, instructions: request.instructions)
    let options = GenerationOptions(
      samplingMode: .greedy, maximumResponseTokens: request.maximumTokens)
    switch format {
    case .text: return try await session.respond(to: request.prompt, options: options).content
    case .notes:
      return try encode(
        await session.respond(to: request.prompt, generating: GeneratedNotes.self, options: options)
          .content)
    case .actions:
      return try encode(
        await session.respond(
          to: request.prompt, generating: GeneratedActionEvidence.self, options: options
        ).content)
    case .suggestion:
      return try encode(
        await session.respond(
          to: request.prompt, generating: GeneratedSuggestion.self, options: options
        ).content)
    case .translations:
      return try encode(
        await session.respond(
          to: request.prompt, generating: TranslatedCommitments.self, options: options
        ).content)
    }
  }
  private func encode(_ value: some Encodable) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }
}
