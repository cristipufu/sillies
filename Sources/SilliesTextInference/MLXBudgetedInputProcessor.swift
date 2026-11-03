import MLXLMCommon
import SilliesTextModels

/// Bounds the actual native render as well as the app's preflight render. Retained sessions may
/// carry protocol details that cannot be reconstructed from the visible answer alone.
struct MLXBudgetedInputProcessor: UserInputProcessor {
  let base: any UserInputProcessor
  let maximumTokens: Int

  func prepare(input: UserInput) async throws -> LMInput {
    let prepared = try await base.prepare(input: input)
    guard prepared.text.tokens.size <= maximumTokens else { throw TextModelError.contextLimit }
    return prepared
  }
}
