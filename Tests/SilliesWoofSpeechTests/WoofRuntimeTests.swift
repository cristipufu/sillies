import Foundation
import MLX
import SilliesTTS
import Testing

@testable import SilliesWoofSpeech

@Suite(.serialized) struct WoofRuntimeTests {
  init() throws {
    let library = Bundle.module.bundleURL.deletingLastPathComponent()
      .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
    try #require(FileManager.default.fileExists(atPath: library.path))
    GPU.metallib = library
  }

  @Test func archiveDecompressesChecksumsAndNeverExtractsFiles() throws {
    let url = try #require(
      Bundle.module.url(forResource: "arrays", withExtension: "npz", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let arrays = try WoofTensorArchive(data: data).arrays()
    let weights = WoofWeights(arrays: arrays)
    #expect(try weights.tensor(.init(name: "values")).asArray(Float.self) == [4, 7])
    #expect(throws: WoofModelError.archiveLimit) {
      try WoofTensorArchive(data: data, limits: .init(maximumExpandedBytes: 1)).arrays()
    }
    var damaged = data
    damaged[50] ^= 0x01
    #expect(throws: WoofModelError.self) { try WoofTensorArchive(data: damaged).arrays() }
    #expect(throws: WoofModelError.self) {
      try weights.tensor(.init(name: "values"), shape: [Int.max])
    }
  }

  @Test func causalConvolutionMatchesIndependentReferenceAcrossChunks() throws {
    let layer = try WoofCodecConvolution(
      weight: MLXArray([Float(1), 2, 3]).reshaped(1, 1, 3), bias: MLXArray([Float(0.5)]),
      operation: .causal)
    let input = MLXArray([Float(1), 2, 4, 8, 16]).reshaped(5, 1)
    let expected: [Float] = [3.5, 8.5, 17.5, 34.5, 68.5]
    let first = try layer(input[..<2]).asArray(Float.self)
    let second = try layer(input[2...]).asArray(Float.self)
    #expect(first + second == expected)
    layer.reset()
    #expect(try layer(input).asArray(Float.self) == expected)
  }

  @Test func upsamplingCarriesPreviousTailWithoutDuplicatingBias() throws {
    let layer = try WoofCodecConvolution(
      weight: MLXArray([Float(1), 2, 3, 4]).reshaped(1, 1, 4), bias: MLXArray([Float(0.5)]),
      operation: .upsample(stride: 2))
    let input = MLXArray([Float(1), 2, 4]).reshaped(3, 1)
    let expected: [Float] = [1.5, 2.5, 5.5, 8.5, 10.5, 16.5]
    var samples: [Float] = []
    for index in 0..<3 { samples += try layer(input[index..<(index + 1)]).asArray(Float.self) }
    #expect(samples == expected)
    layer.reset()
    #expect(try layer(input).asArray(Float.self) == expected)
  }

  @Test func slidingAttentionUsesPastWindowAndRespectsChunkCausality() {
    let input = MLXArray([Float(1), 2, 3, 4, 5]).reshaped(1, 1, 5, 1)
    let queries = MLXArray.zeros([1, 1, 5, 1])
    var cache = WoofAttentionCache()
    let full = cache.attend(queries: queries, newKeys: input, newValues: input, window: 2).asArray(
      Float.self)
    #expect(full == [1, 1.5, 2.5, 3.5, 4.5])
    cache = WoofAttentionCache()
    var streamed: [Float] = []
    for range in [0..<1, 1..<3, 3..<5] {
      streamed += cache.attend(
        queries: queries[0..., 0..., range, 0...], newKeys: input[0..., 0..., range, 0...],
        newValues: input[0..., 0..., range, 0...], window: 2
      ).asArray(Float.self)
      cache.materialize()
    }
    #expect(streamed == full)
  }

}
