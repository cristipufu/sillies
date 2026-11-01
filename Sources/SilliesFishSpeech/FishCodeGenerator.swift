import Foundation
import MLX

/// Slow autoregression advances time; the fast transformer fills the remaining codebooks.
final class FishCodeGenerator {
  private static let repetitionWindow = 10
  private static let framesPerChunk = 4
  private let configuration: FishConfiguration
  private let weights: FishWeights
  private let semanticHead: FishWeights
  private let slow: FishTransformer
  private let fast: FishTransformer
  private let profile: FishProfiler

  init(configuration: FishConfiguration, weights: FishWeights, profile: FishProfiler) throws {
    self.profile = profile
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
    var frames: [[Int32]] = []
    try stream(prompt: prompt) { frames.append(contentsOf: $0) }
    return frames
  }

  func stream(prompt: [Int32], receive: ([[Int32]]) throws -> Void) throws {
    slow.reset()
    defer {
      slow.reset()
      fast.reset()
    }
    var hidden = try profile.tensor(.promptPrefill) {
      let embedded = try weights.embedding(MLXArray(prompt).reshaped(1, -1), at: "model.embeddings")
      return try slow.apply(embedded)[0..., (prompt.count - 1)..<prompt.count, 0...]
    }
    var previousSemantics: [Int32] = []
    var frames: [[Int32]] = []
    for index in 0..<FishConfiguration.maximumAudioFrames {
      try Task.checkCancellation()
      let logits = try profile.tensor(.semanticLogits) {
        try semanticHead.linear(hidden, at: "output").reshaped(1, -1)
      }
      var choice = try profile.measure(.semanticSampling) { try FishSampling.sample(logits) }
      if previousSemantics.contains(choice), choice != 0 {
        choice = try profile.measure(.semanticResampling) {
          try FishSampling.sample(logits, settings: .repetitionRecovery)
        }
      }
      if choice == 0 {
        guard index > 0 else { throw FishError.emptyAudio }
        if !frames.isEmpty { try receive(frames) }
        return
      }
      previousSemantics.append(choice)
      if previousSemantics.count > Self.repetitionWindow { previousSemantics.removeFirst() }
      let code = choice - 1
      let frame = try generateFrame(semanticCode: code, hidden: hidden)
      frames.append(frame)
      if frames.count == Self.framesPerChunk {
        try receive(frames)
        frames.removeAll(keepingCapacity: true)
      }
      let next = try profile.tensor(.audioEmbedding) { try audioEmbedding(frame) }
      hidden = try profile.measure(.slowStep) {
        let result = try profile.measure(.slowGraph) { try slow.apply(next) }
        profile.measure(.slowEvaluation) { eval(result) }
        return result
      }
    }
    throw FishError.generationLimit
  }

  private func generateFrame(semanticCode: Int32, hidden: MLXArray) throws -> [Int32] {
    try profile.measure(.fastPrefill) {
      fast.reset()
      let prefill = try fast.apply(hidden)
      eval(prefill)
    }
    var codes = [semanticCode]
    var previous = semanticCode
    for _ in 1..<FishConfiguration.codebookCount {
      let output = try profile.tensor(.fastForward) {
        let embedded = try weights.embedding(
          MLXArray([previous]).reshaped(1, 1), at: "model.fast_embeddings")
        return try fast.apply(embedded)
      }
      let logits = try profile.tensor(.fastLogits) {
        try weights.linear(output, at: "model.fast_output").reshaped(1, -1)
      }
      previous = try profile.measure(.fastSampling) { try FishSampling.sample(logits) }
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
