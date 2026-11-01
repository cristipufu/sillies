import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SilliesTextModels

/// The helper alone imports MLX. A model fault or cancelled kernel cannot terminate the app.
actor MLXTextRuntime {
  private static let maximumOutputTokens = 1_400
  private static let maximumPromptCharacters = 24_000
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
      generation.instructions.count + generation.messages.reduce(0, { $0 + $1.content.count })
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
    let container = try await load(configuration.directory)
    let tools = MLXConversationInput.tools(generation)
    if !tools.isEmpty, await container.configuration.toolCallFormat == nil {
      throw TextModelError.toolsUnavailable
    }
    let input = try await container.prepare(
      input: UserInput(
        chat: try MLXConversationInput.messages(generation), tools: tools.isEmpty ? nil : tools,
        additionalContext: ["enable_thinking": false]))
    if generation.operation == .measure {
      return .init(text: "", inputTokens: input.text.tokens.size)
    }
    guard input.text.tokens.size + generation.maximumTokens <= configuration.contextTokens else {
      throw TextModelError.contextLimit
    }
    var parameters = GenerateParameters(
      maxTokens: generation.maximumTokens, maxKVSize: configuration.contextTokens,
      temperature: Float(generation.style.temperature),
      topP: Float(generation.style.probabilityThreshold),
      repetitionPenalty: generation.style.repetitionPenalty,
      repetitionContextSize: generation.style.repetitionContextSize)
    parameters.prefill = PrefillParameters(stepSize: 64)
    let stream = try await container.generate(
      input: input, parameters: parameters, tools: tools.isEmpty ? nil : tools)
    var output = ""
    var calls: [TextGenerationOutput.Call] = []
    var completed = false
    var batch = TextStreamBatch()
    for await event in stream {
      try Task.checkCancellation()
      switch event {
      case .chunk(let text):
        output += text
        if let delta = batch.append(text) { try await receive(delta) }
        if generation.style == .conversation, TextRepetitionGuard.containsLoop(output) {
          throw TextModelError.repetitiveResponse
        }
      case .info(let info):
        guard case .stop = info.stopReason else { throw TextModelError.invalidResponse }
        completed = true
      case .toolCall(let call):
        calls.append(
          .init(
            id: call.id ?? UUID().uuidString, name: call.function.name,
            arguments: try JSONEncoder().encode(call.function.arguments)))
      case .rejectedToolCall: throw TextModelError.invalidResponse
      }
      guard output.utf8.count <= TextInferenceWire.maximumMessageBytes / 2 else {
        throw TextModelError.invalidResponse
      }
    }
    guard completed else { throw TextModelError.invalidResponse }
    if let delta = batch.flush() { try await receive(delta) }
    Memory.clearCache()
    return .init(text: output.trimmingCharacters(in: .whitespacesAndNewlines), calls: calls)
  }

  private func load(_ location: URL) async throws -> ModelContainer {
    if directory == location, let model { return model }
    model = nil
    Memory.clearCache()
    let loaded = try await LLMModelFactory.shared.loadContainer(
      from: location, using: LocalTokenizerLoader())
    directory = location
    model = loaded
    return loaded
  }
}
