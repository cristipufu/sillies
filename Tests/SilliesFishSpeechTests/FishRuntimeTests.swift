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

  @Test func compiledSpeechRotaryMatchesIndependentRoundedPairReference() throws {
    let dimensions = 8
    let positions = 64
    let frequencies =
      1
      / pow(
        MLXArray(Float(10_000)), arange(0, dimensions, step: 2).asType(.float32) / Float(dimensions)
      )
    let angles = outer(arange(positions).asType(.float32), frequencies)
    let cosine = cos(angles).asType(.bfloat16).asArray(Float.self)
    let sine = sin(angles).asType(.bfloat16).asArray(Float.self)
    let rotary = FishRotaryEmbedding(
      headDimensions: dimensions, positions: positions, base: 10_000, precision: .speech)
    for length in [3, 1, 7, 1] {
      let input = sin(arange(2 * length * dimensions).asType(.float32) * 0.173)
        .asType(.bfloat16).reshaped(1, 2, length, dimensions)
      let samples = input.asArray(Float.self)
      for offset in [0, 1, 31] {
        var expected: [Float] = []
        for index in stride(from: 0, to: samples.count, by: 2) {
          let token = (index / dimensions) % length
          let pair = (index % dimensions) / 2
          let coefficient = (offset + token) * (dimensions / 2) + pair
          let even = samples[index]
          let odd = samples[index + 1]
          expected.append(even * cosine[coefficient] - odd * sine[coefficient])
          expected.append(odd * cosine[coefficient] + even * sine[coefficient])
        }
        let rounded = MLXArray(expected).asType(.bfloat16).asArray(Float.self)
        #expect(try rotary.apply(input, offset: offset).asArray(Float.self) == rounded)
      }
    }
  }
}

extension FishRuntimeTests {
  @Test func profilingReportsInclusiveStagesAndResetsBetweenRequests() throws {
    var clock: TimeInterval = 10
    let profile = FishProfiler(
      configuration: .init(directory: URL(fileURLWithPath: "/unused"), mode: .natural, seed: 123),
      now: { clock })
    profile.begin(.loading)
    profile.measure(.codecTotal) {
      clock += 1
      profile.measure(.codecOutput) { clock += 2 }
      clock += 1
    }
    let first = try #require(profile.report())
    #expect(first.elapsedSeconds == 4)
    #expect(first.stages["codecTotal"]?.totalSeconds == 4)
    #expect(first.stages["codecOutput"]?.totalSeconds == 2)
    profile.begin(.loading)
    #expect(profile.report()?.stages.isEmpty == true)
    #expect(profile.report()?.elapsedSeconds == 0)
  }

  @Test func disabledProfilingDoesNotReadTheClockOrChangeTheResult() {
    let profile = FishProfiler(now: {
      Issue.record("Disabled diagnostics must not read a clock")
      return 0
    })
    profile.begin(.loading)
    #expect(profile.measure(.slowStep) { 42 } == 42)
    #expect(profile.report() == nil)
    profile.finish()
  }

