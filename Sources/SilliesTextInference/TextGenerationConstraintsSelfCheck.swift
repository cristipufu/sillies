import Foundation
import MLX
import MLXLMCommon
import SilliesTextModels

/// Exercises checkpoint validation and the actual pre-sampling GPU processor without model weights.
enum TextGenerationConstraintsSelfCheck {
  private enum Failure: Error {
    case expectation(line: UInt)
    case acceptedInvalidMetadata
  }

  static func run() throws {
    try checkSampling()
    try checkPenaltyComposition()
    try checkInvalidTokens()
    try checkMetadata()
  }

  private static func checkSampling() throws {
    let constraints = try CheckpointGenerationConstraints.validated(
      tokens: [1, 3, 1], vocabularySize: 4)
    try require(constraints.suppressedTokens == [1, 3])
    let parameters = GenerateParameters(temperature: 0)
    guard let processor = constraints.components.logitProcessor(parameters: parameters) else {
      throw Failure.expectation(line: #line)
    }
    let scores = MLXArray([Float(2), 100, 4, 50])
    for input in [scores, scores.asType(.float16), stacked([scores, scores])] {
      let output = processor.process(logits: input)
      let values = output.asArray(Float.self)
      try require(output.shape == input.shape && output.dtype == input.dtype)
      try require(
        values.enumerated().allSatisfy { index, value in
          [1, 3].contains(index % 4)
            ? value == -Float.infinity : value == [Float(2), 100, 4, 50][index % 4]
        })
      try require(
        parameters.sampler().sample(logits: output).asArray(Int.self).allSatisfy { $0 == 2 })
    }
    try require(
      CheckpointGenerationConstraints.unconstrained.components.logitProcessor(
        parameters: parameters) == nil)
  }

  private static func checkPenaltyComposition() throws {
    let constraints = try CheckpointGenerationConstraints.validated(tokens: [1], vocabularySize: 3)
    let parameters = GenerateParameters(
      temperature: 0, repetitionPenalty: 2, repetitionContextSize: 4)
    guard var processor = constraints.components.logitProcessor(parameters: parameters) else {
      throw Failure.expectation(line: #line)
    }
    processor.prompt(MLXArray([Int32(0)]))
    let output = processor.process(logits: MLXArray([Float(8), 100, 6]).reshaped(1, 3))
    try require(output.asArray(Float.self) == [4, -Float.infinity, 6])
    try require(parameters.sampler().sample(logits: output).item(Int.self) == 2)
  }

  private static func checkInvalidTokens() throws {
    for tokens in [[-1], [4], [Int.max], [0, 1, 2, 3]] {
      try rejects {
        _ = try CheckpointGenerationConstraints.validated(tokens: tokens, vocabularySize: 4)
      }
    }
    for vocabulary in [0, -1, Int.max] {
      try rejects {
        _ = try CheckpointGenerationConstraints.validated(tokens: [0], vocabularySize: vocabulary)
      }
    }
    try rejects {
      _ = try CheckpointGenerationConstraints.validated(
        tokens: Array(repeating: 1, count: 4_097), vocabularySize: 8)
    }
  }

  private static func checkMetadata() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      do { try FileManager.default.removeItem(at: directory) } catch {
        fputs("Cannot remove synthetic generation metadata: \(error)\n", stderr)
      }
    }
    try require(try CheckpointGenerationConstraints.load(from: directory).suppressedTokens.isEmpty)
    let generation = directory.appendingPathComponent("generation_config.json")
    let model = directory.appendingPathComponent("config.json")
    for source in ["{}", #"{"suppress_tokens":null}"#, #"{"suppress_tokens":[]}"#] {
      try Data(source.utf8).write(to: generation)
      try require(
        try CheckpointGenerationConstraints.load(from: directory).suppressedTokens.isEmpty)
    }
    try Data(#"{"suppress_tokens":[3]}"#.utf8).write(to: generation)
    try Data(#"{"text_config":{"vocab_size":4}}"#.utf8).write(to: model)
    try require(try CheckpointGenerationConstraints.load(from: directory).suppressedTokens == [3])
    try Data(#"{"vocab_size":4}"#.utf8).write(to: model)
    try require(try CheckpointGenerationConstraints.load(from: directory).suppressedTokens == [3])
    try Data("{}".utf8).write(to: model)
    try rejects { _ = try CheckpointGenerationConstraints.load(from: directory) }
    try FileManager.default.removeItem(at: model)
    try rejects { _ = try CheckpointGenerationConstraints.load(from: directory) }
    try Data(#"{"vocab_size":4}"#.utf8).write(to: model)
    for source in ["{", #"{"suppress_tokens":"3"}"#, #"{"suppress_tokens":[4]}"#] {
      try Data(source.utf8).write(to: generation)
      try rejects { _ = try CheckpointGenerationConstraints.load(from: directory) }
    }
    try Data(repeating: 32, count: 1_024 * 1_024 + 1).write(to: generation)
    try rejects { _ = try CheckpointGenerationConstraints.load(from: directory) }
  }

  private static func rejects(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw Failure.acceptedInvalidMetadata
  }

  private static func require(_ condition: Bool, line: UInt = #line) throws {
    guard condition else { throw Failure.expectation(line: line) }
  }
}
