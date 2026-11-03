import Foundation
import SilliesCore
import SilliesTextModels

/// Counts the serialized provider request and the same task allowances used during generation.
struct ConversationBudget {
  let backend: any ConversationBudgeting

  func canMeasure(_ request: TextGenerationRequest) throws -> Bool {
    let bytes =
      request.instructions.utf8.count
      + request.messages.reduce(0) {
        $0 + $1.content.utf8.count + ($1.reasoningContent?.utf8.count ?? 0)
          + $1.calls.reduce(0) { $0 + $1.arguments.count }
      }
    guard bytes <= TextInferenceWire.maximumMessageBytes / 2 else { return false }
    // JSON escaping can expand control characters. Reserve the other half for preparation metadata.
    return try JSONEncoder().encode(request).count <= TextInferenceWire.maximumMessageBytes / 2
  }

  func admits(_ request: TextGenerationRequest) async throws -> Bool {
    guard try canMeasure(request) else { return false }
    return try await requiredTokens(request) <= admissionTokens
  }

  func requiredTokens(_ request: TextGenerationRequest) async throws -> Int {
    guard try canMeasure(request) else { throw TextModelError.contextLimit }
    let input = try await backend.inputTokenCount(request)
    let reasoning = backend.reasoningTokenReserve(for: request.style)
    guard input >= 0, request.maximumTokens > 0, reasoning >= 0 else {
      throw TextModelError.contextLimit
    }
    let task = request.style.settings(in: backend.generationProfile)
    let generation = input.addingReportingOverflow(min(request.maximumTokens, task.outputTokens))
    let total = generation.partialValue.addingReportingOverflow(reasoning)
    guard !generation.overflow, !total.overflow else { throw TextModelError.contextLimit }
    return total.partialValue
  }

  var admissionTokens: Int {
    let safety = backend.conversationPolicy.safetyTokens
    return backend.contextWindowTokens > safety ? backend.contextWindowTokens - safety : 0
  }

  func initialTurnTokens(tools: [ConversationToolDefinition]) -> Int {
    let reserve =
      tools.isEmpty
      ? backend.conversationPolicy.safetyTokens : backend.conversationPolicy.tools.reserveTokens
    return backend.contextWindowTokens > reserve ? backend.contextWindowTokens - reserve : 0
  }
}
