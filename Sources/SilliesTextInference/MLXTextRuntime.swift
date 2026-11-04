import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SilliesTextModels

/// The helper alone imports MLX. A model fault or cancelled kernel cannot terminate the app.
actor MLXTextRuntime {
  private static let promptTailTokenCount = 64
  private static let cacheBytes = 128 * 1024 * 1024
  private var model: ModelContainer?
  private var preparation: TextModelPreparation?
  private var inputProcessor: MLXInputProcessor?
  private let conversation = MLXNativeConversation()
  private var active = false
  private var constraints = CheckpointGenerationConstraints.unconstrained
  private let rejectionObserver: (@Sendable (RejectedToolCall) async -> Void)?
  private let timingObserver: TextPreparationTiming.Observer?

  init(
    rejectionObserver: (@Sendable (RejectedToolCall) async -> Void)? = nil,
    timingObserver: TextPreparationTiming.Observer? = nil
  ) {
    self.rejectionObserver = rejectionObserver
    self.timingObserver = timingObserver
  }

  func generate(_ request: TextInferenceRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
    guard !active else { throw TextModelError.busy }
    active = true
    defer { active = false }
    if request.generation.operation == .releaseSession {
      if let id = request.generation.sessionID { await conversation.release(id) }
      Memory.clearCache()
      return .init(text: "")
    }
    do { return try await perform(request, receive: receive) } catch {
      await conversation.clear()
      Memory.clearCache()
      throw error
    }
  }

  private struct PreparedGeneration {
    let input: LMInput
    let collector: MLXGenerationCollector
  }

  private func perform(_ request: TextInferenceRequest, receive: @escaping TextDeltaSink)
    async throws -> TextGenerationOutput
  {
    let plan = try MLXGenerationPlan(request)
    Memory.cacheLimit = Self.cacheBytes
    Memory.memoryLimit = request.configuration.memoryLimitBytes
    let loadStart = ContinuousClock.now
    let container = try await load(request.configuration)
    await timingObserver?(.init(.modelLoad, since: loadStart))
    let inputStart = ContinuousClock.now
    let input = try await prepareInput(plan, using: container)
    await timingObserver?(.init(.inputPreparation, since: inputStart))
    if request.generation.operation == .measure {
      return .init(text: "", inputTokens: input.text.tokens.size)
    }
    let promptTail = Array(input.text.tokens.asArray(Int.self).suffix(Self.promptTailTokenCount))
    let collector = await collector(
      promptTail: promptTail, style: request.generation.style, using: container)
    defer { Memory.clearCache() }
    if plan.usesNativeSession {
      return try await conversation.generate(
        .init(
          request: request.generation, model: container, parameters: plan.parameters,
          components: constraints.components, templateContext: plan.templateContext,
          collector: collector, rejectionObserver: rejectionObserver), receive: receive)
    }
    await conversation.clear()
    return try await stream(
      .init(input: input, collector: collector), plan: plan, using: container, receive: receive)
  }

  private func prepareInput(_ plan: MLXGenerationPlan, using container: ModelContainer)
    async throws -> sending LMInput
  {
    guard let inputProcessor else { throw TextModelError.invalidResponse }
    if let maximum = plan.maximumInputTokens {
      let bounded = MLXBudgetedInputProcessor(base: inputProcessor, maximumTokens: maximum)
      await container.update { $0.processor = bounded }
    } else {
      await container.update { $0.processor = inputProcessor }
    }
    if !plan.tools.isEmpty, await container.configuration.toolCallFormat == nil {
      throw TextModelError.toolsUnavailable
    }
    let messages = try await container.perform { context in
      let generator =
        context.configuration.messageGenerator
        ?? (context.model as? any LLMModel)?.messageGenerator(tokenizer: context.tokenizer)
        ?? DefaultMessageGenerator()
      return try MLXConversationInput.templateMessages(
        plan.request.generation, generator: generator)
    }
    return try await container.prepare(
      input: UserInput(
        messages: messages, tools: plan.tools.isEmpty ? nil : plan.tools,
        additionalContext: plan.templateContext))
  }

  private func collector(
    promptTail: [Int], style: TextGenerationStyle, using container: ModelContainer
  )
    async -> MLXGenerationCollector
  {
    let promptTail = await container.tokenizer.decode(tokenIds: promptTail)
    return await MLXGenerationCollector(
      style: style, channel: .init(configuration: container.configuration, promptTail: promptTail))
  }

  private func stream(
    _ prepared: sending PreparedGeneration, plan: MLXGenerationPlan,
    using container: ModelContainer,
    receive: @escaping TextDeltaSink
  ) async throws -> TextGenerationOutput {
    let components = constraints.components
    let stream = try await container.perform(nonSendable: prepared.input) { context, input in
      try MLXLMCommon.generate(
        input: input, parameters: plan.parameters, context: context, components: components,
        tools: plan.tools.isEmpty ? nil : plan.tools)
    }
    var collector = prepared.collector
    for await event in stream {
      try Task.checkCancellation()
      if case .rejectedToolCall(let rejection) = event { await rejectionObserver?(rejection) }
      if let delta = try collector.consume(event) { try await receive(delta) }
    }
    return try await collector.finish(receive: receive)
  }

  private func load(_ preparation: TextModelPreparation) async throws -> ModelContainer {
    let location = preparation.directory
    if self.preparation == preparation, let model { return model }
    await conversation.clear()
    model = nil
    inputProcessor = nil
    Memory.clearCache()
    let loadedConstraints = try CheckpointGenerationConstraints.load(from: location)
    let loaded = try await LLMModelFactory.shared.loadContainer(
      from: location,
      using: LocalTokenizerLoader(
        policy: preparation.profile.runtimePolicy, timingObserver: timingObserver))
    let processor = await MLXInputProcessor(base: loaded.processor)
    await loaded.update {
      $0.processor = processor
      if let reasoning = MLXReasoningPolicy(reasoning: preparation.reasoning).configuration {
        $0.configuration.reasoningConfig = reasoning
      }
    }
    self.preparation = preparation
    inputProcessor = processor
    constraints = loadedConstraints
    model = loaded
    return loaded
  }
}
