import Foundation
import MLX
import Testing

@testable import SilliesVibeVoice

@Suite(.serialized) struct VibeVoiceRuntimeTests {
  init() throws {
    let library = Bundle.module.bundleURL.deletingLastPathComponent()
      .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
    try #require(FileManager.default.fileExists(atPath: library.path))
    GPU.metallib = library
  }

  @Test func diffusionMatchesThePublishedSchedulerAtEveryStep() throws {
    struct Reference: Decodable {
      struct Step: Decodable {
        let timestep: Int
        let velocity: [Float]
        let result: [Float]
      }
      let input: [Float]
      let steps: [Step]
    }
    let url = try #require(
      Bundle.module.url(forResource: "schedule", withExtension: "json", subdirectory: "Fixtures"))
    let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    let scheduler = try VibeVoiceDiffusionSchedule(
      trainingSteps: 1_000, inferenceSteps: reference.steps.count)
    #expect(scheduler.steps.map(\.timestep) == reference.steps.map(\.timestep))
    var sample = MLXArray(reference.input).reshaped(1, -1)
    var previous: MLXArray?
    for (step, expected) in zip(scheduler.steps, reference.steps) {
      sample = scheduler.advance(
        sample, velocity: MLXArray(expected.velocity).reshaped(1, -1), step: step,
        previous: &previous)
      let actual = sample.asArray(Float.self)
      for (value, expectedValue) in zip(actual, expected.result) {
        #expect(abs(value - expectedValue) < 1e-5)
      }
    }
    #expect(throws: VibeVoiceError.self) {
      try VibeVoiceDiffusionSchedule(trainingSteps: 0, inferenceSteps: 5)
    }
  }

  @Test func causalAndUpsamplingConvolutionsPreserveChunkBoundaries() throws {
    let causal = try VibeVoiceConvolution(
      weight: MLXArray([Float(1), 2, 3]).reshaped(1, 3, 1), bias: MLXArray([Float(0.5)]),
      operation: .causal(groups: 1))
    let input = MLXArray([Float(1), 2, 4]).reshaped(1, 3, 1)
    let first = try causal(input[0..., ..<1, 0...]).asArray(Float.self)
    let second = try causal(input[0..., 1..., 0...]).asArray(Float.self)
    #expect(first + second == [3.5, 8.5, 17.5])
    causal.reset()
    #expect(try causal(input).asArray(Float.self) == first + second)
    let upsample = try VibeVoiceConvolution(
      weight: MLXArray([Float(1), 2, 3, 4]).reshaped(1, 4, 1), bias: MLXArray([Float(0.5)]),
      operation: .upsample(stride: 2))
    let beginning = try upsample(input[0..., ..<1, 0...]).asArray(Float.self)
    let rest = try upsample(input[0..., 1..., 0...]).asArray(Float.self)
    #expect(beginning + rest == [1.5, 2.5, 5.5, 8.5, 10.5, 16.5])
    upsample.reset()
    #expect(try upsample(input).asArray(Float.self) == beginning + rest)
    #expect(throws: VibeVoiceError.self) { try upsample(MLXArray.zeros([1, 2, 2])) }
  }

  @Test func tensorValidationRejectsMalformedQuantizationBeforeCallingMLX() throws {
    let quantization = try JSONDecoder().decode(
      VibeVoiceConfiguration.Quantization.self,
      from: Data(#"{"bits":4,"group_size":64,"mode":"affine"}"#.utf8))
    let weights = VibeVoiceWeights(
      tensors: [
        "projection.weight": MLXArray.zeros([2, 8], dtype: .uint32),
        "projection.scales": MLXArray.ones([2, 1]),
        "projection.biases": MLXArray.zeros([2, 2]),
      ], quantization: quantization)
    #expect(throws: VibeVoiceError.self) { try weights.linear("projection", input: 64, output: 2) }
    for invalid in [
      #"{"bits":0,"group_size":64,"mode":"affine"}"#,
      #"{"bits":4,"group_size":0,"mode":"affine"}"#,
      #"{"bits":4,"group_size":64,"mode":"unknown"}"#,
    ] {
      let setting = try JSONDecoder().decode(
        VibeVoiceConfiguration.Quantization.self, from: Data(invalid.utf8))
      let malformed = VibeVoiceWeights(tensors: weights.tensors, quantization: setting)
      #expect(throws: VibeVoiceError.self) {
        try malformed.linear("projection", input: 64, output: 2)
      }
    }
  }

  @Test(arguments: [4, 8]) func supportedQuantizationPreservesProjectionAndEmbedding(bits: Int)
    throws
  {
    let settings = VibeVoiceConfiguration.Quantization(bits: bits, groupSize: 64, mode: "affine")
    let packed: UInt32 = bits == 4 ? 0x1111_1111 : 0x0101_0101
    let weights = VibeVoiceWeights(
      tensors: [
        "projection.weight": MLXArray(
          Array(repeating: packed, count: 2 * 64 / (32 / bits))
        ).reshaped(2, -1),
        "projection.scales": MLXArray.full([2, 1], values: MLXArray(Float(0.5))),
        "projection.biases": MLXArray.full([2, 1], values: MLXArray(Float(-0.25))),
      ], quantization: settings)
    let projection = try weights.linear("projection", input: 64, output: 2)
    #expect(projection(MLXArray.ones([1, 64])).asArray(Float.self) == [16, 16])
    let embedding = try weights.embedding("projection", rows: 2, dimensions: 64)
    #expect(try embedding([1]).asArray(Float.self) == Array(repeating: Float(0.25), count: 64))
  }

  @Test func unsupportedArchitecturesFailBeforeTensorLoading() throws {
    let url = try #require(
      Bundle.module.url(forResource: "config", withExtension: "json", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    try JSONDecoder().decode(VibeVoiceConfiguration.self, from: data).validate()
    let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for (section, field, value) in [
      ("decoder_config", "num_attention_heads", 0 as Any),
      ("decoder_config", "use_sliding_window", true),
      ("acoustic_tokenizer_config", "conv_bias", false),
      ("acoustic_tokenizer_config", "conv_norm", "weight_norm"),
      ("acoustic_tokenizer_config", "layernorm_elementwise_affine", false),
      ("acoustic_tokenizer_config", "decoder_ratios", [Int.max]),
      ("diffusion_head_config", "prediction_type", "epsilon"),
      ("quantization", "bits", 0),
    ] {
      var changed = original
      var values = try #require(changed[section] as? [String: Any])
      values[field] = value
      changed[section] = values
      let encoded = try JSONSerialization.data(withJSONObject: changed)
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(VibeVoiceConfiguration.self, from: encoded).validate()
      }
    }
  }
}
