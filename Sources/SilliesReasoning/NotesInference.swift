import Foundation
import SilliesTextModels

/// Each notes request releases admission before another slice or interactive turn can run.
struct NotesInference: Sendable {
  private static let structuredOutputReserveTokens = 256
  let backend: any ReasoningBackend
  let budgeting: any ConversationBudgeting
  let turns: ReasoningTurnGate

  func admits(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> Bool {
    let shaped = TextGenerationRequest(
      instructions: request.instructions + "\n" + format.instruction, prompt: request.prompt,
      maximumTokens: request.maximumTokens, style: request.style)
    let budget = ConversationBudget(backend: budgeting)
    guard try budget.canMeasure(shaped) else { return false }
    return try await budget.requiredTokens(shaped)
      <= max(0, budget.admissionTokens - Self.structuredOutputReserveTokens)
  }

  func response<Value: Decodable & Sendable>(
    _ type: Value.Type, request: TextGenerationRequest, format: ReasoningFormat
  ) async throws -> Value {
    let text = try await generate(request, format: format)
    return try JSONDecoder().decode(type, from: Data(text.utf8))
  }

  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    try await turns.acquire(.background)
    do {
      try Task.checkCancellation()
      guard try await admits(request, format: format) else { throw TextModelError.contextLimit }
      let value = try await backend.generate(request, format: format)
      try Task.checkCancellation()
      await turns.release()
      return value
    } catch {
      await turns.release()
      throw error
    }
  }
}
