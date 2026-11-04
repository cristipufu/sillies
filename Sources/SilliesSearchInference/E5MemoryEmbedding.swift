import Foundation
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import SilliesCore
import Tokenizers

struct E5MemoryEmbedding: PreparedEmbeddingModel {
  private static let maximumTokens = 512
  let model: EmbedderModelContainer
  let identity: String
  static func load(directory: URL, identity: String) async throws -> Self {
    let model = try await EmbedderModelFactory.shared.loadContainer(
      from: directory, using: #huggingFaceTokenizerLoader())
    return Self(model: model, identity: identity)
  }
  func embed(_ input: MemoryEmbeddingInput) async throws -> MemoryEmbedding? {
    try await model.perform { context in
      let tokens = context.tokenizer.encode(
        text: input.purpose.rawValue + ": " + input.text, addSpecialTokens: true)
      // Do not silently index a truncated fact as though the whole fact were represented.
      guard !tokens.isEmpty, tokens.count <= Self.maximumTokens else { return nil }
      let ids = MLXArray(tokens)[.newAxis]
      let mask = MLXArray.ones(like: ids)
      let output = context.model(
        ids, positionIds: nil,
        tokenTypeIds: MLXArray.zeros(like: ids), attentionMask: mask)
      let vector = context.pooling(output, mask: mask, normalize: true, applyLayerNorm: false)
      eval(vector)
      return try MemoryEmbedding(space: identity, values: vector.asArray(Float.self))
    }
  }
}
