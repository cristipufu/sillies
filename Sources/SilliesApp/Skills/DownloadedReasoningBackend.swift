import Foundation
import SilliesModelStore
import SilliesTextModels

struct DownloadedReasoningBackend: ReasoningBackend {
  let manifest: TextModelManifest
  let store: ModelStore
  let registry: TextModelRegistry

  func availabilityNotice(localeIdentifier: String?) async -> String? {
    do {
      guard try await store.isInstalled(manifest) else {
        return
          "Download \(manifest.model.name) in Settings → Local AI to generate notes. Your transcript is saved."
      }
      return nil
    } catch {
      return "The selected local text model could not be opened: \(error.localizedDescription)"
    }
  }

  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    let shaped = TextGenerationRequest(
      instructions: request.instructions + "\n" + format.instruction,
      prompt: request.prompt, maximumTokens: request.maximumTokens)
    let text = try await registry.generate(shaped, using: manifest)
    return try ReasoningOutput.clean(text, format: format)
  }
}

/// Accept a single JSON object, optionally fenced. Never salvage arbitrary prose as factual notes.
enum ReasoningOutput {
  static func clean(_ response: String, format: ReasoningFormat) throws -> String {
    var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.contains("<think>"), !text.contains("</think>") else {
      throw TextModelError.invalidResponse
    }
    if case .text = format { return text }
    if text.hasPrefix("```json\n"), text.hasSuffix("```") {
      text = String(text.dropFirst("```json\n".count).dropLast(3)).trimmingCharacters(
        in: .whitespacesAndNewlines)
    } else if text.hasPrefix("```\n"), text.hasSuffix("```") {
      text = String(text.dropFirst(4).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard text.first == "{", text.last == "}" else { throw TextModelError.invalidResponse }
    return text
  }
}
