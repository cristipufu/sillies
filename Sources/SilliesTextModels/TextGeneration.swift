import Foundation

package struct TextGenerationRequest: Codable, Sendable {
  package let instructions: String
  package let prompt: String
  package let maximumTokens: Int
  package let style: TextGenerationStyle
  package init(
    instructions: String, prompt: String, maximumTokens: Int,
    style: TextGenerationStyle = .precise
  ) {
    self.instructions = instructions
    self.prompt = prompt
    self.maximumTokens = maximumTokens
    self.style = style
  }
}

/// Backends own inference. Prompts, evidence validation and session presentation stay in the app.
package protocol PreparedTextModel: Sendable {
  func generate(_ request: TextGenerationRequest) async throws -> String
  func stop() async
}

package protocol TextModelProvider: Sendable {
  var id: String { get }
  func prepare(_ configuration: TextModelPreparation) async throws -> any PreparedTextModel
}

package struct TextModelPreparation: Codable, Sendable {
  package let directory: URL
  package let contextTokens: Int
  package let memoryLimitBytes: Int
  package init(directory: URL, contextTokens: Int, memoryLimitBytes: Int) {
    self.directory = directory
    self.contextTokens = contextTokens
    self.memoryLimitBytes = memoryLimitBytes
  }
}

package enum TextModelError: LocalizedError {
  case unavailable(String)
  case busy, invalidResponse, interrupted, repetitiveResponse
  package var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .busy: String(localized: "The text model is busy. Please try again.")
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
