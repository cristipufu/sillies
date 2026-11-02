import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SilliesTextModels

/// The helper alone imports MLX. A model fault or cancelled kernel cannot terminate the app.
actor MLXTextRuntime {
  private static let maximumOutputTokens = 1_400
  private static let maximumPromptCharacters = 24_000
  private static let promptTailTokenCount = 64
  private static let cacheBytes = 128 * 1024 * 1024
  private var model: ModelContainer?
  private var directory: URL?

  func generate(_ request: TextInferenceRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
    let configuration = request.configuration
    let generation = request.generation
    guard configuration.directory.isFileURL, (2_048...8_192).contains(configuration.contextTokens),
      (1...Self.maximumOutputTokens).contains(generation.maximumTokens),
      generation.instructions.count
        + generation.messages.reduce(
          0, { $0 + $1.content.count + ($1.reasoningContent?.count ?? 0) })
        <= Self.maximumPromptCharacters
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
        additionalContext: MLXReasoningPolicy(preparation: configuration).templateContext))
    if generation.operation == .measure {
      return .init(text: "", inputTokens: input.text.tokens.size)
    }
    let outputTokens = generation.maximumTokens + (configuration.reasoning?.tokenReserve ?? 0)
    guard input.text.tokens.size + outputTokens <= configuration.contextTokens else {
      throw TextModelError.contextLimit
    }
    var parameters = GenerateParameters(
      maxTokens: outputTokens, maxKVSize: configuration.contextTokens,
      temperature: Float(generation.style.temperature),
      topP: Float(generation.style.probabilityThreshold),
      repetitionPenalty: generation.style.repetitionPenalty,
      repetitionContextSize: generation.style.repetitionContextSize)
    parameters.prefill = PrefillParameters(stepSize: 64)
    let promptTailTokens = Array(
      input.text.tokens.asArray(Int.self).suffix(Self.promptTailTokenCount))
    let promptTail = await container.tokenizer.decode(tokenIds: promptTailTokens)
    var collector = await MLXGenerationCollector(
      style: generation.style,
      channel: .init(configuration: container.configuration, promptTail: promptTail))
    let stream = try await container.generate(
      input: input, parameters: parameters, tools: tools.isEmpty ? nil : tools)
    defer { Memory.clearCache() }
    for await event in stream {
      try Task.checkCancellation()
      if let delta = try collector.consume(event) { try await receive(delta) }
    }
    return try await collector.finish(receive: receive)
  }

  private func load(_ preparation: TextModelPreparation) async throws -> ModelContainer {
    let location = preparation.directory
    if directory == location, let model { return model }
    model = nil
    Memory.clearCache()
    let loaded = try await LLMModelFactory.shared.loadContainer(
      from: location, using: LocalTokenizerLoader())
    await loaded.update {
      $0.processor = MLXInputProcessor(base: $0.processor)
      if let reasoning = MLXReasoningPolicy(preparation: preparation).configuration {
        $0.configuration.reasoningConfig = reasoning
      }
    }
    directory = location
    model = loaded
    return loaded
  }
}
