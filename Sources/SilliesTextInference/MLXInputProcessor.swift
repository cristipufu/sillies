import Foundation
import MLX
import MLXLMCommon

/// Shares one exact text-only tokenization between budget measurement and generation.
final class MLXInputProcessor: UserInputProcessor {
  private let base: any UserInputProcessor
  private let cache = TokenCache()

  init(base: any UserInputProcessor) { self.base = base }

  func prepare(input: UserInput) async throws -> LMInput {
    try Task.checkCancellation()
    let key = try Self.key(input)
    if let key, let tokens = await cache.tokens(for: key) {
      try Task.checkCancellation()
      return LMInput(tokens: MLXArray(tokens))
    }
    let prepared = try await base.prepare(input: input)
    try Task.checkCancellation()
    if let key, prepared.text.mask == nil, prepared.text.tokens.ndim == 1,
      prepared.image == nil, prepared.video == nil, prepared.audio == nil
    {
      await cache.store(prepared.text.tokens.asArray(Int.self), for: key)
    }
    return prepared
  }

  private static func key(_ input: UserInput) throws -> Data? {
    guard input.images.isEmpty, input.videos.isEmpty, input.audios.isEmpty else { return nil }
    var object: [String: Any] = [:]
    switch input.prompt {
    case .text(let text): object["text"] = text
    case .messages(let messages): object["messages"] = messages
    case .chat(let messages):
      guard messages.allSatisfy({ $0.images.isEmpty && $0.videos.isEmpty && $0.audios.isEmpty })
      else { return nil }
      object["chat"] = DefaultMessageGenerator().generate(messages: messages)
    }
    object["tools"] = input.tools ?? NSNull() as Any
    object["context"] = input.additionalContext ?? NSNull() as Any
    guard JSONSerialization.isValidJSONObject(object) else { return nil }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return data.count <= TokenCache.maximumKeyBytes ? data : nil
  }
}

private actor TokenCache {
  static let maximumKeyBytes = 64 * 1_024
  private static let maximumTokens = 8_192
  private var cached: (key: Data, tokens: [Int])?
  func tokens(for key: Data) -> [Int]? { cached?.key == key ? cached?.tokens : nil }
  func store(_ tokens: [Int], for key: Data) {
    cached = tokens.count <= Self.maximumTokens ? (key, tokens) : nil
  }
}
