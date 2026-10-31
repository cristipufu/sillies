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
  private static let maximumMemoryBytes = 12 * 1024 * 1024 * 1024
  private var model: ModelContainer?
  private var directory: URL?

  func generate(_ request: TextInferenceRequest) async throws -> String {
    let configuration = request.configuration
    let generation = request.generation
    guard configuration.directory.isFileURL, (2_048...8_192).contains(configuration.contextTokens),
      (1...Self.maximumOutputTokens).contains(generation.maximumTokens),
      generation.instructions.count + generation.prompt.count <= Self.maximumPromptCharacters
    else { throw TextModelError.invalidResponse }
    Memory.cacheLimit = Self.cacheBytes
    Memory.memoryLimit = min(
      Self.maximumMemoryBytes, Int(ProcessInfo.processInfo.physicalMemory / 2))
    let container = try await load(configuration.directory)
    let input = try await container.prepare(
      input: UserInput(
        chat: [.system(generation.instructions), .user(generation.prompt)],
        additionalContext: ["enable_thinking": false]))
    guard input.text.tokens.size + generation.maximumTokens <= configuration.contextTokens else {
      throw TextModelError.unavailable(
        "This passage exceeds the local model’s context. Try a shorter passage.")
    }
    var parameters = GenerateParameters(
      maxTokens: generation.maximumTokens, maxKVSize: configuration.contextTokens, temperature: 0)
    parameters.prefill = PrefillParameters(stepSize: 64)
    let stream = try await container.generate(input: input, parameters: parameters)
    var output = ""
    var completed = false
    for await event in stream {
      try Task.checkCancellation()
      switch event {
      case .chunk(let text): output += text
      case .info(let info):
        guard case .stop = info.stopReason else { throw TextModelError.invalidResponse }
        completed = true
      case .toolCall, .rejectedToolCall: throw TextModelError.invalidResponse
      }
      guard output.utf8.count <= TextInferenceWire.maximumMessageBytes / 2 else {
        throw TextModelError.invalidResponse
      }
    }
    guard completed else { throw TextModelError.invalidResponse }
    Memory.clearCache()
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
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
