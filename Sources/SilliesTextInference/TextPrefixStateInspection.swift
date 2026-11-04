import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SilliesTextModels

/// Bounded synthetic diagnostics of native cache contents, not an answer-quality score.
enum TextPrefixStateInspection {
  private static let maximumRequests = 3
  private static let allocatorCacheBytes = 128 * 1_024 * 1_024
  private struct Result: Encodable {
    let index: Int
    let tokens: Int
    let prefixTokens: Int
    let liveStateBytes: Int
    let carriedState: Bool
    let restoredLogitError: Float
    let restoredStateError: Float
    let repeatedLogitError: Float
    let coldLogitError: Float
    let coldTopTokenMatches: Bool
    let releaseCleared: Bool
    let memory: Memory.Snapshot
  }

  static func run(requestURL: URL) async throws {
    let requests = try TextInferenceJSON.read(
      [TextInferenceRequest].self, from: requestURL,
      maximumBytes: TextInferenceWire.maximumMessageBytes)
    guard let first = requests.first, requests.count <= maximumRequests,
      requests.allSatisfy({ $0.configuration == first.configuration })
    else { throw TextModelError.invalidResponse }
    Memory.cacheLimit = allocatorCacheBytes
    Memory.memoryLimit = first.configuration.memoryLimitBytes
    let container = try await LLMModelFactory.shared.loadContainer(
      from: first.configuration.directory,
      using: LocalTokenizerLoader(policy: first.configuration.profile.runtimePolicy))
    for (index, request) in requests.enumerated() {
      let result = try await container.perform { context in
        try await inspect(request, index: index, context: context)
      }
      try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result) + Data([10]))
      Memory.clearCache()
    }
  }

  private static func inspect(_ request: TextInferenceRequest, index: Int, context: ModelContext)
    async throws -> Result
  {
    let plan = try MLXGenerationPlan(request)
    let input = try await prepareInput(plan, context: context)
    let tokens = input.text.tokens.asArray(Int.self)
    guard tokens.count <= (plan.maximumInputTokens ?? 0),
      let sessionID = request.generation.sessionID
    else { throw TextModelError.contextLimit }
    let boundary = try await MLXPrefixBoundary.count(
      tokens: tokens, plan: plan, context: context)
    let snapshot = MLXPrefixSnapshot()
    let original = try snapshot.prepare(
      tokens: tokens, boundary: boundary, plan: plan, context: context)
    let suffix = Array(tokens.dropFirst(original.consumedTokens))
    let output = try forward(suffix, prepared: original, plan: plan, context: context)
    let restored = try snapshot.prepare(
      tokens: tokens, boundary: boundary, plan: plan, context: context)
    let restoredOutput = try forward(suffix, prepared: restored, plan: plan, context: context)
    let stateError = try cacheError(original.cache, restored.cache)
    let logitError = difference(output.logits, restoredOutput.logits)
    let repeated = try snapshot.prepare(
      tokens: tokens, boundary: boundary, plan: plan, context: context)
    let repeatedOutput = try forward(suffix, prepared: repeated, plan: plan, context: context)
    let repeatError = difference(output.logits, repeatedOutput.logits)
    let coldCache = try context.model.newCache(parameters: plan.parameters)
    let cold = try forward(
      tokens,
      prepared: .init(
        cache: coldCache, state: nil, consumedTokens: 0, reusedTokens: 0, preparationSeconds: 0),
      plan: plan, context: context)
    let coldError = difference(output.logits[0, -1], cold.logits[0, -1])
    let topMatches =
      output.logits[0, -1].argMax().item(Int.self) == cold.logits[0, -1].argMax().item(Int.self)
    snapshot.release(sessionID)
    return Result(
      index: index, tokens: tokens.count, prefixTokens: restored.reusedTokens,
      liveStateBytes: restored.cache.flatMap(\.state).reduce(0) { $0 + $1.nbytes },
      carriedState: original.state != nil, restoredLogitError: logitError,
      restoredStateError: stateError, repeatedLogitError: repeatError,
      coldLogitError: coldError, coldTopTokenMatches: topMatches,
      releaseCleared: !snapshot.matches(tokens: tokens, sessionID: sessionID),
      memory: Memory.snapshot())
  }

  private static func prepareInput(_ plan: MLXGenerationPlan, context: ModelContext) async throws
    -> sending LMInput
  {
    let generator =
      context.configuration.messageGenerator
      ?? (context.model as? any LLMModel)?.messageGenerator(tokenizer: context.tokenizer)
      ?? DefaultMessageGenerator()
    return try await context.processor.prepare(
      input: UserInput(
        messages: MLXConversationInput.templateMessages(
          plan.request.generation, generator: generator),
        tools: plan.tools, additionalContext: plan.templateContext))
  }

  private static func forward(
    _ tokens: [Int], prepared: MLXPrefixSnapshot.Prepared, plan: MLXGenerationPlan,
    context: ModelContext
  ) throws -> LMOutput {
    switch try context.model.prepare(
      LMInput(tokens: MLXArray(tokens)), cache: prepared.cache,
      state: prepared.state, prefill: plan.parameters.prefill)
    {
    case .logits(let output):
      eval(output.logits, prepared.cache)
      return output
    case .tokens(let remaining):
      let output = context.model(
        remaining[text: .newAxis], cache: prepared.cache, state: prepared.state)
      eval(output.logits, prepared.cache)
      return output
    }
  }

  private static func difference(_ lhs: MLXArray, _ rhs: MLXArray) -> Float {
    guard lhs.shape == rhs.shape else { return .infinity }
    return MLX.max(MLX.abs(lhs.asType(.float32) - rhs.asType(.float32))).item(Float.self)
  }

  private static func cacheError(_ lhs: [KVCache], _ rhs: [KVCache]) throws -> Float {
    guard lhs.count == rhs.count else { throw TextModelError.invalidResponse }
    var maximum: Float = 0
    for (first, second) in zip(lhs, rhs) {
      guard first.offset == second.offset, first.metaState == second.metaState,
        first.state.count == second.state.count
      else { throw TextModelError.invalidResponse }
      for (a, b) in zip(first.state, second.state) { maximum = max(maximum, difference(a, b)) }
    }
    return maximum
  }
}
