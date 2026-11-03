import MLX
import MLXLMCommon
import SilliesTextModels

/// Exercises the exact native processor decorator without model weights or a network connection.
enum TextInputSelfCheck {
  static func run() async throws {
    let base = CountingProcessor()
    let processor = MLXInputProcessor(base: base)
    func input(_ content: String, context: [String: any Sendable] = ["enable_thinking": false])
      -> UserInput
    {
      UserInput(chat: [.system("Be helpful"), .user(content)], additionalContext: context)
    }
    let first = try await processor.prepare(input: input("One"))
    let repeatInput = try await processor.prepare(input: input("One"))
    guard first.text.tokens.asArray(Int.self) == repeatInput.text.tokens.asArray(Int.self),
      await base.count.value == 1
    else { throw TextModelError.invalidResponse }
    _ = try await processor.prepare(input: input("Two"))
    _ = try await processor.prepare(input: input("Two", context: ["enable_thinking": true]))
    guard await base.count.value == 3 else { throw TextModelError.invalidResponse }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await processor.prepare(input: input("Two", context: ["enable_thinking": true]))
        .text.tokens.size
    }
    do {
      _ = try await task.value
      throw TextModelError.invalidResponse
    } catch is CancellationError {}
    let bounded = MLXBudgetedInputProcessor(base: processor, maximumTokens: 0)
    do {
      _ = try await bounded.prepare(input: input("One"))
      throw TextModelError.invalidResponse
    } catch TextModelError.contextLimit {}
  }
}

private final class CountingProcessor: UserInputProcessor {
  let count = ProcessorCount()
  func prepare(input: UserInput) async throws -> LMInput {
    let value = await count.increment()
    return LMInput(tokens: MLXArray([value]))
  }
}

private actor ProcessorCount {
  private(set) var value = 0
  func increment() -> Int {
    value += 1
    return value
  }
}
