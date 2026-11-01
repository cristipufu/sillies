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
    let options = options(for: request)
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
  func options(for request: TextGenerationRequest) -> GenerationOptions {
    // Apple's tool decoder can fail under stochastic sampling even on a first-turn greeting.
    // Keep native tool selection/arguments deterministic; personality still comes from instructions.
    if !request.tools.isEmpty {
      return GenerationOptions(samplingMode: .greedy, maximumResponseTokens: request.maximumTokens)
    }
    return GenerationOptions(
      samplingMode: request.style == .conversation
        ? .random(probabilityThreshold: request.style.probabilityThreshold) : .greedy,
      temperature: request.style.temperature, maximumResponseTokens: request.maximumTokens)
  }
  private func encode(_ value: some Encodable) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }
}
