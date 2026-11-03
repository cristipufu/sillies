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
  private var directory: URL?
  private var constraints = CheckpointGenerationConstraints.unconstrained
  private let rejectionObserver: (@Sendable (RejectedToolCall) async -> Void)?

  init(rejectionObserver: (@Sendable (RejectedToolCall) async -> Void)? = nil) {
    self.rejectionObserver = rejectionObserver
  }

  func generate(_ request: TextInferenceRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
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
    Memory.cacheLimit = Self.cacheBytes
    Memory.memoryLimit = configuration.memoryLimitBytes
    let container = try await load(configuration)
    let tools = MLXConversationInput.tools(generation)
    if !tools.isEmpty, await container.configuration.toolCallFormat == nil {
      throw TextModelError.toolsUnavailable
    }
    let messages = try await container.perform { context in
      let generator =
        context.configuration.messageGenerator
        ?? (context.model as? any LLMModel)?.messageGenerator(tokenizer: context.tokenizer)
        ?? DefaultMessageGenerator()
      return try MLXConversationInput.templateMessages(generation, generator: generator)
    }
    let input = try await container.prepare(
      input: UserInput(
        messages: messages,
        tools: tools.isEmpty ? nil : tools,
        additionalContext: MLXReasoningPolicy(reasoning: configuration.reasoning).templateContext))
    if generation.operation == .measure {
      return .init(text: "", inputTokens: input.text.tokens.size)
    }
    guard
      outputTokens <= configuration.contextTokens
        && input.text.tokens.size <= configuration.contextTokens - outputTokens
    else {
      throw TextModelError.contextLimit
    }
    let sampling = task.sampling
    var parameters = GenerateParameters(
      maxTokens: outputTokens, maxKVSize: configuration.contextTokens,
      temperature: sampling.temperature, topP: sampling.topP, topK: sampling.topK,
      repetitionPenalty: sampling.repetitionPenalty,
      repetitionContextSize: task.repetitionContextTokens)
    parameters.prefill = PrefillParameters(stepSize: configuration.profile.prefill.chunkTokens)
    let promptTailTokens = Array(
      input.text.tokens.asArray(Int.self).suffix(Self.promptTailTokenCount))
    let promptTail = await container.tokenizer.decode(tokenIds: promptTailTokens)
    var collector = await MLXGenerationCollector(
      style: generation.style,
      channel: .init(configuration: container.configuration, promptTail: promptTail))
    let selectedParameters = parameters
    let components = constraints.components
    let stream = try await container.perform(nonSendable: input) { context, input in
      try MLXLMCommon.generate(
        input: input, parameters: selectedParameters, context: context, components: components,
        tools: tools.isEmpty ? nil : tools)
    }
    defer { Memory.clearCache() }
    for await event in stream {
      try Task.checkCancellation()
      if case .rejectedToolCall(let rejection) = event { await rejectionObserver?(rejection) }
      if let delta = try collector.consume(event) { try await receive(delta) }
    }
    return try await collector.finish(receive: receive)
  }

  private func load(_ preparation: TextModelPreparation) async throws -> ModelContainer {
    let location = preparation.directory
    if directory == location, let model { return model }
    model = nil
    Memory.clearCache()
    let loadedConstraints = try CheckpointGenerationConstraints.load(from: location)
    let loaded = try await LLMModelFactory.shared.loadContainer(
      from: location, using: LocalTokenizerLoader())
    await loaded.update {
      $0.processor = MLXInputProcessor(base: $0.processor)
      if let reasoning = MLXReasoningPolicy(reasoning: preparation.reasoning).configuration {
        $0.configuration.reasoningConfig = reasoning
      }
    }
    directory = location
    constraints = loadedConstraints
    model = loaded
    return loaded
  }
}
