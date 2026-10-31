import Foundation
import MLX
import Testing

@testable import SilliesFishSpeech

@Suite(.serialized) struct FishRuntimeTests {
  init() throws {
    // Test runners can prevent MLX's dladdr-based default bundle discovery.
    let library = Bundle.module.bundleURL.deletingLastPathComponent()
      .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
    try #require(FileManager.default.fileExists(atPath: library.path))
    GPU.metallib = library
  }

  @Test func rejectsUnsupportedArchitectureBeforeAllocatingTensors() throws {
    let url = try #require(
      Bundle.module.url(forResource: "config", withExtension: "json", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    _ = try FishConfiguration.decode(data)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var text = try #require(object["text_config"] as? [String: Any])
    for invalid in [0, -1, Int.max, 1_000_000] {
      text["n_layer"] = invalid
      object["text_config"] = text
      let malformed = try JSONSerialization.data(withJSONObject: object)
      #expect(throws: FishError.self) { try FishConfiguration.decode(malformed) }
    }
    object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var audio = try #require(object["audio_decoder_config"] as? [String: Any])
    audio["num_codebooks"] = Int.max
    object["audio_decoder_config"] = audio
    #expect(throws: FishError.self) {
      try FishConfiguration.decode(JSONSerialization.data(withJSONObject: object))
    }
  }

  @Test func malformedTensorDimensionsThrowBeforeCallingMLX() throws {
    let weights = FishWeights(tensors: ["projection.weight": MLXArray.ones([2, 3])])
    #expect(throws: FishError.self) { try weights.linear(MLXArray.ones([1, 4]), at: "projection") }
    #expect(throws: FishError.self) { try weights.linear(MLXArray.ones([1, 3]), at: "missing") }
    #expect(throws: FishError.self) {
      try weights.selectingOutputRows([Int32.max], at: "projection")
    }
  }

  @Test func affineProjectionAndOutputSelectionPreserveRows() throws {
    let weights = FishWeights(tensors: [
      "projection.weight": MLXArray([Float(1), 2, 3, 4, 5, 6]).reshaped(3, 2),
      "projection.bias": MLXArray([Float(10), 20, 30]),
    ])
    let input = MLXArray([Float(2), 3]).reshaped(1, 2)
    #expect(try weights.linear(input, at: "projection").asArray(Float.self) == [18, 38, 58])
    let selected = try weights.selectingOutputRows([2, 0], at: "projection")
    #expect(try selected.linear(input, at: "output").asArray(Float.self) == [28, 8])
  }

  @Test func causalConvolutionNeverReadsFutureSamples() throws {
    let weights = FishWeights(tensors: [
      "test.conv.weight": MLXArray([Float(1), 2, 3]).reshaped(1, 1, 3),
      "test.conv.bias": MLXArray([Float(0)]),
    ])
    let convolution = FishCodecConvolution(weights: weights)
    let input = MLXArray([Float(1), 2, 100]).reshaped(1, 1, 3)
    let output = try convolution.forward(input, at: "test.conv").asArray(Float.self)
    #expect(output == [3, 8, 305])
  }

  @Test func rotaryPairsPreserveNormAndRejectContextOverflow() throws {
    let rotary = FishRotaryEmbedding(
      headDimensions: 2, positions: 4, base: 10_000, precision: .codec)
    let input = MLXArray([Float(3), 4]).reshaped(1, 1, 1, 2)
    let rotated = try rotary.apply(input, offset: 1).asArray(Float.self)
    #expect(abs(rotated[0] * rotated[0] + rotated[1] * rotated[1] - 25) < 0.0001)
    #expect(throws: FishError.self) { try rotary.apply(input, offset: 4) }
    #expect(throws: FishError.self) { try rotary.apply(input, offset: -1) }
  }

  @Test func audioDecoderRejectsUnboundedOrIncompleteFrames() throws {
    let decoder = FishAudioDecoder(tensors: [:])
    #expect(throws: FishError.self) { try decoder.decode([]) }
    #expect(throws: FishError.self) { try decoder.decode([[1, 2]]) }
    let frame = Array(repeating: Int32(0), count: FishConfiguration.codebookCount)
    #expect(throws: FishError.self) {
      try decoder.decode(Array(repeating: frame, count: FishConfiguration.maximumAudioFrames + 1))
    }
  }
}
