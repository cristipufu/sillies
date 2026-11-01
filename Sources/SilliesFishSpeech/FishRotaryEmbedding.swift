import MLX

/// Fish uses interleaved rotary pairs, with bfloat16 trigonometric values for the speech transformer.
struct FishRotaryEmbedding {
  enum Precision { case speech, codec }
  private let cosines: MLXArray
  private let sines: MLXArray
  private let rotate: @Sendable (MLXArray, MLXArray, MLXArray) -> MLXArray

  init(headDimensions: Int, positions: Int, base: Float, precision: Precision) {
    let frequencies =
      1
      / pow(
        MLXArray(base), arange(0, headDimensions, step: 2, dtype: .float32) / Float(headDimensions))
    let angles = outer(arange(positions, dtype: .float32), frequencies)
    let dtype: DType = precision == .speech ? .bfloat16 : .float32
    cosines = cos(angles).asType(dtype)
    sines = sin(angles).asType(dtype)
    rotate = compile(Self.rotatePairs)
  }

  func apply(_ input: MLXArray, offset: Int) throws -> MLXArray {
    guard input.ndim == 4, offset >= 0, input.dim(2) <= cosines.dim(0) - offset,
      input.dim(3) == cosines.dim(1) * 2
    else { throw FishError.generationLimit }
    let length = input.dim(2)
    let cosine = cosines[offset..<(offset + length)].reshaped(1, 1, length, -1)
    let sine = sines[offset..<(offset + length)].reshaped(1, 1, length, -1)
    // Compile the repeated one-token decode shape; varying prompt/chunk lengths must not grow
    // a cache of specialized graphs for every utterance length in a long-running conversation.
    if length == 1 { return rotate(input, cosine, sine) }
    return Self.rotatePairs(input, cosine, sine)
  }

  private static func rotatePairs(_ input: MLXArray, _ cosine: MLXArray, _ sine: MLXArray)
    -> MLXArray
  {
    let pairs = input.asType(.float32).reshaped(input.shape.dropLast() + [input.dim(3) / 2, 2])
    let even = pairs[0..., 0..., 0..., 0..., 0]
    let odd = pairs[0..., 0..., 0..., 0..., 1]
    return stacked([even * cosine - odd * sine, odd * cosine + even * sine], axis: -1)
      .reshaped(input.shape).asType(input.dtype)
  }
}
