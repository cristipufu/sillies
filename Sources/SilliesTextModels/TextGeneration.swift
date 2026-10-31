import Foundation

package struct TextGenerationRequest: Codable, Sendable {
  package let instructions: String
  package let prompt: String
  package let maximumTokens: Int
  package init(instructions: String, prompt: String, maximumTokens: Int) {
    self.instructions = instructions
    self.prompt = prompt
    self.maximumTokens = maximumTokens
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
  package init(directory: URL, contextTokens: Int) {
    self.directory = directory
    self.contextTokens = contextTokens
  }
}

package enum TextModelError: LocalizedError {
  case unavailable(String)
  case busy, invalidResponse, interrupted
  package var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .busy: "The text model is busy. Please try again."
    case .invalidResponse:
      "The local text model returned an incomplete response. Your source is unchanged."
    case .interrupted: "Local text generation was interrupted. Your source is unchanged."
    }
  }
}
