import Foundation
import MLX
import SilliesTTS

final class WoofLatentGenerator {
  private static let noiseDeviation: Float = 0.5
  private static let endProbability: Float = 0.9
  private static let minimumFrameIndex = 3
  private static let framesPerChunk = 2
  private let configuration: WoofConfiguration
  private let transformer: WoofSpeechTransformer
  private let flow: WoofFlowHead
  private let textEmbedding: MLXArray
  private let beginningOfSpeech: MLXArray
  private let latentInput: WoofLinear

  init(configuration: WoofConfiguration, weights: WoofWeights) throws {
    self.configuration = configuration
    transformer = try WoofSpeechTransformer(configuration: configuration.speech, weights: weights)
    flow = try WoofFlowHead(configuration: configuration.speech, weights: weights)
    textEmbedding = try weights.tensor(
      configuration.speech.textEmbedding,
      shape: [WoofTextEncoder.vocabularySize, configuration.speech.transformer.dimensions])
    beginningOfSpeech = try weights.tensor(
      configuration.speech.beginningOfSpeech, shape: [configuration.speech.transformer.dimensions])
    latentInput = try weights.linear(configuration.speech.latentInput)
    try latentInput.validate(
      input: configuration.speech.transformer.latentDimensions,
      output: configuration.speech.transformer.dimensions)
    eval(textEmbedding, beginningOfSpeech)
  }

  func stream(text: String, voice: MLXArray, seed: UInt32, receive: (MLXArray) throws -> Void)
    throws
  {
    transformer.reset()
    defer { transformer.reset() }
    let ids = WoofTextEncoder.encode(text)
    let prefix = concatenated(
      [voice, textEmbedding[MLXArray(ids)], beginningOfSpeech.expandedDimensions(axis: 0)], axis: 0)
    let maximumFrames = min(
      configuration.maximumFrames, WoofConfiguration.maximumContext - prefix.dim(0))
    guard maximumFrames > Self.minimumFrameIndex else { throw WoofModelError.invalidConfiguration }
    var condition = flow.condition(try transformer(prefix)[prefix.dim(0) - 1])
    var random = WoofGaussianNoise(seed: seed)
    var pending: [MLXArray] = []
    let endThreshold = log(Self.endProbability / (1 - Self.endProbability))
    for index in 0..<maximumFrames {
      try Task.checkCancellation()
      if index > Self.minimumFrameIndex, condition.endLogit > endThreshold { break }
      let noise = try MLXArray(
        random.samples(
          count: configuration.speech.transformer.latentDimensions,
          standardDeviation: Self.noiseDeviation))
      let latent = flow.latent(condition: condition.state, noise: noise)
      eval(latent)
      pending.append(latent)
      if pending.count == Self.framesPerChunk {
        try receive(stacked(pending))
        pending.removeAll(keepingCapacity: true)
      }
      let hidden = try transformer(latentInput(latent).expandedDimensions(axis: 0))[0]
      condition = flow.condition(hidden)
    }
    if !pending.isEmpty { try receive(stacked(pending)) }
    guard condition.endLogit > endThreshold else { throw TTSError.invalidRequest }
  }
}
