import Foundation
import MLX

/// Decode-only S1 DAC. Reference-audio encoding and training layers are deliberately absent.
final class FishAudioDecoder {
  private static let decoderRates = [8, 8, 4, 2]
  private static let residualDilations = [1, 3, 9]
  private static let latentUpsampleStages = 2
  private static let latentUpsampleFactor = 2
  private static let layerNormalizationEpsilon: Float = 1e-6
  private let weights: FishWeights
  private let convolution: FishCodecConvolution
  private let transformer: FishCodecTransformer
  private var decodedFrames = 0

  init(tensors: [String: MLXArray]) {
    weights = FishWeights(tensors: tensors)
    convolution = FishCodecConvolution(weights: weights)
    transformer = FishCodecTransformer(weights: weights)
  }

  func reset() {
    decodedFrames = 0
    convolution.reset()
    transformer.reset()
  }

  func decode(_ frames: [[Int32]]) throws -> [Float] {
    reset()
    defer { reset() }
    return try decodeNext(frames)
  }

  func decodeNext(_ frames: [[Int32]]) throws -> [Float] {
    guard !frames.isEmpty, frames.count <= FishConfiguration.maximumAudioFrames,
      decodedFrames <= FishConfiguration.maximumAudioFrames - frames.count,
      frames.allSatisfy({ $0.count == FishConfiguration.codebookCount })
    else { throw FishError.emptyAudio }
    var hidden = try decodeCodebooks(frames)
    hidden = try transformer.apply(hidden)
    for stage in 0..<Self.latentUpsampleStages {
      let path = "quantizer.upsample.\(stage)"
      hidden = try convolution.upsample(
        hidden, at: path + ".0.conv", stride: Self.latentUpsampleFactor)
      hidden = try convNext(hidden, at: path + ".1")
    }
    hidden = try convolution.forward(hidden, at: "decoder.model.0")
    for (index, stride) in Self.decoderRates.enumerated() {
      try Task.checkCancellation()
      hidden = try decoderBlock(hidden, at: "decoder.model.\(index + 1).block", stride: stride)
      eval(hidden)
    }
    hidden = try convolution.snake(hidden, at: "decoder.model.5")
    hidden = try convolution.forward(hidden, at: "decoder.model.6")
    let sampleCount = frames.count * FishConfiguration.samplesPerFrame
    guard hidden.shape[0...1] == [1, 1], hidden.dim(2) >= sampleCount else {
      throw FishError.emptyAudio
    }
    let audio = tanh(hidden)[0, 0, 0..<sampleCount].asType(.float32)
    eval(audio)
    try Task.checkCancellation()
    decodedFrames += frames.count
    return audio.asArray(Float.self)
  }

  private func decodeCodebooks(_ frames: [[Int32]]) throws -> MLXArray {
    var sum: MLXArray?
    for index in 0..<FishConfiguration.codebookCount {
      let path =
        index == 0
        ? "quantizer.semantic_quantizer.quantizers.0"
        : "quantizer.quantizer.quantizers.\(index - 1)"
      let maximum =
        index == 0
        ? FishConfiguration.semanticVocabularySize : FishConfiguration.residualVocabularySize
      let tokens = frames.map { min(max($0[index], 0), Int32(maximum - 1)) }
      let embedded = try weights.embedding(MLXArray(tokens).reshaped(1, -1), at: path + ".codebook")
        .transposed(0, 2, 1)
      let decoded = try convolution.forward(embedded, at: path + ".out_proj")
      sum = sum.map { $0 + decoded } ?? decoded
    }
    guard let sum else { throw FishError.emptyAudio }
    return sum
  }

  private func convNext(_ input: MLXArray, at path: String) throws -> MLXArray {
    var hidden = try convolution.forward(
      input, at: path + ".dwconv.conv", geometry: .init(groups: input.dim(1))
    )
    .transposed(0, 2, 1)
    hidden = try MLXFast.layerNorm(
      hidden, weight: weights.vector(path + ".norm.weight", count: hidden.dim(2)),
      bias: weights.vector(path + ".norm.bias", count: hidden.dim(2)),
      eps: Self.layerNormalizationEpsilon)
    hidden = try weights.linear(hidden, at: path + ".pwconv1")
    hidden = hidden * (1 + erf(hidden / sqrt(Float(2)))) / 2
    hidden = try weights.linear(hidden, at: path + ".pwconv2")
    hidden = try hidden * weights.vector(path + ".gamma", count: hidden.dim(2))
    return input + hidden.transposed(0, 2, 1)
  }

  private func decoderBlock(_ input: MLXArray, at path: String, stride: Int) throws -> MLXArray {
    var hidden = try convolution.snake(input, at: path + ".0")
    hidden = try convolution.upsample(hidden, at: path + ".1", stride: stride)
    for (index, dilation) in Self.residualDilations.enumerated() {
      hidden = try residualUnit(hidden, at: path + ".\(index + 2).block", dilation: dilation)
    }
    return hidden
  }

  private func residualUnit(_ input: MLXArray, at path: String, dilation: Int) throws -> MLXArray {
    var hidden = try convolution.snake(input, at: path + ".0")
    hidden = try convolution.forward(hidden, at: path + ".1", geometry: .init(dilation: dilation))
    hidden = try convolution.snake(hidden, at: path + ".2")
    hidden = try convolution.forward(hidden, at: path + ".3")
    guard input.shape == hidden.shape else { throw FishError.invalidTensor(path) }
    return input + hidden
  }
}
