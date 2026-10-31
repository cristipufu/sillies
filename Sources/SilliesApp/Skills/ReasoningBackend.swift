import Foundation
import SilliesTextModels

/// Shared tasks describe output shape; providers own their native inference mechanism.
enum ReasoningFormat: Sendable {
  case text, notes, actions, suggestion, translations
  var instruction: String {
    switch self {
    case .text: "Return only the requested text."
    case .notes:
      "Return ONLY a JSON object with string fields summary and explanation. Leave explanation empty unless requested."
    case .actions:
      "Return ONLY a JSON object with a passages array containing verbatim source sentences."
    case .suggestion:
      "Return ONLY a JSON object with string fields question and evidence. Use empty strings when no question is warranted."
    case .translations:
      "Return ONLY a JSON object with a translations array of strings in input order."
    }
  }
}

protocol ReasoningBackend: Sendable {
  func availabilityNotice(localeIdentifier: String?) async -> String?
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String
}

extension ReasoningBackend {
  func response<T: Decodable & Sendable>(
    _ type: T.Type, request: TextGenerationRequest, format: ReasoningFormat
  ) async throws -> T {
    let output = try await generate(request, format: format)
    return try JSONDecoder().decode(type, from: Data(output.utf8))
  }
}
