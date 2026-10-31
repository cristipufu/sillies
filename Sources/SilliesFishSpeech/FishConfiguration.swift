import Foundation

/// The supported S2 Pro architecture, independent of downloaded tensor data.
package struct FishConfiguration: Decodable, Sendable {
  struct Transformer: Decodable, Sendable {
    let dim: Int
    let nLayer: Int
    let nHead: Int
    let nLocalHeads: Int
    let headDim: Int
    let intermediateSize: Int
    let vocabSize: Int
    let ropeBase: Float
    let normEps: Float
    let attentionQkNorm: Bool
    let attentionQkvBias: Bool
    let attentionOBias: Bool
    let tieWordEmbeddings: Bool
    let useMoe: Bool
    let numCodebooks: Int?
  }

  struct Quantization: Decodable, Sendable {
    let groupSize: Int
    let bits: Int
    let mode: String
  }

  static let codebookCount = 10
  static let semanticVocabularySize = 4_096
  static let residualVocabularySize = 1_024
  package static let sampleRate = 44_100
  static let samplesPerFrame = 2_048
  static let maximumPromptTokens = 1_024
  static let maximumAudioFrames = 800
  static let maximumContextTokens = maximumPromptTokens + maximumAudioFrames

  let modelType: String
  let textConfig: Transformer
  let audioDecoderConfig: Transformer
  let quantization: Quantization
  let semanticStartTokenId: Int
  let semanticEndTokenId: Int
  let eosTokenId: Int

  package static func decode(_ data: Data) throws -> Self {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let configuration = try decoder.decode(Self.self, from: data)
    try configuration.validate()
    return configuration
  }

  private func validate() throws {
    guard modelType == "fish_qwen3_omni", quantization.bits == 8,
      quantization.groupSize == 64, quantization.mode == "affine",
      semanticStartTokenId == 151_678, semanticEndTokenId == 155_773,
      eosTokenId == 151_645,
      textConfig.nLayer == 36, textConfig.vocabSize == 155_776,
      textConfig.attentionQkNorm, textConfig.tieWordEmbeddings,
      audioDecoderConfig.nLayer == 4,
      audioDecoderConfig.vocabSize == Self.semanticVocabularySize,
      audioDecoderConfig.numCodebooks == Self.codebookCount,
      !audioDecoderConfig.attentionQkNorm, !audioDecoderConfig.tieWordEmbeddings
    else { throw FishError.unsupportedConfiguration }
    for transformer in [textConfig, audioDecoderConfig] {
      guard transformer.dim == 2_560, transformer.nHead == 32,
        transformer.nLocalHeads == 8, transformer.headDim == 128,
        transformer.intermediateSize == 9_728, transformer.ropeBase == 1_000_000,
        transformer.normEps == 1e-6, !transformer.attentionQkvBias,
        !transformer.attentionOBias, !transformer.useMoe
      else { throw FishError.unsupportedConfiguration }
    }
  }
}
