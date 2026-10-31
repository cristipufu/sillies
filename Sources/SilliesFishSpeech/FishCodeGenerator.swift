import Foundation
import MLX

/// Slow autoregression advances time; the fast transformer fills the remaining codebooks.
final class FishCodeGenerator {
  private static let repetitionWindow = 10
  private let configuration: FishConfiguration
  private let weights: FishWeights
  private let semanticHead: FishWeights
  private let slow: FishTransformer
  private let fast: FishTransformer

  init(configuration: FishConfiguration, weights: FishWeights) throws {
    self.configuration = configuration
    self.weights = weights
    let allowedTokens =
      [configuration.eosTokenId]
      + Array(configuration.semanticStartTokenId...configuration.semanticEndTokenId)
    semanticHead = try weights.selectingOutputRows(
      allowedTokens.map(Int32.init), at: "model.embeddings")
    slow = FishTransformer(
      weights: weights, configuration: configuration.textConfig, prefix: "model.")
    fast = FishTransformer(
      weights: weights, configuration: configuration.audioDecoderConfig, prefix: "model.fast_")
  }

  func generate(prompt: [Int32]) throws -> [[Int32]] {
    slow.reset()
    defer {
      slow.reset()
      fast.reset()
    }
    let embedded = try weights.embedding(MLXArray(prompt).reshaped(1, -1), at: "model.embeddings")
    var hidden = try slow.apply(embedded)[0..., (prompt.count - 1)..<prompt.count, 0...]
    var previousSemantics: [Int32] = []
    var frames: [[Int32]] = []
    for _ in 0..<FishConfiguration.maximumAudioFrames {
      try Task.checkCancellation()
      let logits = try semanticHead.linear(hidden, at: "output").reshaped(1, -1)
      var choice = try FishSampling.sample(logits)
      if previousSemantics.contains(choice), choice != 0 {
        choice = try FishSampling.sample(logits, settings: .repetitionRecovery)
      }
      if choice == 0 {
        guard !frames.isEmpty else { throw FishError.emptyAudio }
        return frames
      }
      previousSemantics.append(choice)
      if previousSemantics.count > Self.repetitionWindow { previousSemantics.removeFirst() }
      let code = choice - 1
      let frame = try generateFrame(semanticCode: code, hidden: hidden)
      frames.append(frame)
      let next = try audioEmbedding(frame)
      hidden = try slow.apply(next)
      eval(hidden)
    }
    throw FishError.generationLimit
  }

  private func generateFrame(semanticCode: Int32, hidden: MLXArray) throws -> [Int32] {
    fast.reset()
    let prefill = try fast.apply(hidden)
    eval(prefill)
    var codes = [semanticCode]
    var previous = semanticCode
    for _ in 1..<FishConfiguration.codebookCount {
      let embedded = try weights.embedding(
        MLXArray([previous]).reshaped(1, 1), at: "model.fast_embeddings")
      let output = try fast.apply(embedded)
      let logits = try weights.linear(output, at: "model.fast_output").reshaped(1, -1)
      previous = try FishSampling.sample(logits)
      codes.append(previous)
    }
    return codes
  }

  private func audioEmbedding(_ frame: [Int32]) throws -> MLXArray {
    guard let first = frame.first, frame.count == FishConfiguration.codebookCount else {
      throw FishError.emptyAudio
    }
    let semanticID = first + Int32(configuration.semanticStartTokenId)
    let embedded = try weights.embedding(
      MLXArray([semanticID]).reshaped(1, 1), at: "model.embeddings")
    var codebookSum = MLXArray.zeros(embedded.shape, dtype: .float32)
    for (index, code) in frame.enumerated() {
      let offset = Int32(index * FishConfiguration.semanticVocabularySize)
      let value = try weights.embedding(
        MLXArray([code + offset]).reshaped(1, 1), at: "model.codebook_embeddings")
      codebookSum = codebookSum + value.asType(.float32)
    }
    let scale = MLXArray(sqrt(Float(FishConfiguration.codebookCount + 1))).asType(embedded.dtype)
    return (embedded + codebookSum.asType(embedded.dtype)) / scale
  }
}
