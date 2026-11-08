import Foundation
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import SilliesCore
import SilliesSearchModels
import Tokenizers

struct E5SearchEmbedding: PreparedEmbeddingModel {
  private static let maximumTokens = 512
  let model: EmbedderModelContainer
  let identity: String
  static func load(directory: URL, identity: String) async throws -> Self {
    let model = try await EmbedderModelFactory.shared.loadContainer(
      from: directory, using: #huggingFaceTokenizerLoader())
    return Self(model: model, identity: "\(identity)/\(EmbeddingPreparation.revision)")
  }
  func embed(_ input: SearchEmbeddingInput) async throws -> SearchEmbedding? {
    try await EmbeddingPreparation.embed(input, encode: encode)
  }

  private func encode(_ input: SearchEmbeddingInput) async throws -> EmbeddingChunkResult {
    try await model.perform { context in
      let tokens = context.tokenizer.encode(
        text: input.purpose.rawValue + ": " + input.text, addSpecialTokens: true)
      guard !tokens.isEmpty else { return .unsupported }
      guard tokens.count <= Self.maximumTokens else { return .exceedsCapacity }
      let ids = MLXArray(tokens)[.newAxis]
      let mask = MLXArray.ones(like: ids)
      let output = context.model(
        ids, positionIds: nil,
        tokenTypeIds: MLXArray.zeros(like: ids), attentionMask: mask)
      let vector = context.pooling(output, mask: mask, normalize: false, applyLayerNorm: false)
      eval(vector)
      return try .embedded(
        EmbeddingChunk(
          space: identity, mean: vector.asArray(Float.self), tokenCount: tokens.count))
    }
  }
}
