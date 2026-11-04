import Foundation
import MLXLMCommon
import SilliesTextModels

/// Validates one request and translates its reviewed profile into native generation settings.
struct MLXGenerationPlan: Sendable {
  let request: TextInferenceRequest
  let parameters: GenerateParameters
  let tools: [[String: any Sendable]]?
  let maximumInputTokens: Int?

  init(_ request: TextInferenceRequest, samplingSeed: UInt64? = nil) throws {
    let configuration = request.configuration
    let generation = request.generation
    let task = generation.style.settings(in: configuration.profile.generation)
    guard configuration.directory.isFileURL, configuration.profile.isValid,
      let outputTokens = task.generationTokens(for: generation.maximumTokens)
    else { throw TextModelError.invalidResponse }
    guard configuration.memoryLimitBytes > 0,
      configuration.memoryLimitBytes
        <= TextModelMemoryBudget.maximumAllocation(
          physicalMemory: ProcessInfo.processInfo.physicalMemory)
    else {
      throw TextModelError.unavailable(
        String(localized: "The text model exceeds this Mac’s memory budget."))
    }
    guard outputTokens <= configuration.contextTokens else { throw TextModelError.contextLimit }
    if let snapshot = configuration.profile.runtimePolicy.prefixSnapshot,
      snapshot.maximumBytes > configuration.memoryLimitBytes
    {
      throw TextModelError.invalidResponse
    }
    maximumInputTokens =
      generation.operation == .measure ? nil : configuration.contextTokens - outputTokens
    let sampling = task.sampling
    var parameters = GenerateParameters(
      maxTokens: outputTokens, maxKVSize: configuration.contextTokens,
      temperature: sampling.temperature, topP: sampling.topP, topK: sampling.topK,
      repetitionPenalty: sampling.repetitionPenalty,
      repetitionContextSize: task.repetitionContextTokens)
    parameters.prefill = PrefillParameters(stepSize: configuration.profile.prefill.chunkTokens)
    parameters.seed = samplingSeed
    self.parameters = parameters
    self.request = request
    tools = MLXConversationInput.nativeTools(generation)
  }

  var templateContext: [String: any Sendable] {
    MLXReasoningPolicy(reasoning: request.configuration.reasoning).templateContext
  }
  var usesNativeSession: Bool {
    request.configuration.profile.runtimePolicy.conversationCache == .nativeSession
      && request.generation.style == .conversation && request.generation.sessionID != nil
      && request.generation.messages.allSatisfy { $0.reasoningContent == nil }
  }
  var usesPrefixSnapshot: Bool {
    request.configuration.profile.runtimePolicy.conversationCache == .prefixSnapshot
      && request.generation.style == .conversation && request.generation.sessionID != nil
  }
}
