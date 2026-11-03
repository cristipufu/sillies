import Foundation
import SilliesTextModels

/// Selects complete tool-owned representations. Never truncates JSON or asks a tool to repeat a write.
struct ConversationEvidenceBudget: Sendable {
  let totalTokens: Int
  let resultTokens: Int
  let measure: @Sendable (String) async throws -> Int

  static func prepare(backend: any ConversationBackend, request: TextGenerationRequest) async throws
    -> Self?
  {
    guard backend.toolResultBudgeting == .measured else { return nil }
    let capacity = ConversationBudget(backend: backend)
    let used = try await capacity.requiredTokens(request)
    let remaining = max(0, capacity.admissionTokens - used)
    let policy = backend.conversationPolicy.tools
    return .init(
      totalTokens: min(policy.reserveTokens, remaining), resultTokens: policy.resultTokens
    ) { text in
      try await backend.inputTokenCount(
        .init(instructions: "", prompt: text, maximumTokens: 1, style: .conversation))
    }
  }

  func select(_ output: ConversationToolOutput, remaining: Int) async throws -> (
    text: String, tokens: Int
  ) {
    for text in output.representations {
      try Task.checkCancellation()
      let count = try await measure(text)
      guard count >= 0 else { throw TextModelError.invalidResponse }
      if count <= min(resultTokens, remaining) { return (text, count) }
    }
    // The operation completed, but its evidence cannot fit. In particular, never report a
    // successful memory write as "not executed" or silently clip its acknowledgement.
    let notice = """
      {"status":"outputOmitted","coverage":"The operation completed, but its result exceeds the remaining context allowance. No result evidence is included. Do not invent its contents; narrow a read or explain the limitation."}
      """
    let count = try await measure(notice)
    guard count >= 0, count <= min(resultTokens, remaining) else {
      throw TextModelError.contextLimit
    }
    return (notice, count)
  }
}
