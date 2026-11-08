import MLX

struct WoofLinear {
  let weight: MLXArray
  let bias: MLXArray?
  var inputDimensions: Int { weight.dim(1) }
  var outputDimensions: Int { weight.dim(0) }

  init(weight: MLXArray, bias: MLXArray? = nil) throws {
    guard weight.ndim == 2, weight.shape.allSatisfy({ $0 > 0 }),
      bias == nil || bias?.shape == [weight.dim(0)]
    else { throw WoofModelError.invalidConfiguration }
    self.weight = weight
    self.bias = bias
    eval(weight)
    if let bias { eval(bias) }
  }

  func validate(input: Int, output: Int) throws {
    guard inputDimensions == input, outputDimensions == output else {
      throw WoofModelError.invalidConfiguration
    }
  }

  func callAsFunction(_ input: MLXArray) -> MLXArray {
    let result = matmul(input, weight.T)
    return bias.map { result + $0 } ?? result
  }
}