  @Test func streamingConvolutionMatchesIndependentCausalReferenceAcrossDilatedBoundaries() throws {
    let input = MLXArray((1...23).map(Float.init)).reshaped(1, 1, 23)
    let weight = MLXArray([Float(1), 2, 3]).reshaped(1, 1, 3)
    let weights = FishWeights(tensors: [
      "test.conv.weight": weight, "test.conv.bias": MLXArray([Float(0.5)]),
    ])
    for dilation in [1, 3, 9] {
      let padding = MLXArray.zeros([1, 1, 2 * dilation])
      let reference =
        conv1d(
          concatenated([padding, input], axis: 2).transposed(0, 2, 1),
          weight.transposed(0, 2, 1), dilation: dilation) + 0.5
      let decoder = FishCodecConvolution(weights: weights)
      var chunks: [MLXArray] = []
      for range in [0..<1, 1..<4, 4..<7, 7..<23] {
        chunks.append(
          try decoder.forward(
            input[0..., 0..., range], at: "test.conv", geometry: .init(dilation: dilation)))
        decoder.materializeHistory()
      }
      #expect(concatenated(chunks, axis: 2).asArray(Float.self) == reference.asArray(Float.self))
      decoder.reset()
      #expect(
        try decoder.forward(input, at: "test.conv", geometry: .init(dilation: dilation)).asArray(
          Float.self) == reference.asArray(Float.self))
    }
  }

  @Test func streamingUpsamplingMatchesIndependentTransposedConvolution() throws {
    let input = MLXArray((1...11).map { Float($0) / 11 }).reshaped(1, 1, 11)
    for stride in [2, 4, 8] {
      let weight = MLXArray((1...(stride * 2)).map { Float($0) / 10 }).reshaped(1, 1, stride * 2)
      let weights = FishWeights(tensors: [
        "test.conv.weight": weight, "test.conv.bias": MLXArray([Float(0.5)]),
      ])
      let full =
        convTransposed1d(
          input.transposed(0, 2, 1), weight.transposed(1, 2, 0), stride: stride, outputPadding: 1)
        + 0.5
      let expected = full[0..., 0..<(11 * stride), 0...].asArray(Float.self)
      let decoder = FishCodecConvolution(weights: weights)
      var chunks: [MLXArray] = []
      for range in [0..<1, 1..<3, 3..<11] {
        chunks.append(
          try decoder.upsample(input[0..., 0..., range], at: "test.conv", stride: stride))
        decoder.materializeHistory()
      }
      let actual = concatenated(chunks, axis: 2).asArray(Float.self)
      #expect(actual.count == expected.count)
      #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.00001 })
    }
  }

  @Test func streamingCodecAttentionMatchesWholeSequenceAcrossSlidingWindowBoundary() throws {
    let weights = FishWeights(tensors: Self.codecAttentionWeights())
    let input = sin(arange(132 * 1_024).asType(.float32) * 0.003).reshaped(1, 132, 1_024)
      .transposed(0, 2, 1)
    let whole = try FishCodecTransformer(weights: weights).apply(input).asArray(Float.self)
    let streaming = FishCodecTransformer(weights: weights)
    var chunks: [MLXArray] = []
    for range in [0..<9, 9..<129, 129..<132] {
      let chunk = try streaming.apply(input[0..., 0..., range])
      eval(chunk)
      streaming.materializeHistory()
      chunks.append(chunk)
    }
    let actual = concatenated(chunks, axis: 2).asArray(Float.self)
    #expect(actual.count == whole.count)
    let error = zip(actual, whole).map { abs($0 - $1) }.max() ?? .infinity
    #expect(error < 0.0001, "Maximum codec streaming error: \(error)")
    streaming.reset()
    let restarted = try streaming.apply(input).asArray(Float.self)
    #expect(zip(restarted, whole).allSatisfy { abs($0 - $1) < 0.0001 })
  }

  private static func codecAttentionWeights() -> [String: MLXArray] {
    let width = 1_024
    let identity = eye(width)
    let projection = concatenated([identity * 0.2, identity * 0.3, identity * 0.4], axis: 0)
    let ones = MLXArray.ones([width])
    let zeros = MLXArray.zeros([width])
    var tensors: [String: MLXArray] = [
      "quantizer.post_module.norm.weight": ones, "quantizer.post_module.norm.bias": zeros,
    ]
    for index in 0..<8 {
      let path = "quantizer.post_module.layers.\(index)"
      for norm in ["attention_norm", "ffn_norm"] {
        tensors[path + ".\(norm).weight"] = ones
        tensors[path + ".\(norm).bias"] = zeros
      }
      tensors[path + ".attention.wqkv.weight"] = projection
      tensors[path + ".attention.wo.weight"] = identity
      tensors[path + ".attention_layer_scale.gamma"] = ones * 0.1
      tensors[path + ".ffn_layer_scale.gamma"] = ones * 0.1
      tensors[path + ".feed_forward.w1.weight"] = MLXArray.zeros([4, width])
      tensors[path + ".feed_forward.w3.weight"] = MLXArray.zeros([4, width])
      tensors[path + ".feed_forward.w2.weight"] = MLXArray.zeros([width, 4])
    }
    return tensors
  }
}
