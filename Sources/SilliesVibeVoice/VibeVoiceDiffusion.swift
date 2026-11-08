import MLX

struct VibeVoiceDiffusion {
  private struct Block {
    let norm: MLXArray
    let modulation: VibeVoiceLinear
    let gate: VibeVoiceLinear
    let up: VibeVoiceLinear
    let down: VibeVoiceLinear
  }
  private static let timeEmbeddingDimensions = 256
  private static let timeEmbeddingPeriod: Float = 10_000
  // Microsoft uses five diffusion steps and guidance 1.5 in its realtime demo.
  static let realtimeSteps = 5
  private static let guidance: Float = 1.5
  private let configuration: VibeVoiceConfiguration.Diffusion
  private let input: VibeVoiceLinear
  private let condition: VibeVoiceLinear
  private let output: VibeVoiceLinear
  private let finalModulation: VibeVoiceLinear
  private let blocks: [Block]
  private let schedule: VibeVoiceDiffusionSchedule
  private let timeEmbeddings: [MLXArray]
  private let unitScale: MLXArray

  init(
    configuration: VibeVoiceConfiguration.Diffusion, weights: VibeVoiceWeights,
    inferenceSteps: Int = Self.realtimeSteps
  ) throws {
    self.configuration = configuration
    let size = configuration.dimensions
    let feedForward = Int(Float(size) * configuration.expansion)
    let prefix = "prediction_head."
    input = try weights.linear(
      prefix + "noisy_images_proj", input: configuration.latentDimensions, output: size)
    condition = try weights.linear(prefix + "cond_proj", input: size, output: size)
    output = try weights.linear(
      prefix + "final_layer.linear", input: size, output: configuration.latentDimensions)
    finalModulation = try weights.linear(
      prefix + "final_layer.adaLN_modulation.layers.1", input: size, output: size * 2)
    unitScale = MLXArray.ones([size])
    schedule = try VibeVoiceDiffusionSchedule(
      trainingSteps: configuration.trainingSteps, inferenceSteps: inferenceSteps)
    let timeInput = try weights.linear(
      prefix + "t_embedder.mlp.layers.0", input: Self.timeEmbeddingDimensions, output: size)
    let timeOutput = try weights.linear(
      prefix + "t_embedder.mlp.layers.2", input: size, output: size)
    let half = Self.timeEmbeddingDimensions / 2
    let frequencies = exp(
      arange(half).asType(.float32) * (-log(MLXArray(Self.timeEmbeddingPeriod)) / Float(half)))
    timeEmbeddings = schedule.steps.map { step in
      let angles = frequencies * Float(step.timestep)
      let embedding = timeInput(
        concatenated([cos(angles), sin(angles)]).reshaped(1, Self.timeEmbeddingDimensions))
      let result = timeOutput(embedding * sigmoid(embedding))
      eval(result)
      return result
    }
    blocks = try (0..<configuration.layers).map { index in
      let path = "\(prefix)layers.\(index)"
      return try Block(
        norm: weights.tensor(path + ".norm.weight", shape: [size]),
        modulation: weights.linear(
          path + ".adaLN_modulation.layers.1", input: size, output: size * 3),
        gate: weights.linear(path + ".ffn.gate_proj", input: size, output: feedForward),
        up: weights.linear(path + ".ffn.up_proj", input: size, output: feedForward),
        down: weights.linear(path + ".ffn.down_proj", input: feedForward, output: size))
    }
  }

  func sample(positive: MLXArray, negative: MLXArray, noise: MLXArray) throws -> MLXArray {
    guard positive.shape == [1, configuration.dimensions], negative.shape == positive.shape,
      noise.shape == [1, configuration.latentDimensions]
    else { throw VibeVoiceError.invalidTensor("diffusion inputs") }
    let conditioning = condition(concatenated([positive, negative], axis: 0))
    var current = noise
    var previous: MLXArray?
    for (index, step) in schedule.steps.enumerated() {
      try Task.checkCancellation()
      let both = concatenated([current, current], axis: 0)
      let velocity = predict(both, conditioning: conditioning + timeEmbeddings[index])
      let guided = velocity[1..<2] + Self.guidance * (velocity[0..<1] - velocity[1..<2])
      current = schedule.advance(current, velocity: guided, step: step, previous: &previous)
      eval(current)
    }
    return current
  }

  private func predict(_ noise: MLXArray, conditioning: MLXArray) -> MLXArray {
    let activated = conditioning * sigmoid(conditioning)
    let dimensions = configuration.dimensions
    var hidden = input(noise)
    for block in blocks {
      let parameters = block.modulation(activated)
      let normalized = MLXFast.rmsNorm(
        hidden, weight: block.norm, eps: configuration.normalizationEpsilon)
      let modulated =
        normalized * (1 + parameters[0..., dimensions..<(2 * dimensions)])
        + parameters[0..., ..<dimensions]
      let gate = block.gate(modulated)
      hidden =
        hidden + parameters[0..., (2 * dimensions)...]
        * block.down(gate * sigmoid(gate) * block.up(modulated))
    }
    let parameters = finalModulation(activated)
    let normalized = MLXFast.rmsNorm(
      hidden, weight: unitScale, eps: configuration.normalizationEpsilon)
    return output(
      normalized * (1 + parameters[0..., dimensions...]) + parameters[0..., ..<dimensions])
  }
}
