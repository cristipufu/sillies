import MLX

enum FishSampling {
  struct Settings {
    let temperature: Float
    let probability: Float
    static let speech = Self(temperature: 0.7, probability: 0.7)
    static let repetitionRecovery = Self(temperature: 1, probability: 0.9)
  }
  private static let candidateLimit = 50
  private static let minimumNoise: Float = 1e-6

  static func sample(_ logits: MLXArray, settings: Settings = .speech) throws -> Int32 {
    let result = try sampleTensor(logits, settings: settings)
    eval(result)
    try Task.checkCancellation()
    return result.item(Int32.self)
  }

  /// Keep dependent codebook choices on the GPU until the complete frame is needed by the codec.
  static func sampleTensor(_ logits: MLXArray, settings: Settings = .speech) throws -> MLXArray {
    try Task.checkCancellation()
    guard logits.ndim == 2, logits.dim(0) == 1, logits.dim(1) > 0 else {
      throw FishError.invalidTensor("generation logits")
    }
    let order = argSort(-logits, axis: -1)
    let sorted = takeAlong(logits, order, axis: -1)
    let cumulative = cumsum(softmax(sorted, axis: -1), axis: -1)
    let ranks = arange(logits.dim(1)).reshaped(1, -1)
    let keep =
      ((cumulative .<= settings.probability) .&& (ranks .< candidateLimit)) .|| (ranks .== 0)
    let filtered = MLX.where(keep, sorted / settings.temperature, MLXArray(-Float.infinity))
    let probabilities = softmax(filtered, axis: -1)
    let noise = -log(MLXRandom.uniform(low: minimumNoise, high: 1, probabilities.shape))
    let position = argMax(probabilities / noise, axis: -1).reshaped(1, 1)
    return takeAlong(order, position, axis: -1).asType(.int32)
  }
}
