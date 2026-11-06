import Foundation
import MLX
import MLXLMCommon
import SilliesTextModels

/// Full-template prefix reuse, independent of the model's conversation serialization format.
enum MLXPrefixGeneration {
  struct Invocation: Sendable {
    let tokens: [Int]
    let plan: MLXGenerationPlan
    let components: GenerationComponents
    var collector: MLXGenerationCollector
    let rejectionObserver: (@Sendable (RejectedToolCall) async -> Void)?
  }

  static func generate(
    _ invocation: Invocation, snapshot: MLXPrefixSnapshot, context: ModelContext,
    receive: @escaping TextDeltaSink
  ) async throws -> TextGenerationOutput {
    let plan = invocation.plan
    let boundary =
      snapshot.matches(
        tokens: invocation.tokens, sessionID: plan.request.generation.sessionID,
        contextIdentity: plan.request.generation.contextIdentity)
      ? 0
      : try await MLXPrefixBoundary.count(tokens: invocation.tokens, plan: plan, context: context)
    let prepared = try snapshot.prepare(
      tokens: invocation.tokens, boundary: boundary, plan: plan, context: context)
    try invocation.components.validate(parameters: plan.parameters)
    let processor = invocation.components.logitProcessor(parameters: plan.parameters).map {
      MLXCompletePromptProcessor(base: $0, tokens: invocation.tokens)
    }
    let pending = Array(invocation.tokens.dropFirst(prepared.consumedTokens))
    let iterator = try TokenIterator(
      input: LMInput(tokens: MLXArray(pending)), model: context.model,
      cache: prepared.cache, state: prepared.state, processor: processor,
      sampler: plan.parameters.sampler(), prefill: plan.parameters.prefill,
      maxTokens: plan.parameters.maxTokens)
    let (events, task) = generateTask(
      promptTokenCount: pending.count, modelConfiguration: context.configuration,
      tokenizer: context.tokenizer, iterator: iterator, tools: plan.tools,
      toolCallPolicy: plan.parameters.toolCallPolicy)
    var collector = invocation.collector
    do {
      for await event in events {
        try Task.checkCancellation()
        if case .rejectedToolCall(let rejection) = event {
          await invocation.rejectionObserver?(rejection)
        }
        if let delta = try collector.consume(account(event, preparation: prepared)) {
          try await receive(delta)
        }
      }
      await task.value
      try Task.checkCancellation()
      let output = try await collector.finish(receive: receive)
      try Task.checkCancellation()
      return output
    } catch {
      task.cancel()
      await task.value
      snapshot.clear()
      throw error
    }
  }

  private static func account(_ event: Generation, preparation: MLXPrefixSnapshot.Prepared)
    -> Generation
  {
    guard case .info(let info) = event else { return event }
    return .info(
      .init(
        promptTokenCount: info.promptTokenCount + preparation.consumedTokens
          - preparation.reusedTokens,
        cachedPromptTokenCount: preparation.reusedTokens,
        generationTokenCount: info.generationTokenCount,
        promptTime: info.promptTime + preparation.preparationSeconds,
        generationTime: info.generateTime, stopReason: info.stopReason,
        rejectedToolCallCount: info.rejectedToolCallCount,
        recoveredToolCallCount: info.recoveredToolCallCount))
  }
}
